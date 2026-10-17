import Foundation
import XCTest

final class AudioVisualizationTests: XCTestCase {
    private func tone(_ level: Float, frequency: Double = 400) -> [Float] {
        (0..<1024).map { level * Float(sin(2 * .pi * frequency * Double($0) / 48_000)) }
    }
    private func feed(_ level: Float, frequency: Double = 400, into meter: AudioVisualization, at time: Double) {
        tone(level, frequency: frequency).withUnsafeBufferPointer {
            meter.ingest($0.baseAddress!, count: $0.count, time: time)
        }
    }
    private func maximum(_ meter: AudioVisualization, time: Double) -> Double {
        (0..<32).map { meter.snapshot().level(at: $0, time: time) }.max() ?? 0
    }

    func testSilenceStaysFlatAndLouderAudioHasMoreEnergy() {
        let quiet = AudioVisualization(), loud = AudioVisualization(), silence = AudioVisualization()
        feed(0, into: silence, at: 10)
        feed(0.01, into: quiet, at: 10)
        feed(0.8, into: loud, at: 10)
        XCTAssertEqual(maximum(silence, time: 10.06), 0)
        XCTAssertGreaterThan(maximum(loud, time: 10.06), maximum(quiet, time: 10.06))
        XCTAssertLessThanOrEqual(maximum(loud, time: 10.06), 1)
    }

    func testOrdinaryMusicLeavesHeadroomAndBandsDoNotAllStayTall() {
        let meter = AudioVisualization()
        feed(0.15, into: meter, at: 10)
        let levels = (0..<32).map { meter.snapshot().level(at: $0, time: 10.06) }
        XCTAssertGreaterThan(levels.max() ?? 0, 0.1)
        XCTAssertLessThan(levels.max() ?? 1, 0.7)
        XCTAssertGreaterThan(levels.filter { $0 < 0.05 }.count, 20)
    }

    func testBassAndTrebleMoveDifferentBars() {
        let bass = AudioVisualization(), treble = AudioVisualization()
        feed(0.5, frequency: 180, into: bass, at: 10)
        feed(0.5, frequency: 5000, into: treble, at: 10)
        let bassPeak = (0..<32).max { bass.snapshot().levels[$0] < bass.snapshot().levels[$1] }!
        let treblePeak = (0..<32).max { treble.snapshot().levels[$0] < treble.snapshot().levels[$1] }!
        XCTAssertLessThan(bassPeak, 12)
        XCTAssertGreaterThan(treblePeak, 20)
    }

    func testAudioChangesInterpolateAndStalledFramesSettleToSilence() {
        let meter = AudioVisualization()
        feed(0.5, into: meter, at: 10)
        XCTAssertEqual(maximum(meter, time: 10), 0)
        XCTAssertGreaterThan(maximum(meter, time: 10.03), 0)
        XCTAssertLessThan(maximum(meter, time: 10.03), maximum(meter, time: 10.06))
        XCTAssertEqual(maximum(meter, time: 11), 0)
        meter.reset()
        XCTAssertEqual(maximum(meter, time: 11), 0)
    }

    func testNewAudioBuffersContinueFromTheCurrentlyDisplayedLevels() {
        let meter = AudioVisualization()
        feed(0.5, into: meter, at: 10)
        let before = meter.snapshot()
        feed(0.8, into: meter, at: 10.02)
        let after = meter.snapshot()
        for band in 0..<32 {
            XCTAssertEqual(after.level(at: band, time: 10.02), before.level(at: band, time: 10.02), accuracy: 0.00001)
        }
    }

    func testRightChannelOnlyAndOppositePhaseStereoRemainVisible() {
        let rightOnly = AudioVisualization(), opposite = AudioVisualization()
        let silent = tone(0), right = tone(0.5), left = tone(-0.5)
        for (meter, channel) in [(rightOnly, silent), (opposite, left)] {
            channel.withUnsafeBufferPointer { leftBuffer in
                right.withUnsafeBufferPointer { rightBuffer in
                    meter.ingest(leftBuffer.baseAddress!, otherChannel: rightBuffer.baseAddress!, count: 1024, time: 10)
                }
            }
        }
        XCTAssertGreaterThan(maximum(rightOnly, time: 10.06), 0)
        XCTAssertEqual(maximum(rightOnly, time: 10.06), maximum(opposite, time: 10.06), accuracy: 0.001)
    }

    func testReleaseFallsBetweenAudioBuffers() {
        let meter = AudioVisualization()
        feed(0.7, into: meter, at: 10)
        let peak = maximum(meter, time: 10.06)
        feed(0, into: meter, at: 10.08)
        XCTAssertLessThan(maximum(meter, time: 10.14), peak)
    }
}
