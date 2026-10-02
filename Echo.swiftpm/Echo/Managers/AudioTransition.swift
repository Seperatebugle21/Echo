import Foundation

enum AudioTransitionMode: String, Codable, CaseIterable, Identifiable {
    case direct, gapless, crossfade, mix
    var id: String { rawValue }
    var key: String { "audio_transition_" + rawValue }
    var detailKey: String { key + "_detail" }
}
struct BeatAnalysis: Codable, Sendable {
    var bpm: Double = 0
    var confidence: Double = 0
    var firstBeat: Double = 0
    var energy: Double = 0
}
struct AudioTransitionPlan: Equatable, Sendable {
    var overlap: Double = 0
    var incomingRate: Double = 1
    var incomingOffset: Double = 0
    var outgoingTrim: Double = 0
    var beatMatched = false
    static func make(mode: AudioTransitionMode, seconds: Double, outgoingDuration: Double, incomingDuration: Double,
                     outro: BeatAnalysis = BeatAnalysis(), intro: BeatAnalysis = BeatAnalysis()) -> Self {
        guard outgoingDuration.isFinite, incomingDuration.isFinite, seconds.isFinite, outgoingDuration > 0, incomingDuration > 0 else { return Self() }
        guard mode == .crossfade || mode == .mix else { return Self() }
        let available = max(0, min(outgoingDuration / 2, incomingDuration / 2, 12))
        if mode == .crossfade { return Self(overlap: min(available, max(1, seconds))) }
        if outro.confidence >= 0.35, intro.confidence >= 0.35, outro.bpm > 0, intro.bpm > 0 {
            let rates = [intro.bpm / 2, intro.bpm, intro.bpm * 2].map { outro.bpm / $0 }
            if let rate = rates.filter({ (0.92...1.08).contains($0) }).min(by: { abs(1 - $0) < abs(1 - $1) }) {
                let beat = 60 / outro.bpm
                let beats = min(8, floor(available / beat))
                let overlap = beats * beat
                if overlap >= 3 {
                    let phase = max(0, outgoingDuration - 45) + outro.firstBeat
                    let lastBeat = phase + floor((outgoingDuration - phase) / beat) * beat
                    return Self(overlap: overlap, incomingRate: rate,
                                incomingOffset: min(max(0, intro.firstBeat), 4 * 60 / intro.bpm),
                                outgoingTrim: max(0, outgoingDuration - lastBeat), beatMatched: true)
                }
            }
        }
        return Self(overlap: min(available, max(3, min(8, 3 + 5 * min(1, outro.energy + intro.energy)))))
    }
    static func outgoingGain(_ fraction: Double) -> Float {
        Float(cos(min(1, max(0, fraction)) * .pi / 2)) * 0.70710678
    }
    static func incomingGain(_ fraction: Double) -> Float {
        Float(sin(min(1, max(0, fraction)) * .pi / 2)) * 0.70710678
    }
}

enum BeatDetector {
    /// Positive energy flux at 100 Hz, followed by normalized autocorrelation.
    /// Analysis runs on a worker queue, never on the audio render thread.
    static func analyze(_ samples: [Float], sampleRate: Double) -> BeatAnalysis {
        guard sampleRate > 0, samples.count > Int(sampleRate * 3) else { return BeatAnalysis() }
        let hop = max(1, Int(sampleRate / 100)), count = samples.count / hop
        var energy = [Double](repeating: 0, count: count)
        for index in 0..<count {
            var sum = 0.0
            for sample in samples[(index * hop)..<((index + 1) * hop)] { sum += Double(sample * sample) }
            energy[index] = sqrt(sum / Double(hop))
        }
        var onset = [Double](repeating: 0, count: count)
        for i in 1..<count { onset[i] = max(0, energy[i] - energy[i - 1]) }
        let power = onset.reduce(0) { $0 + $1 * $1 }
        guard power > 1e-8 else { return BeatAnalysis(energy: energy.reduce(0, +) / Double(count)) }
        var bestLag = 0, best = 0.0
        for lag in 33...100 where lag < count / 2 {
            var value = 0.0, left = 0.0, right = 0.0
            for i in lag..<count { value += onset[i] * onset[i - lag]; left += onset[i] * onset[i]; right += onset[i - lag] * onset[i - lag] }
            let correlation = value / max(1e-12, sqrt(left * right))
            if correlation > best { best = correlation; bestLag = lag }
        }
        guard bestLag > 0 else { return BeatAnalysis() }
        let phase = (0..<bestLag).max { a, b in
            stride(from: a, to: count, by: bestLag).reduce(0) { $0 + onset[$1] } < stride(from: b, to: count, by: bestLag).reduce(0) { $0 + onset[$1] }
        } ?? 0
        return BeatAnalysis(bpm: 6000 / Double(bestLag), confidence: best, firstBeat: Double(phase) / 100,
                            energy: energy.reduce(0, +) / Double(count))
    }
}
