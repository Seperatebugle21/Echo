import AVFoundation
import OSLog

protocol EqualizedAudioPlayerDelegate: AnyObject {
    @MainActor func audioPlayerDidFinishPlaying(_ player: EqualizedAudioPlayer, successfully flag: Bool)
}
enum LocalPlaybackState: String, Sendable {
    case idle, preparing, playing, paused, seeking, transitioning, recovering, failed
    var isBusy: Bool { self == .preparing || self == .seeking || self == .recovering }
}

struct LocalPlaybackUpdate: Sendable {
    var state: LocalPlaybackState
    var position: Double
    var duration: Double
    var rate: Double
    var wantsPlayback: Bool
    var intentRevision: UInt64
}

/// UI snapshots never wait on decoding or graph operations. Each deck decodes on
/// its own serial queue; one control queue owns AVAudioEngine and scheduling.
final class EqualizedAudioPlayer: @unchecked Sendable {
    weak var delegate: EqualizedAudioPlayerDelegate?
    var onPromote: (@MainActor (UUID) -> Void)?
    var onStarted: (@MainActor (UUID?) -> Void)?
    var onStateChanged: (@MainActor (LocalPlaybackUpdate) -> Void)?
    /// Latency to the first advancing render frame, including opening/seek work.
    var onFirstRender: (@MainActor (Double) -> Void)?
    private struct Snapshot {
        var state: LocalPlaybackState = .idle
        var position = 0.0, duration = 0.0, rate = 1.0
        var generation = UUID(), identity = UUID()
        var canPrepare = false
        var wantsPlayback = false
        var intentRevision: UInt64 = 0
    }
    private let lock = NSLock()
    private var cached = Snapshot(), commandVersion: UInt64 = 0, mediaVersion: UInt64 = 0
    private let control = DispatchQueue(label: "com.echomusic.audio-control", qos: .userInitiated)
    private let opening = DispatchQueue(label: "com.echomusic.audio-open", qos: .userInitiated, attributes: .concurrent)
    private let logger = Logger(subsystem: "com.echomusic.app", category: "Playback")
    private var graph: Graph?, decks: [Deck?] = [nil, nil], active = 0
    private var generation = UUID(), wantsPlayback = false, preparedNext: UUID?, currentURL: URL?
    private var playbackIdentity = UUID()
    private var intentRevision: UInt64 = 0
    private var state: LocalPlaybackState = .idle
    private var transitionActive = false, recovered = false, interruptionResume = false
    private var lastProgress = 0.0
    private var awaitingRenderMeasurement = true
    private var progressDate = ProcessInfo.processInfo.systemUptime, requestDate = ProcessInfo.processInfo.systemUptime
    private var monitor: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    #if DEBUG
    private var injectedEmptyReads = 0
    func injectTemporaryEmptyBuffers(_ count: Int) { control.async { [weak self] in self?.injectedEmptyReads = max(0, count) } }
    func injectEngineStall() { control.async { [weak self] in self?.graph?.nodes.forEach { $0.pause() } } }
    #endif

