import AVFoundation

protocol EqualizedAudioPlayerDelegate: AnyObject {
    func audioPlayerDidFinishPlaying(_ player: EqualizedAudioPlayer, successfully flag: Bool)
}

/// One graph and two decks, with normalized PCM and sample-based gain ramps.
/// The serial producer reads/converts audio; render callbacks only enqueue work.
final class EqualizedAudioPlayer {
    weak var delegate: EqualizedAudioPlayerDelegate?
    var onPromote: ((UUID) -> Void)?
    var onStarted: ((UUID?) -> Void)?
    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 6)
    private let sum = AVAudioMixerNode()
    private let nodes = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private let pitches = [AVAudioUnitTimePitch(), AVAudioUnitTimePitch()]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    private let worker = DispatchQueue(label: "com.echomusic.audio-producer", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<Bool>()
    private var decks: [Deck?] = [nil, nil]
    private var active = 0
    private var observers: [NSObjectProtocol] = []
    private var generation = UUID()
    private var playing = false
    private var interruptionResume = false
    private var preparedNext: UUID?
    private var transitionActive = false
    private final class Deck {
        let file: AVAudioFile
        let converter: AVAudioConverter
        let duration: Double
        var offset: Double
        var queuedFrames: Int64 = 0
        var ended = false
        var scheduled = 0
        var completed = false
        var identifier: UUID?
        var fadeIn: Double = 0
        var fadeOutStart: Double?
        var end: Double
        var rate: Double = 1
        var fadeRate: Double = 1
        var promoted = false
        var started = false
        var hostStart: UInt64 = 0
        init(_ url: URL, format: AVAudioFormat, offset: Double = 0) throws {
            file = try AVAudioFile(forReading: url)
            duration = Double(file.length) / file.processingFormat.sampleRate
            guard duration.isFinite, duration > 0, let converter = AVAudioConverter(from: file.processingFormat, to: format) else { throw NSError(domain: "EchoAudio", code: 1) }
            self.converter = converter; self.offset = min(duration, max(0, offset)); end = duration
            file.framePosition = AVAudioFramePosition(self.offset * file.processingFormat.sampleRate)
        }
    }
    init(contentsOf url: URL) throws {
        worker.setSpecific(key: queueKey, value: true)
        decks[0] = try Deck(url, format: format)
        engine.attach(eq); engine.attach(sum)
        for i in 0..<2 {
            engine.attach(nodes[i]); engine.attach(pitches[i])
            engine.connect(nodes[i], to: pitches[i], format: format)
            engine.connect(pitches[i], to: sum, fromBus: 0, toBus: AVAudioNodeBus(i), format: format)
        }
        engine.connect(sum, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        applyEqualizer()
        observe(EqualizerSettings.didChange) { player in player.worker.async { player.applyEqualizer() } }
        observe(.AVAudioEngineConfigurationChange, object: engine) { player in
            let resume = player.isPlaying; player.pause(); if resume { player.play() }
        }
        observe(AVAudioSession.interruptionNotification) { player, notification in player.interruption(notification) }
        observe(AVAudioSession.routeChangeNotification) { player, notification in
            if let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable { player.pause() }
        }
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) }; engine.stop() }
    private func sync<T>(_ body: () -> T) -> T { DispatchQueue.getSpecific(key: queueKey) == true ? body() : worker.sync(execute: body) }
    var duration: Double { sync { decks[active]?.duration ?? 0 } }
    var isPlaying: Bool { sync { playing } }
    var currentRate: Double { sync { decks[active]?.rate ?? 1 } }
    var currentTime: Double {
        get { sync { position(active) } }
        set {
            guard newValue.isFinite else { return }
            let resume = isPlaying
            sync { reset(offset: min(duration, max(0, newValue))) }
            if resume { play() }
        }
    }
    private func position(_ index: Int) -> Double {
        guard let deck = decks[index] else { return 0 }
        if playing, let render = nodes[index].lastRenderTime, let time = nodes[index].playerTime(forNodeTime: render), time.sampleTime >= 0 {
            return min(deck.duration, deck.offset + Double(time.sampleTime) / time.sampleRate)
        }
        return deck.offset
    }
    @discardableResult func prepareToPlay() -> Bool { engine.prepare(); return true }
    func replace(with url: URL) throws {
        let deck = try Deck(url, format: format)
        sync {
            generation = UUID(); nodes.forEach { $0.stop() }; engine.pause()
            decks = [deck, nil]; active = 0; playing = false; transitionActive = false; preparedNext = nil
            pitches.forEach { $0.rate = 1 }
        }
    }
    @discardableResult func play() -> Bool {
        sync {
            guard !playing, let deck = decks[active] else { return playing }
            if deck.offset >= deck.duration { reset(offset: 0); decks[active]?.started = false }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                if !engine.isRunning { try engine.start() }
                playing = true
                let token = generation, index = active
                worker.async { [weak self] in
                    guard let self, self.generation == token, let current = self.decks[index] else { return }
                    for _ in 0..<3 { self.enqueue(index, token: token) }
                    guard self.playing, current.scheduled > 0 else { return }
                    current.hostStart = AVAudioTime.hostTime(forSeconds: ProcessInfo.processInfo.systemUptime + 0.04)
                    self.nodes[index].play(at: AVAudioTime(hostTime: current.hostStart))
                }
                return true
            } catch { playing = false; finished(false); return false }
        }
    }
    func pause() { sync { reset(offset: position(active)); interruptionResume = false } }
    func stop() { sync { reset(offset: 0); interruptionResume = false } }
    private func reset(offset: Double) {
        guard let old = decks[active] else { return }
        generation = UUID(); playing = false; nodes.forEach { $0.stop() }; engine.pause(); pitches.forEach { $0.rate = 1 }
        if let fresh = try? Deck(old.file.url, format: format, offset: offset) {
            fresh.started = old.started; decks = [fresh, nil]; active = 0
        }
        preparedNext = nil; transitionActive = false
    }
    var canPrepareNext: Bool { sync { playing && !transitionActive && preparedNext == nil && decks[active]?.rate == 1 } }
    func cancelPreparedNext() {
        let resume = isPlaying
        sync { reset(offset: position(active)) }
        if resume { play() }
    }
    func prepareNext(url: URL, identifier: UUID, plan: AudioTransitionPlan) {
        worker.async { [weak self] in
            guard let self, self.playing, !self.transitionActive, self.preparedNext == nil, let outgoing = self.decks[self.active] else { return }
            do {
                let incoming = try Deck(url, format: self.format, offset: plan.incomingOffset)
                let fadeStart = outgoing.duration - plan.outgoingTrim - plan.overlap
                guard fadeStart > outgoing.offset + Double(outgoing.queuedFrames) / 48000 + 0.10 else { return }
                let index = 1 - self.active, token = self.generation
                incoming.identifier = identifier; incoming.rate = plan.incomingRate; incoming.fadeRate = plan.incomingRate
                incoming.fadeIn = plan.overlap; self.pitches[index].rate = Float(plan.incomingRate)
                outgoing.fadeOutStart = plan.overlap > 0 ? fadeStart : nil
                outgoing.end = outgoing.duration - plan.outgoingTrim
                self.decks[index] = incoming; self.preparedNext = identifier; self.transitionActive = true
                for _ in 0..<3 { self.enqueue(index, token: token) }
                // Extrapolate the outgoing render clock, including pitch latency.
                let host: UInt64
                if let render = self.nodes[self.active].lastRenderTime, render.isHostTimeValid,
                   let source = self.nodes[self.active].playerTime(forNodeTime: render), source.sampleTime >= 0 {
                    let sourcePosition = outgoing.offset + Double(source.sampleTime) / source.sampleRate
                    let delay = max(0, (fadeStart - sourcePosition) / outgoing.rate)
                        + self.pitches[self.active].latency - self.pitches[index].latency
                    host = render.hostTime + AVAudioTime.hostTime(forSeconds: max(0, delay))
                } else {
                    host = outgoing.hostStart + AVAudioTime.hostTime(forSeconds: max(0, (fadeStart - outgoing.offset) / outgoing.rate))
                }
                incoming.hostStart = host
                self.nodes[index].play(at: AVAudioTime(hostTime: host))
            } catch { /* Keep ordinary automatic-next available. */ }
        }
    }
    private func enqueue(_ index: Int, token: UUID) {
        guard token == generation, playing, let deck = decks[index], !deck.ended,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { return }
        var inputError: Error?, conversionError: NSError?
        let result = deck.converter.convert(to: buffer, error: &conversionError) { requested, status in
            let remaining = deck.file.length - deck.file.framePosition
            guard remaining > 0 else { status.pointee = .endOfStream; return nil }
            let frames = AVAudioFrameCount(min(remaining, Int64(requested)))
            guard let input = AVAudioPCMBuffer(pcmFormat: deck.file.processingFormat, frameCapacity: frames) else { status.pointee = .noDataNow; return nil }
            do { try deck.file.read(into: input, frameCount: frames); status.pointee = .haveData; return input }
            catch { inputError = error; status.pointee = .endOfStream; return nil }
        }
        if inputError != nil || conversionError != nil || result == .error { deck.ended = true; playing = false; finished(false); return }
        let start = deck.offset + Double(deck.queuedFrames) / 48000
        buffer.frameLength = AVAudioFrameCount(min(Int64(buffer.frameLength), max(0, Int64((deck.end - start) * 48000))))
        guard buffer.frameLength > 0 else { deck.ended = true; drained(index, token: token); return }
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
        deck.queuedFrames += Int64(buffer.frameLength); deck.scheduled += 1
        let end = start + Double(buffer.frameLength) / 48000
        nodes[index].scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.worker.async {
                guard self.generation == token else { return }
                deck.scheduled -= 1
                if !deck.started { deck.started = true; self.started(deck.identifier) }
                if let id = deck.identifier, !deck.promoted, end - deck.offset >= deck.fadeIn * deck.fadeRate / 2 { self.promote(index, id: id) }
                if deck.promoted, deck.rate != 1, end - deck.offset >= deck.fadeIn * deck.fadeRate {
                    deck.rate += (1 - deck.rate) * 0.12
                    if abs(1 - deck.rate) < 0.001 { deck.rate = 1 }
                    self.pitches[index].rate = Float(deck.rate)
                }
                self.enqueue(index, token: token); self.drained(index, token: token)
            }
        }
        if result == .endOfStream || end >= deck.end - 1 / 48000 { deck.ended = true }
    }
    private func promote(_ index: Int, id: UUID) {
        decks[index]?.promoted = true; active = index
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sync({ self.generation == token }) else { return }
            self.onPromote?(id)
        }
    }
    private func drained(_ index: Int, token: UUID) {
        guard generation == token, let deck = decks[index], deck.ended, deck.scheduled <= 0, !deck.completed else { return }
        deck.completed = true
        nodes[index].stop()
        if index != active || (preparedNext != nil && deck.identifier != preparedNext) {
            let other = 1 - index
            if index == active, let id = decks[other]?.identifier, decks[other]?.promoted == false { promote(other, id: id) }
            decks[index] = nil; preparedNext = nil; transitionActive = false
        } else { deck.offset = deck.duration; playing = false; engine.pause(); finished(true) }
    }
    private func started(_ id: UUID?) {
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sync({ self.generation == token }) else { return }
            self.onStarted?(id)
        }
    }
    private func finished(_ success: Bool) {
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sync({ self.generation == token }) else { return }
            self.delegate?.audioPlayerDidFinishPlaying(self, successfully: success)
        }
    }
    private func applyEqualizer() {
        let settings = EqualizerSettings.shared.configuration
        for band in EqualizerBand.allCases {
            let filter = eq.bands[band.rawValue]
            filter.filterType = .parametric; filter.frequency = min(band.frequency, 21600)
            filter.bandwidth = 1; filter.gain = settings.gains[band.rawValue]; filter.bypass = !settings.enabled
        }
        eq.globalGain = settings.enabled ? -max(0, settings.gains.max() ?? 0) : 0
    }
    private func observe(_ name: Notification.Name, object: Any? = nil, handler: @escaping (EqualizedAudioPlayer) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in if let self { handler(self) } })
    }
    private func observe(_ name: Notification.Name, handler: @escaping (EqualizedAudioPlayer, Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in if let self { handler(self, notification) } })
    }
    private func interruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began { let resume = isPlaying; pause(); interruptionResume = resume }
        else {
            let options = AVAudioSession.InterruptionOptions(rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            if interruptionResume && options.contains(.shouldResume) { interruptionResume = false; play() }
        }
    }
}
