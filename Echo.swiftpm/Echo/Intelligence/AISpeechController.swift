import AVFoundation
import Speech
import Observation

@MainActor @Observable final class AISpeechController {
    var listening = false
    var speaking = false
    var level: Float = 0
    var error: String?
    @ObservationIgnored private let recognitionEngine = AVAudioEngine()
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var inputTap = false
    @ObservationIgnored private var previousCategory: AVAudioSession.Category?
    @ObservationIgnored private var previousMode = AVAudioSession.Mode.default
    @ObservationIgnored private var previousOptions: AVAudioSession.CategoryOptions = []
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var speechEngine: AVAudioEngine?
    @ObservationIgnored private var speechNode: AVAudioPlayerNode?
    @ObservationIgnored private var pendingBuffers = 0
    @ObservationIgnored private var synthesisComplete = false
    @ObservationIgnored private var speechToken = UUID()
    @ObservationIgnored private var listeningToken = UUID()
    @ObservationIgnored private var shouldResume = false
    @ObservationIgnored private var interruptedPlayback: UUID?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    func startListening(update: @escaping (String) -> Void, finished: @escaping () -> Void) async {
        stopSpeaking(); stopListening(); error = nil
        let token = UUID(); listeningToken = token
        let authorized = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) } }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard listeningToken == token, !Task.isCancelled else { return }
        let locale = Locale(identifier: UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en")
        guard authorized, microphone, let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { error = AIError.voice.localizedDescription; return }
        let offline = AISettingsStore.shared.value.offlineOnly
        guard !offline || recognizer.supportsOnDeviceRecognition else { error = AIError.voice.localizedDescription; return }
        do {
            let session = AVAudioSession.sharedInstance()
            previousCategory = session.category; previousMode = session.mode; previousOptions = session.categoryOptions
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try session.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true; request.requiresOnDeviceRecognition = offline
            recognitionRequest = request
            let input = recognitionEngine.inputNode, format = recognitionEngine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw AIError.voice }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let amplitude = Self.amplitude(buffer)
                Task { @MainActor in if self?.listeningToken == token { self?.level = amplitude } }
            }
            inputTap = true; recognitionEngine.prepare(); try recognitionEngine.start(); listening = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.listeningToken == token else { return }
                    if let result { update(result.bestTranscription.formattedString) }
                    if result?.isFinal == true { self.stopListening(); finished() }
                    else if error != nil { self.stopListening(); self.error = AIError.voice.localizedDescription }
                }
            }
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, self?.listeningToken == token else { return }; self?.stopListening()
            }
        } catch { stopListening(); self.error = error.localizedDescription }
    }
    func stopListening() {
        listeningToken = UUID(); timeout?.cancel(); timeout = nil
        recognitionEngine.stop()
        if inputTap { recognitionEngine.inputNode.removeTap(onBus: 0); inputTap = false }
        recognitionRequest?.endAudio(); recognitionTask?.cancel(); recognitionTask = nil; recognitionRequest = nil
        listening = false; level = 0
        if let previousCategory {
            do { try AVAudioSession.sharedInstance().setCategory(previousCategory, mode: previousMode, options: previousOptions) }
            catch { self.error = error.localizedDescription }
            self.previousCategory = nil
        }
    }
    func speak(_ text: String) {
        stopListening(); stopSpeaking()
        let settings = AISettingsStore.shared.value
        guard settings.spokenResponses, !text.isEmpty else { return }
        let player = AudioPlayerManager.shared
        if settings.speechBehavior == "interrupt" {
            shouldResume = player.isPlaying; interruptedPlayback = player.playbackGeneration
            if shouldResume { player.setPlaybackDesired(false) }
        } else if settings.speechBehavior == "duck" { player.setIntelligenceDucking(true) }
        speaking = true; pendingBuffers = 0; synthesisComplete = false
        let token = UUID(); speechToken = token
        let utterance = AVSpeechUtterance(string: String(text.prefix(8000)))
        utterance.voice = settings.voiceID.isEmpty ? AVSpeechSynthesisVoice(language: UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en") : AVSpeechSynthesisVoice(identifier: settings.voiceID)
        synthesizer.write(utterance) { [weak self] audio in
            guard let buffer = audio as? AVAudioPCMBuffer else { return }
            Task { @MainActor in
                guard let self, self.speechToken == token else { return }
                if buffer.frameLength == 0 {
                    self.synthesisComplete = true; self.finishIfReady(); return
                }
                do {
                    if self.speechEngine == nil {
                        let engine = AVAudioEngine(), node = AVAudioPlayerNode()
                        engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
                        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: nil) { [weak self] buffer, _ in
                            let amplitude = Self.amplitude(buffer)
                            Task { @MainActor in if self?.speechToken == token { self?.level = amplitude } }
                        }
                        self.speechEngine = engine; self.speechNode = node
                        try engine.start(); node.play()
                    }
                    self.pendingBuffers += 1
                    self.speechNode?.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                        Task { @MainActor in
                            guard let self, self.speechToken == token else { return }
                            self.pendingBuffers -= 1; self.finishIfReady()
                        }
                    }
                } catch { self.error = error.localizedDescription; self.stopSpeaking() }
            }
        }
    }
    private func finishIfReady() { if synthesisComplete && pendingBuffers == 0 { stopSpeaking() } }
    func stopSpeaking() {
        speechToken = UUID(); synthesizer.stopSpeaking(at: .immediate)
        speechNode?.stop(); speechEngine?.stop(); speechEngine?.mainMixerNode.removeTap(onBus: 0)
        speechNode = nil; speechEngine = nil; speaking = false; level = 0
        let player = AudioPlayerManager.shared
        player.setIntelligenceDucking(false)
        if shouldResume, interruptedPlayback == player.playbackGeneration, !player.isPlaying { player.setPlaybackDesired(true) }
        shouldResume = false; interruptedPlayback = nil
    }
    func stop() { stopListening(); stopSpeaking() }
    nonisolated private static func amplitude(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var energy: Float = 0
        for index in 0..<count { energy += samples[index] * samples[index] }
        return min(1, sqrt(energy / Float(count)) * 6)
    }
}
