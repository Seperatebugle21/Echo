import AVFoundation
import Foundation

// MARK: - Meter

/// Integrated loudness per ITU-R BS.1770-4 / EBU R128: K-weighting,
/// 400 ms blocks with 75% overlap, absolute (-70 LUFS) and relative (-10 LU) gating.
struct LoudnessMeter {
    struct Result: Codable, Equatable, Sendable {
        /// Integrated loudness in LUFS.
        var integrated: Double
        /// Highest absolute sample value (1 = full scale).
        var peak: Float
    }

    private struct Biquad {
        var b0, b1, b2, a1, a2: Double
        var z1 = 0.0, z2 = 0.0
        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    private let channelWeight: Double
    private let subBlockFrames: Int
    private var shelves: [Biquad]
    private var highPasses: [Biquad]
    private var subBlockSum = 0.0
    private var subBlockCount = 0
    /// Channel-weighted mean square of each 100 ms sub-block.
    private var subBlocks: [Double] = []
    private var peak: Float = 0

    init(sampleRate: Double, channels: Int) {
        let count = max(1, channels)
        // A mono file plays on both speakers, so count it twice (dual mono).
        channelWeight = count == 1 ? 2 : 1
        subBlockFrames = max(1, Int((sampleRate * 0.1).rounded()))

        // Coefficients for any sample rate (as in libebur128).
        var k = tan(.pi * 1681.974450955533 / sampleRate)
        let vh = pow(10, 3.999843853973347 / 20), vb = pow(vh, 0.4996667741545416)
        var q = 0.7071752369554196
        var a0 = 1 + k / q + k * k
        let shelf = Biquad(b0: (vh + vb * k / q + k * k) / a0, b1: 2 * (k * k - vh) / a0,
                           b2: (vh - vb * k / q + k * k) / a0,
                           a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
        k = tan(.pi * 38.13547087602444 / sampleRate)
        q = 0.5003270373238773
        a0 = 1 + k / q + k * k
        let highPass = Biquad(b0: 1, b1: -2, b2: 1, a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
        shelves = Array(repeating: shelf, count: count)
        highPasses = Array(repeating: highPass, count: count)
    }

    /// Adds frames; `channels` holds one pointer per channel (non-interleaved floats).
    mutating func add(_ channels: [UnsafePointer<Float>], frames: Int) {
        guard channels.count == shelves.count else { return }
        for frame in 0..<frames {
            var sum = 0.0
            for channel in 0..<channels.count {
                let sample = channels[channel][frame]
                peak = max(peak, abs(sample))
                let weighted = highPasses[channel].process(shelves[channel].process(Double(sample)))
                sum += weighted * weighted
            }
            subBlockSum += sum * channelWeight
            subBlockCount += 1
            if subBlockCount == subBlockFrames {
                subBlocks.append(subBlockSum / Double(subBlockFrames))
                subBlockSum = 0; subBlockCount = 0
            }
        }
    }

    func result() -> Result {
        var blocks: [Double] = []
        if subBlocks.count >= 4 {
            blocks.reserveCapacity(subBlocks.count - 3)
            for index in 3..<subBlocks.count {
                blocks.append((subBlocks[index - 3] + subBlocks[index - 2] + subBlocks[index - 1] + subBlocks[index]) / 4)
            }
        } else {
            // Shorter than one block: measure what there is.
            let frames = subBlocks.count * subBlockFrames + subBlockCount
            let total = subBlocks.reduce(0) { $0 + $1 * Double(subBlockFrames) } + subBlockSum
            if frames > 0 { blocks = [total / Double(frames)] }
        }
        func loudness(_ meanSquare: Double) -> Double { -0.691 + 10 * log10(max(meanSquare, 1e-12)) }
        let aboveAbsolute = blocks.filter { loudness($0) > -70 }
        guard !aboveAbsolute.isEmpty else { return Result(integrated: -70, peak: peak) }
        let relativeGate = loudness(aboveAbsolute.reduce(0, +) / Double(aboveAbsolute.count)) - 10
        let gated = aboveAbsolute.filter { loudness($0) > relativeGate }
        let integrated = loudness(gated.reduce(0, +) / Double(max(1, gated.count)))
        return Result(integrated: integrated, peak: peak)
    }

    /// Measures a whole audio file.
    static func measure(_ url: URL) throws -> Result {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        var meter = LoudnessMeter(sampleRate: format.sampleRate, channels: Int(format.channelCount))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536) else {
            throw NSError(domain: "EchoLoudness", code: 1)
        }
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: 65_536)
            guard buffer.frameLength > 0, let data = buffer.floatChannelData else { break }
            let pointers = (0..<Int(format.channelCount)).map { UnsafePointer(data[$0]) }
            meter.add(pointers, frames: Int(buffer.frameLength))
        }
        return meter.result()
    }
}