    private final class Graph {
        let engine = AVAudioEngine(), eq = AVAudioUnitEQ(numberOfBands: 6), sum = AVAudioMixerNode()
        let nodes = [AVAudioPlayerNode(), AVAudioPlayerNode()]
        let pitches = [AVAudioUnitTimePitch(), AVAudioUnitTimePitch()]
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        init() {
            engine.attach(eq); engine.attach(sum)
            for i in 0..<2 {
                engine.attach(nodes[i]); engine.attach(pitches[i]); pitches[i].bypass = true
                engine.connect(nodes[i], to: pitches[i], format: format)
                engine.connect(pitches[i], to: sum, fromBus: 0, toBus: AVAudioNodeBus(i), format: format)
            }
            engine.connect(sum, to: eq, format: format); engine.connect(eq, to: engine.mainMixerNode, format: format)
            engine.prepare()
        }
        func apply(_ value: EqualizerConfiguration) {
            for band in EqualizerBand.allCases {
                let filter = eq.bands[band.rawValue]
                filter.filterType = .parametric; filter.frequency = min(band.frequency, 21600)
                filter.bandwidth = 1; filter.gain = value.gains[band.rawValue]; filter.bypass = !value.enabled
            }
            eq.globalGain = value.enabled ? -max(0, value.gains.max() ?? 0) : 0
        }
    }
    private final class Deck: @unchecked Sendable {
        let url: URL, duration: Double, file: AVAudioFile, converter: AVAudioConverter, format: AVAudioFormat
        let decoder = DispatchQueue(label: "com.echomusic.audio-decode", qos: .userInitiated)
        var offset: Double, end: Double, queuedFrames: Int64 = 0
        var scheduled = 0, pending = 0
        var ended = false, completed = false, started = false, promoted = false, nodeStarted = false
        var finalBufferScheduled = false
        var identifier: UUID?, fadeOutStart: Double?
        var fadeIn = 0.0, rate = 1.0, fadeRate = 1.0
        var hostStart: UInt64 = 0
        init(url: URL, offset: Double, format: AVAudioFormat) throws {
            self.url = url; self.format = format; file = try AVAudioFile(forReading: url)
            duration = Double(file.length) / file.processingFormat.sampleRate
            guard duration.isFinite, duration > 0, let converter = AVAudioConverter(from: file.processingFormat, to: format) else { throw NSError(domain: "EchoAudio", code: 1) }
            self.converter = converter; self.offset = min(duration, max(0, offset)); end = duration
            file.framePosition = AVAudioFramePosition(self.offset * file.processingFormat.sampleRate)
        }
        /// Decoder queue only. Empty output is not necessarily end of stream.
        func read() -> (AVAudioPCMBuffer?, AVAudioConverterOutputStatus, Error?) {
            guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { return (nil, .error, nil) }
            var error: NSError?, readError: Error?
            let result = converter.convert(to: output, error: &error) { requested, status in
                let remaining = self.file.length - self.file.framePosition
                guard remaining > 0 else { status.pointee = .endOfStream; return nil }
                let frames = AVAudioFrameCount(min(remaining, Int64(requested)))
                guard let input = AVAudioPCMBuffer(pcmFormat: self.file.processingFormat, frameCapacity: frames) else { status.pointee = .noDataNow; return nil }
                do { try self.file.read(into: input, frameCount: frames); status.pointee = .haveData; return input }
                catch { readError = error; status.pointee = .endOfStream; return nil }
            }
            return (output, result, readError ?? error)
        }
    }

