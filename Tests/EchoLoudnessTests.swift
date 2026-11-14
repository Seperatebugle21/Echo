import Foundation
import XCTest

final class EchoLoudnessTests: XCTestCase {
    private func sine(amplitude: Float, seconds: Double, sampleRate: Double, frequency: Double = 997) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { Float(Double(amplitude) * sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    private func measure(_ channels: [[Float]], sampleRate: Double) -> LoudnessMeter.Result {
        var meter = LoudnessMeter(sampleRate: sampleRate, channels: channels.count)
        func feed(_ index: Int, _ pointers: [UnsafePointer<Float>]) {
            guard index < channels.count else { meter.add(pointers, frames: channels[0].count); return }
            channels[index].withUnsafeBufferPointer { feed(index + 1, pointers + [$0.baseAddress!]) }
        }
        feed(0, [])
        return meter.result()
    }

    func testStereoSineAtMinus20DBFSMeasuresMinus20LUFS() {
        for rate in [44_100.0, 48_000.0] {
            let tone = sine(amplitude: 0.1, seconds: 10, sampleRate: rate)
            let result = measure([tone, tone], sampleRate: rate)
            XCTAssertEqual(result.integrated, -20, accuracy: 0.2, "\(rate) Hz")
            XCTAssertEqual(result.peak, 0.1, accuracy: 0.001)
        }
    }

    func testMonoCountsAsDualMono() {
        let tone = sine(amplitude: 0.1, seconds: 10, sampleRate: 48_000)
        XCTAssertEqual(measure([tone], sampleRate: 48_000).integrated, -20, accuracy: 0.2)
    }

    func testSilenceIsGatedAway() {
        let tone = sine(amplitude: 0.1, seconds: 5, sampleRate: 48_000) + [Float](repeating: 0, count: 5 * 48_000)
        XCTAssertEqual(measure([tone, tone], sampleRate: 48_000).integrated, -20, accuracy: 0.3)
        let silent = measure([[Float](repeating: 0, count: 48_000)], sampleRate: 48_000)
        XCTAssertEqual(silent.integrated, -70)
        XCTAssertEqual(LoudnessNormalizer.gain(for: silent), 1)
    }

    func testGainTargetsReferenceLevelWithinLimits() {
        let loud = LoudnessNormalizer.gain(for: .init(integrated: -8, peak: 1))
        XCTAssertEqual(loud, Float(pow(10, -6.0 / 20)), accuracy: 0.0001)
        let veryLoud = LoudnessNormalizer.gain(for: .init(integrated: 10, peak: 1))
        XCTAssertEqual(veryLoud, Float(pow(10, LoudnessNormalizer.maxCutDB / 20)), accuracy: 0.0001)
        let quietLowPeak = LoudnessNormalizer.gain(for: .init(integrated: -30, peak: 0.3))
        XCTAssertEqual(quietLowPeak, Float(pow(10, LoudnessNormalizer.maxBoostDB / 20)), accuracy: 0.0001)
        let quietHighPeak = LoudnessNormalizer.gain(for: .init(integrated: -30, peak: 0.8))
        XCTAssertEqual(quietHighPeak, LoudnessNormalizer.peakCeiling / 0.8, accuracy: 0.0001)
        XCTAssertEqual(LoudnessNormalizer.gain(for: .init(integrated: -20, peak: 1)), 1)
    }
}
