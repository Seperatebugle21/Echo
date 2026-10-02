import AVFoundation

actor AudioBeatCache {
    static let shared = AudioBeatCache()
    struct Pair: Codable, Sendable { var intro: BeatAnalysis; var outro: BeatAnalysis }
    private var values: [String: Pair] = [:]
    private var loaded = false
    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("EchoBeats-v1.json")
    }
    func analysis(_ url: URL) throws -> Pair {
        if !loaded { values = (try? JSONDecoder().decode([String: Pair].self, from: Data(contentsOf: cacheURL))) ?? [:]; loaded = true }
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let key = "\(url.path)|\(attributes.fileSize ?? 0)|\(attributes.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        if let value = values[key] { return value }
        let file = try AVAudioFile(forReading: url)
        let frames = min(file.length, AVAudioFramePosition(file.processingFormat.sampleRate * 45))
        func section(start: AVAudioFramePosition) throws -> BeatAnalysis {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames)) else { return BeatAnalysis() }
            file.framePosition = start
            try file.read(into: buffer, frameCount: AVAudioFrameCount(frames))
            guard let channels = buffer.floatChannelData else { return BeatAnalysis() }
            let stride = max(1, Int(file.processingFormat.sampleRate / 11025))
            var samples: [Float] = []; samples.reserveCapacity(Int(frames) / stride)
            for i in Swift.stride(from: 0, to: Int(buffer.frameLength), by: stride) {
                var value: Float = 0
                for c in 0..<Int(file.processingFormat.channelCount) { value += channels[c][i] }
                samples.append(value / Float(file.processingFormat.channelCount))
            }
            return BeatDetector.analyze(samples, sampleRate: file.processingFormat.sampleRate / Double(stride))
        }
        let value = Pair(intro: try section(start: 0), outro: try section(start: max(0, file.length - frames)))
        values[key] = value
        if values.count > 500 { values = [key: value] }
        if let data = try? JSONEncoder().encode(values) { try? data.write(to: cacheURL, options: .atomic) }
        return value
    }
}