    init(contentsOf url: URL) throws {
        let value = EqualizerSettings.shared.configuration
        control.async { [weak self] in
            guard let self else { return }
            self.graph = Graph(); self.graph?.apply(value)
            let timer = DispatchSource.makeTimerSource(queue: self.control)
            timer.schedule(deadline: .now(), repeating: .milliseconds(50)); timer.setEventHandler { [weak self] in self?.tick() }
            self.monitor = timer; timer.resume()
        }
        observe(EqualizerSettings.didChange) { player, _ in
            let value = EqualizerSettings.shared.configuration
            player.control.async { player.graph?.apply(value) }
        }
        observe(.AVAudioEngineConfigurationChange) { player, note in
            player.control.async {
                guard let engine = note.object as? AVAudioEngine, engine === player.graph?.engine else { return }
                if player.wantsPlayback && (!engine.isRunning || [.playing, .transitioning].contains(player.state)) { player.recover() }
            }
        }
        observe(AVAudioSession.interruptionNotification) { player, note in
            player.control.async {
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
                if AVAudioSession.InterruptionType(rawValue: raw) == .began {
                    player.interruptionResume = player.wantsPlayback; player.pauseOnControl()
                } else if player.interruptionResume {
                    let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                    if options.contains(.shouldResume) {
                        do { try AVAudioSession.sharedInstance().setActive(true); player.startOnControl() }
                        catch { player.fail() }
                    }
                    player.interruptionResume = false
                }
            }
        }
        observe(AVAudioSession.routeChangeNotification) { player, note in
            if let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt, AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable { player.pause() }
        }
        try replace(with: url)
    }
    deinit {
        monitor?.cancel(); observers.forEach { NotificationCenter.default.removeObserver($0) }
        let retired = graph
        control.async { retired?.nodes.forEach { $0.stop() }; retired?.engine.stop() }
    }
    private func snapshot() -> Snapshot { lock.lock(); defer { lock.unlock() }; return cached }
    private func version() -> UInt64 { lock.lock(); defer { lock.unlock() }; return commandVersion }
    private func mediaToken() -> UInt64 { lock.lock(); defer { lock.unlock() }; return mediaVersion }
    private func invalidate(_ state: LocalPlaybackState, newMedia: Bool = false) -> UInt64 {
        lock.lock(); defer { lock.unlock() }; commandVersion &+= 1; cached.state = state
        if newMedia { mediaVersion &+= 1 }
        if state == .preparing { cached.duration = 0; cached.position = 0 }
        return commandVersion
    }
    var duration: Double { snapshot().duration }
    var stateValue: LocalPlaybackState { snapshot().state }
    var isPlaying: Bool { [.playing, .transitioning].contains(stateValue) }
    var currentRate: Double { snapshot().rate }
    var canPrepareNext: Bool { snapshot().canPrepare }
    var currentTime: Double {
        get { snapshot().position }
        set {
            guard newValue.isFinite else { return }
            let requestedAt = ProcessInfo.processInfo.systemUptime
            let token = invalidate(.seeking)
            control.async { [weak self] in
                guard let self, self.version() == token else { return }
                self.requestDate = requestedAt; self.awaitingRenderMeasurement = true
                self.recovered = false; self.seekOnControl(max(0, newValue), version: token)
            }
        }
    }
    @discardableResult func prepareToPlay() -> Bool { true }
    func preparedDuration() async throws -> Double {
        let token = version()
        for _ in 0..<500 {
            try Task.checkCancellation()
            guard version() == token else { throw CancellationError() }
            let value = snapshot()
            if value.state == .failed { throw NSError(domain: "EchoAudio", code: 2) }
            if !value.state.isBusy, value.duration > 0 { return value.duration }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "EchoAudio", code: 3)
    }
    func replace(with url: URL) throws {
        let requestedAt = ProcessInfo.processInfo.systemUptime
        let token = invalidate(.preparing, newMedia: true)
        control.async { [weak self] in
            guard let self, self.version() == token else { return }
            self.currentURL = url; self.wantsPlayback = false; self.recovered = false; self.playbackIdentity = UUID()
            self.requestDate = requestedAt; self.awaitingRenderMeasurement = true
            self.reload(offset: 0, preserveStart: false, state: .preparing, version: token)
        }
    }
    @discardableResult func play(intentRevision: UInt64? = nil) -> Bool {
        let token = mediaToken()
        let requestedAt = ProcessInfo.processInfo.systemUptime
        control.async { [weak self] in
            guard let self, self.mediaToken() == token else { return }
            if let intentRevision { self.intentRevision = intentRevision }
            if self.state == .paused && !self.wantsPlayback {
                self.requestDate = requestedAt; self.awaitingRenderMeasurement = true
            }
            self.startOnControl()
        }
        return true // Command accepted; isPlaying confirms rendered progress.
    }
    func pause(intentRevision: UInt64? = nil, completion: (@MainActor () -> Void)? = nil) {
        let token = mediaToken()
        control.async { [weak self] in
            guard let self, self.mediaToken() == token else { return }
            if let intentRevision { self.intentRevision = intentRevision }
            self.pauseOnControl()
            if let completion {
                DispatchQueue.main.async { completion() }
            }
        }
    }
    func stop() {
        let token = invalidate(.idle, newMedia: true)
        control.async { [weak self] in
            guard let self, self.version() == token else { return }
            self.wantsPlayback = false; self.generation = UUID(); self.playbackIdentity = UUID(); self.graph?.nodes.forEach { $0.stop() }
            self.decks = [nil, nil]; self.preparedNext = nil; self.transitionActive = false; self.state = .idle; self.publish(position: 0)
        }
    }
    private func startOnControl() {
        wantsPlayback = true
        guard let graph, let deck = decks[active] else { return }
        if deck.completed {
            recovered = false
            reload(offset: 0, preserveStart: false, state: .preparing, version: version())
            return
        }
        do {
            if !graph.engine.isRunning {
                let session = AVAudioSession.sharedInstance()
                if session.category != .playback { try session.setCategory(.playback, mode: .default) }
                try session.setActive(true); try graph.engine.start()
            }
            if deck.nodeStarted { graph.nodes[active].play(); state = .preparing }
            else { pump(active) }
            progressDate = ProcessInfo.processInfo.systemUptime; publish(position: position(active))
        } catch { fail() }
    }
    private func pauseOnControl() {
        let position = position(active); wantsPlayback = false
        lastProgress = position
        progressDate = ProcessInfo.processInfo.systemUptime
        if transitionActive { seekOnControl(position, version: version()) }
        else { graph?.nodes.forEach { $0.pause() }; state = .paused; publish(position: position) }
        // Pause hardware output too so iOS observes that playback has stopped.
        graph?.engine.pause()
    }
    private func seekOnControl(_ offset: Double, version token: UInt64) {
        guard let deck = decks[active], let graph else {
            reload(offset: offset, preserveStart: true, state: .seeking, version: token); return
        }
        generation = UUID(); let request = generation
        graph.nodes.forEach { $0.stop() }; graph.pitches.forEach { $0.rate = 1; $0.bypass = true }
        let target = min(deck.duration, offset)
        deck.offset = target; deck.end = deck.duration; deck.queuedFrames = 0; deck.scheduled = 0; deck.pending = 0
        deck.ended = false; deck.completed = false; deck.nodeStarted = false; deck.promoted = false
        deck.finalBufferScheduled = false
        deck.identifier = nil; deck.fadeIn = 0; deck.fadeOutStart = nil; deck.rate = 1; deck.fadeRate = 1; deck.hostStart = 0
        decks = [deck, nil]; active = 0; preparedNext = nil; transitionActive = false
        state = wantsPlayback ? .seeking : .paused; lastProgress = target; progressDate = ProcessInfo.processInfo.systemUptime; publish(position: target)
        deck.decoder.async { [weak self] in
            deck.converter.reset(); deck.file.framePosition = AVAudioFramePosition(target * deck.file.processingFormat.sampleRate)
            self?.control.async { [weak self] in
                guard let self, self.generation == request, self.version() == token else { return }
                if self.wantsPlayback { self.startOnControl() }
            }
        }
    }
    private func reload(offset: Double, preserveStart: Bool, state nextState: LocalPlaybackState, version token: UInt64) {
        guard let url = currentURL, let graph else { return }
        let wasStarted = preserveStart && (decks[active]?.started ?? false)
        generation = UUID(); let request = generation
        graph.nodes.forEach { $0.stop() }; graph.pitches.forEach { $0.rate = 1; $0.bypass = true }
        decks = [nil, nil]; active = 0; transitionActive = false; preparedNext = nil
        state = nextState; lastProgress = offset; progressDate = ProcessInfo.processInfo.systemUptime; publish(position: offset)
        opening.async { [weak self] in
            let result = Result { try Deck(url: url, offset: offset, format: graph.format) }
            self?.control.async { [weak self] in
                guard let self, self.version() == token, self.generation == request else { return }
                switch result {
                case .success(let deck):
                    deck.started = wasStarted; self.decks[0] = deck; self.publish(position: deck.offset)
                    if self.wantsPlayback { self.startOnControl() } else { self.state = .paused; self.publish(position: deck.offset) }
                case .failure: self.fail()
                }
            }
        }
    }
    func cancelPreparedNext() {
        control.async { [weak self] in
            guard let self else { return }
            if self.transitionActive { self.seekOnControl(self.position(self.active), version: self.version()) }
            else { self.preparedNext = nil; self.publish(position: self.position(self.active)) }
        }
    }
    func prepareNext(url: URL, identifier: UUID, plan: AudioTransitionPlan) {
        control.async { [weak self] in
            guard let self, let graph = self.graph, self.wantsPlayback, !self.transitionActive, self.preparedNext == nil else { return }
            self.preparedNext = identifier; let request = self.generation
            self.opening.async { [weak self] in
                let result = Result { try Deck(url: url, offset: plan.incomingOffset, format: graph.format) }
                self?.control.async { [weak self] in
                    guard let self, self.generation == request, self.preparedNext == identifier, let outgoing = self.decks[self.active] else { return }
                    guard case .success(let incoming) = result else { self.preparedNext = nil; self.publish(position: self.position(self.active)); return }
                    let fadeStart = outgoing.duration - plan.outgoingTrim - plan.overlap
                    guard fadeStart > outgoing.offset + Double(outgoing.queuedFrames) / 48000 + 0.1 else { self.preparedNext = nil; self.publish(position: self.position(self.active)); return }
                    let index = 1 - self.active
                    incoming.identifier = identifier; incoming.rate = plan.incomingRate; incoming.fadeRate = plan.incomingRate; incoming.fadeIn = plan.overlap
                    graph.pitches[index].bypass = plan.incomingRate == 1; graph.pitches[index].rate = Float(plan.incomingRate)
                    outgoing.fadeOutStart = plan.overlap > 0 ? fadeStart : nil; outgoing.end = outgoing.duration - plan.outgoingTrim
                    let outgoingLatency = graph.pitches[self.active].bypass ? 0 : graph.pitches[self.active].latency
                    let incomingLatency = graph.pitches[index].bypass ? 0 : graph.pitches[index].latency
                    let delay = max(0, (fadeStart - self.position(self.active)) / outgoing.rate + outgoingLatency - incomingLatency)
                    let renderHost = graph.nodes[self.active].lastRenderTime?.hostTime
                    let clock = renderHost.map { AVAudioTime.seconds(forHostTime: $0) } ?? ProcessInfo.processInfo.systemUptime
                    incoming.hostStart = AVAudioTime.hostTime(forSeconds: clock + delay)
                    self.decks[index] = incoming; self.transitionActive = true; self.pump(index); self.publish(position: self.position(self.active))
                }
            }
        }
    }
    private func pump(_ index: Int) {
        guard wantsPlayback, let deck = decks[index], !deck.ended, let graph else { return }
        while deck.scheduled + deck.pending < 4, !deck.ended {
            deck.pending += 1; let request = generation
            #if DEBUG
            let empty = injectedEmptyReads > 0
            if empty { injectedEmptyReads -= 1 }
            #endif
            deck.decoder.async { [weak self] in
                let result: (AVAudioPCMBuffer?, AVAudioConverterOutputStatus, Error?)
                #if DEBUG
                if empty { result = (AVAudioPCMBuffer(pcmFormat: graph.format, frameCapacity: 4096), .inputRanDry, nil) }
                else { result = deck.read() }
                #else
                result = deck.read()
                #endif
                self?.control.async { [weak self] in
                    guard let self, self.generation == request, self.decks[index] === deck else { return }
                    deck.pending -= 1
                    guard result.2 == nil, result.1 != .error, let buffer = result.0 else { self.fail(); return }
                    self.schedule(buffer, result: result.1, deck: deck, index: index, graph: graph, request: request)
                }
            }
        }
    }
    private func schedule(_ buffer: AVAudioPCMBuffer, result: AVAudioConverterOutputStatus, deck: Deck, index: Int, graph: Graph, request: UUID) {
        guard !deck.ended else { drained(index); return }
        let start = deck.offset + Double(deck.queuedFrames) / 48000
        buffer.frameLength = AVAudioFrameCount(min(Int64(buffer.frameLength), max(0, Int64((deck.end - start) * 48000))))
        if buffer.frameLength == 0 {
            if result == .endOfStream || start >= deck.end { deck.ended = true; drained(index) }
            else { control.asyncAfter(deadline: .now() + 0.01) { [weak self] in if self?.generation == request { self?.pump(index) } } }
            return
        }
        let final = result == .endOfStream || start + Double(buffer.frameLength) / 48000 >= deck.end - 1 / 48000
        if let channels = buffer.floatChannelData {
            let mono = AudioSettings.isMonoEnabled
            for frame in 0..<Int(buffer.frameLength) {
                let time = start + Double(frame) / 48000
                var gain: Float = 1
                if let fade = deck.fadeOutStart, time >= fade - 0.05, deck.end > fade {
                    gain = time < fade ? Float(1 - (1 - 0.70710678) * (time - fade + 0.05) / 0.05) : AudioTransitionPlan.outgoingGain((time - fade) / (deck.end - fade))
                }
                if deck.fadeIn > 0 {
                    let elapsed = (time - deck.offset) / deck.fadeRate
                    gain = elapsed <= deck.fadeIn ? AudioTransitionPlan.incomingGain(elapsed / deck.fadeIn) : Float(min(1, 0.70710678 + (elapsed - deck.fadeIn) * 0.29289322))
                }
                if mono { let value = (channels[0][frame] + channels[1][frame]) * 0.5; channels[0][frame] = value; channels[1][frame] = value }
                channels[0][frame] *= gain; channels[1][frame] *= gain
            }
        }
        deck.queuedFrames += Int64(buffer.frameLength); deck.scheduled += 1; deck.ended = final
        if final { deck.finalBufferScheduled = true }
        graph.nodes[index].scheduleBuffer(buffer, completionCallbackType: final ? .dataPlayedBack : .dataConsumed) { [weak self] _ in
            self?.control.async { [weak self] in
                guard let self, self.generation == request, self.decks[index] === deck else { return }
                if final { self.recordStart(deck) }
                deck.scheduled -= 1; self.pump(index); self.drained(index)
            }
        }
        if !deck.nodeStarted, wantsPlayback {
            deck.nodeStarted = true
            if deck.hostStart == 0 { deck.hostStart = AVAudioTime.hostTime(forSeconds: ProcessInfo.processInfo.systemUptime + 0.02) }
            graph.nodes[index].play(at: AVAudioTime(hostTime: max(deck.hostStart, AVAudioTime.hostTime(forSeconds: ProcessInfo.processInfo.systemUptime))))
        }
        pump(index)
    }
    private func position(_ index: Int) -> Double {
        guard let deck = decks[index], let graph else { return snapshot().position }
        guard deck.nodeStarted, let render = graph.nodes[index].lastRenderTime, let time = graph.nodes[index].playerTime(forNodeTime: render), time.sampleTime >= 0 else { return deck.offset }
        return min(deck.duration, deck.offset + Double(time.sampleTime) / time.sampleRate)
    }
    private func tick() {
        guard wantsPlayback else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for index in 0..<2 {
            guard let deck = decks[index], deck.nodeStarted else { continue }
            let elapsed = position(index) - deck.offset
            if elapsed > 1 / 48000, !deck.started {
                recordStart(deck)
            }
            if let id = deck.identifier, !deck.promoted, elapsed > 0, elapsed / deck.fadeRate >= deck.fadeIn / 2 {
                deck.promoted = true; active = index; currentURL = deck.url
                lastProgress = position(index); progressDate = now
                state = transitionActive ? .transitioning : .playing
                notify { $0.onPromote?(id) }
            }
            if deck.promoted, deck.rate != 1, elapsed / deck.fadeRate > deck.fadeIn {
                deck.rate += (1 - deck.rate) * 0.07
                if abs(1 - deck.rate) < 0.001 { deck.rate = 1 }
                graph?.pitches[index].rate = Float(deck.rate)
                if deck.rate == 1 { graph?.pitches[index].bypass = true }
            }
        }
        let current = position(active)
        if current > lastProgress + 0.0001 {
            if awaitingRenderMeasurement {
                awaitingRenderMeasurement = false
                let render = graph?.nodes[active].lastRenderTime
                let elapsed = current - (decks[active]?.offset ?? current)
                let firstHost = render.map { AVAudioTime.seconds(forHostTime: $0.hostTime) - elapsed / (decks[active]?.rate ?? 1) } ?? now
                let latency = max(0, firstHost - requestDate)
                notify { $0.onFirstRender?(latency) }
                logger.notice("First advancing render: \(latency, privacy: .public) seconds")
            }
            lastProgress = current; progressDate = now; state = transitionActive ? .transitioning : .playing
        }
        let latency = graph?.engine.outputNode.presentationLatency ?? 0
        if now - progressDate > max(2, latency + 2), state != .failed { recover(); return }
        publish(position: current)
    }
    private func drained(_ index: Int) {
        guard let deck = decks[index], deck.ended, deck.scheduled == 0, deck.pending == 0, !deck.completed else { return }
        // Some converters report EOF in a separate empty output after their
        // last PCM buffer. Consuming that buffer is not audible completion.
        if !deck.finalBufferScheduled, deck.queuedFrames > 0 {
            guard wantsPlayback, let graph else { return }
            let render = graph.nodes[index].lastRenderTime
            let clock = render.flatMap { graph.nodes[index].playerTime(forNodeTime: $0) }
            let played = clock.map { Double($0.sampleTime) / $0.sampleRate } ?? -1
            let tail = Double(deck.queuedFrames) / 48000 + graph.engine.outputNode.presentationLatency * deck.rate
            if played < tail {
                let request = generation
                control.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                    guard let self, self.generation == request, self.decks[index] === deck else { return }
                    self.drained(index)
                }
                return
            }
            recordStart(deck)
        }
        deck.completed = true
        // A very short incoming file can finish between monitor ticks.
        if let id = deck.identifier, !deck.promoted {
            deck.promoted = true; active = index; currentURL = deck.url
            lastProgress = position(index); progressDate = ProcessInfo.processInfo.systemUptime
            publish(position: lastProgress); notify { $0.onPromote?(id) }
        }
        if transitionActive, deck.identifier != preparedNext {
            graph?.nodes[index].stop(); decks[index] = nil; transitionActive = false; preparedNext = nil
        } else if index == active {
            wantsPlayback = false; state = .idle; publish(position: deck.duration)
            notify { $0.delegate?.audioPlayerDidFinishPlaying($0, successfully: true) }
        }
    }
    private func recover() {
        guard wantsPlayback, state != .failed else { return }
        guard !recovered else { fail(); return }
        recovered = true; let offset = position(active)
        let configuration = graph.map { EqualizerConfiguration(enabled: !$0.eq.bands[0].bypass, gains: $0.eq.bands.map(\.gain), preset: .custom) } ?? EqualizerConfiguration()
        graph?.nodes.forEach { $0.stop() }; graph?.engine.stop(); graph = Graph(); graph?.apply(configuration)
        reload(offset: offset, preserveStart: true, state: .recovering, version: version())
    }
    private func fail() {
        wantsPlayback = false; state = .failed; graph?.nodes.forEach { $0.stop() }; publish(position: position(active))
        notify { $0.delegate?.audioPlayerDidFinishPlaying($0, successfully: false) }
    }
    private func publish(position: Double? = nil) {
        let deck = decks[active]
        lock.lock()
        let previous = cached
        cached = Snapshot(state: state, position: position ?? cached.position, duration: deck?.duration ?? cached.duration,
            rate: deck?.rate ?? 1, generation: generation, identity: playbackIdentity,
            canPrepare: wantsPlayback && deck != nil && !transitionActive && preparedNext == nil && deck?.rate == 1,
            wantsPlayback: wantsPlayback, intentRevision: intentRevision)
        let value = cached
        let command = commandVersion
        lock.unlock()
        if previous.state != value.state || previous.wantsPlayback != value.wantsPlayback ||
            previous.intentRevision != value.intentRevision || abs(previous.rate - value.rate) > 0.001 {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.version() == command else { return }
                let latest = self.snapshot()
                guard latest.generation == value.generation, latest.intentRevision == value.intentRevision,
                      latest.state == value.state, latest.wantsPlayback == value.wantsPlayback else { return }
                self.onStateChanged?(LocalPlaybackUpdate(state: latest.state, position: latest.position,
                    duration: latest.duration, rate: latest.rate, wantsPlayback: latest.wantsPlayback,
                    intentRevision: latest.intentRevision))
            }
        }
    }
    private func recordStart(_ deck: Deck) {
        guard !deck.started else { return }
        deck.started = true; let id = deck.identifier, identity = playbackIdentity
        DispatchQueue.main.async { [weak self] in
            guard let self, self.snapshot().identity == identity else { return }
            self.onStarted?(id)
        }
    }
    private func notify(_ action: @escaping @MainActor (EqualizedAudioPlayer) -> Void) {
        let token = generation, command = version()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.snapshot().generation == token, self.version() == command else { return }; action(self)
        }
    }
    private func observe(_ name: Notification.Name, handler: @escaping (EqualizedAudioPlayer, Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in if let self { handler(self, note) } })
    }
}