// MARK: - Normalizer

/// Remembers the loudness of local tracks and turns it into a playback gain,
/// so songs from different sources play at a similar volume.
///
/// Tracks are measured in the background (upcoming songs first, then the rest of
/// the library). A track that has not been measured yet plays unchanged.
final class LoudnessNormalizer: @unchecked Sendable {
    static let shared = LoudnessNormalizer()

    /// Common streaming reference level.
    static let targetLUFS = -14.0
    static let maxBoostDB = 6.0
    static let maxCutDB = -15.0
    /// Keep boosted peaks just under full scale.
    static let peakCeiling: Float = 0.97

    /// Playback gain (linear) for a measured track.
    static func gain(for result: LoudnessMeter.Result) -> Float {
        guard result.integrated.isFinite, result.integrated > -70 else { return 1 }
        let db = min(maxBoostDB, max(maxCutDB, targetLUFS - result.integrated))
        var gain = Float(pow(10, db / 20))
        if gain > 1, result.peak > 0 { gain = max(1, min(gain, peakCeiling / result.peak)) }
        return gain
    }

    private let lock = NSLock()
    private var values: [String: LoudnessMeter.Result] = [:]
    private var loaded = false
    private var queued: Set<String> = []
    private var urgent: [URL] = []
    private var background: [URL] = []
    private var working = false
    private var saveScheduled = false
    private let worker = DispatchQueue(label: "com.echomusic.loudness", qos: .utility)

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EchoLoudness-v1.json")
    }

    /// Gain to apply to `url` now: 1 when normalization is off or the track is not measured yet
    /// (it is then queued for measuring).
    func gain(for url: URL) -> Float {
        guard AudioSettings.isNormalizationEnabled, let key = Self.key(for: url) else { return 1 }
        lock.lock()
        loadLocked()
        let value = values[key]
        lock.unlock()
        if let value { return Self.gain(for: value) }
        measure([url], urgent: true)
        return 1
    }

    /// Queues tracks for measuring. Urgent ones (current and upcoming songs) go first.
    func measure(_ urls: [URL], urgent isUrgent: Bool) {
        guard AudioSettings.isNormalizationEnabled else { return }
        lock.lock()
        loadLocked()
        for url in urls {
            guard let key = Self.key(for: url), values[key] == nil, queued.insert(key).inserted else { continue }
            if isUrgent { urgent.append(url) } else { background.append(url) }
        }
        let start = !working && !(urgent.isEmpty && background.isEmpty)
        if start { working = true }
        lock.unlock()
        if start { worker.async { [self] in drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            let next: URL?
            if !urgent.isEmpty { next = urgent.removeFirst() }
            else if !background.isEmpty, !ProcessInfo.processInfo.isLowPowerModeEnabled { next = background.removeFirst() }
            else { next = nil }
            if next == nil { working = false }
            lock.unlock()
            guard let url = next else { return }
            guard AudioSettings.isNormalizationEnabled else {
                lock.lock(); urgent.removeAll(); background.removeAll(); queued.removeAll(); working = false; lock.unlock()
                return
            }
            // `measure` reads the entire file; keep it out of the way of playback.
            let result = autoreleasepool { try? LoudnessMeter.measure(url) }
            lock.lock()
            if let key = Self.key(for: url) {
                queued.remove(key)
                if let result { values[key] = result }
            }
            let save = !saveScheduled
            saveScheduled = true
            lock.unlock()
            if save { worker.asyncAfter(deadline: .now() + 5) { [self] in persist() } }
        }
    }

    private func persist() {
        lock.lock()
        saveScheduled = false
        let snapshot = values
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: cacheURL, options: .atomic) }
    }

    private func loadLocked() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode([String: LoudnessMeter.Result].self, from: data) {
            values = saved
        }
    }

    /// File name, size and modification date: survives app-container moves, changes when the file does.
    private static func key(for url: URL) -> String? {
        guard let attributes = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
        let modified = Int(attributes.contentModificationDate?.timeIntervalSince1970 ?? 0)
        return "\(url.lastPathComponent)|\(attributes.fileSize ?? 0)|\(modified)"
    }
}
