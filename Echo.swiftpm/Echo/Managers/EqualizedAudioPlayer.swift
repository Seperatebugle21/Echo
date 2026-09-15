import AVFoundation

protocol EqualizedAudioPlayerDelegate: AnyObject {
    func audioPlayerDidFinishPlaying(_ player: EqualizedAudioPlayer, successfully flag: Bool)
}

// The manager keeps its queue/remote-control API; every local file passes through EQ.
final class EqualizedAudioPlayer {
    weak var delegate: EqualizedAudioPlayerDelegate?
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let channelMixer = AVAudioMixerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 6)
    private let file: AVAudioFile
    private var observers: [NSObjectProtocol] = []
    private var generation = UUID()
    private var offset: TimeInterval = 0
    private var cachedTime: TimeInterval = 0
    private var resumeAfterInterruption = false
    private(set) var isPlaying = false

    var duration: TimeInterval { Double(file.length) / file.processingFormat.sampleRate }
    var currentTime: TimeInterval {
        get {
            if isPlaying, let renderTime = node.lastRenderTime,
               let time = node.playerTime(forNodeTime: renderTime), time.sampleTime >= 0 {
                cachedTime = min(duration, offset + Double(time.sampleTime) / time.sampleRate)
            }
            return cachedTime
        }
        set {
            guard newValue.isFinite else { return }
            let resume = isPlaying
            pause()
            cachedTime = min(duration, max(0, newValue))
            offset = cachedTime
            if resume && cachedTime >= duration {
                let token = generation
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.delegate?.audioPlayerDidFinishPlaying(self, successfully: true)
                }
            } else if resume {
                play()
            }
        }
    }

    init(contentsOf url: URL) throws {
        file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.processingFormat.sampleRate > 0 else {
            throw NSError(domain: "EchoAudio", code: 1)
        }
        engine.attach(node)
        engine.attach(equalizer)
        engine.attach(channelMixer)
        engine.connect(node, to: equalizer, format: file.processingFormat)
        engine.connect(equalizer, to: channelMixer, format: file.processingFormat)
        connectChannelMixer()
        observers.append(NotificationCenter.default.addObserver(
            forName: AudioSettings.didChange, object: nil, queue: .main
        ) { [weak self] _ in self?.applyAudioMode() })
        applyEqualizer()
        observers.append(NotificationCenter.default.addObserver(
            forName: EqualizerSettings.didChange, object: nil, queue: .main
        ) { [weak self] _ in self?.applyEqualizer() })
        observers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            self.pause()
            self.play()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in self?.handleInterruption(notification) })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            if let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable {
                self?.pause()
            }
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        node.stop()
        engine.stop()
    }

    @discardableResult
    func prepareToPlay() -> Bool {
        engine.prepare()
        return true
    }

    @discardableResult
    func play() -> Bool {
        guard !isPlaying else { return true }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try engine.start() }
            if cachedTime >= duration { cachedTime = 0 }
            offset = cachedTime
            let start = AVAudioFramePosition(offset * file.processingFormat.sampleRate)
            let token = UUID()
            generation = token
            // Chunk long files without truncating at AVAudioFrameCount.max.
            var position = start
            while position < file.length {
                let count = AVAudioFrameCount(min(file.length - position, Int64(UInt32.max)))
                let isLast = position + Int64(count) == file.length
                node.scheduleSegment(file, startingFrame: position, frameCount: count,
                                     at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    guard isLast else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == token, self.isPlaying else { return }
                        self.isPlaying = false
                        self.cachedTime = self.duration
                        self.node.stop()
                        self.engine.pause()
                        self.delegate?.audioPlayerDidFinishPlaying(self, successfully: true)
                    }
                }
                position += Int64(count)
            }
            isPlaying = true
            node.play()
            return true
        } catch {
            isPlaying = false
            delegate?.audioPlayerDidFinishPlaying(self, successfully: false)
            return false
        }
    }

    func pause() {
        let position = currentTime
        resumeAfterInterruption = false
        generation = UUID() // stop also invokes scheduled callbacks; ignore stale ones.
        isPlaying = false
        node.stop()
        engine.pause()
        cachedTime = position
        offset = position
    }

    func stop() {
        pause()
        resumeAfterInterruption = false
        cachedTime = 0
        offset = 0
    }

    private func connectChannelMixer() {
        // The mixer downmixes all input channels to mono before the main mixer
        // distributes that signal to the output device's channels.
        let channels: AVAudioChannelCount = AudioSettings.isMonoEnabled ? 1 : file.processingFormat.channelCount
        let format = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate,
                                   channels: channels)!
        engine.connect(channelMixer, to: engine.mainMixerNode, format: format)
    }

    private func applyAudioMode() {
        let resume = isPlaying
        let pendingInterruptionResume = resumeAfterInterruption
        pause()
        engine.stop()
        engine.disconnectNodeOutput(channelMixer)
        connectChannelMixer()
        resumeAfterInterruption = pendingInterruptionResume
        if resume { play() }
    }

    private func applyEqualizer() {
        let settings = EqualizerSettings.shared.configuration
        for band in EqualizerBand.allCases {
            let filter = equalizer.bands[band.rawValue]
            filter.filterType = .parametric
            filter.frequency = min(band.frequency, Float(file.processingFormat.sampleRate * 0.45))
            filter.bandwidth = 1
            filter.gain = settings.gains[band.rawValue]
            filter.bypass = !settings.enabled
        }
        // Leave headroom when boosting a band instead of simply raising output level.
        equalizer.globalGain = settings.enabled
            ? -max(0, settings.gains.max() ?? 0) : 0
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            let resume = isPlaying
            pause()
            resumeAfterInterruption = resume
        } else {
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            let resume = resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
            resumeAfterInterruption = false
            if resume { play() }
        }
    }
}
