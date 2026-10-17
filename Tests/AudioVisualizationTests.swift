import Foundation
import XCTest

final class AudioVisualizationTests: XCTestCase {
    private func feed(_ level: Float, into meter: AudioVisualization, at time: Double) {
        [Float](repeating: level, count: 1024).withUnsafeBufferPointer {
            meter.ingest($0.baseAddress!, count: $0.count, time: time)
        }
    }

    func testSilenceStaysFlatAndAudioLevelDrivesHeight() {
        let quiet = AudioVisualization(), loud = AudioVisualization(), silence = AudioVisualization()
        feed(0, into: silence, at: 10)
        feed(0.01, into: quiet, at: 10)
        feed(0.8, into: loud, at: 10)
        for band in 0..<32 {
            XCTAssertEqual(silence.snapshot().level(at: band, time: 10.06), 0)
            XCTAssertGreaterThan(loud.snapshot().level(at: band, time: 10.06), quiet.snapshot().level(at: band, time: 10.06))
            XCTAssertLessThanOrEqual(loud.snapshot().level(at: band, time: 10.06), 1)
        }
    }

    func testAudioChangesInterpolateAndStalledFramesSettleToSilence() {
        let meter = AudioVisualization()
        feed(0.5, into: meter, at: 10)
        let frame = meter.snapshot()
        XCTAssertEqual(frame.level(at: 0, time: 10), 0)
        XCTAssertGreaterThan(frame.level(at: 0, time: 10.03), 0)
        XCTAssertLessThan(frame.level(at: 0, time: 10.03), frame.level(at: 0, time: 10.06))
        XCTAssertEqual(frame.level(at: 0, time: 11), 0)
        meter.reset()
        XCTAssertEqual(meter.snapshot().level(at: 0, time: 11), 0)
    }

    func testNewAudioBuffersContinueFromTheCurrentlyDisplayedLevel() {
        let meter = AudioVisualization()
        feed(0.5, into: meter, at: 10)
        let displayed = meter.snapshot().level(at: 0, time: 10.02)
        feed(0.8, into: meter, at: 10.02)
        XCTAssertEqual(meter.snapshot().level(at: 0, time: 10.02), displayed, accuracy: 0.00001)
        XCTAssertGreaterThan(meter.snapshot().level(at: 0, time: 10.06), displayed)
    }

    func testRightChannelOnlyMusicIsVisible() {
        let meter = AudioVisualization()
        let silent = [Float](repeating: 0, count: 1024)
        let right = [Float](repeating: 0.5, count: 1024)
        silent.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                meter.ingest(leftBuffer.baseAddress!, otherChannel: rightBuffer.baseAddress!, count: 1024, time: 10)
            }
        }
        XCTAssertGreaterThan(meter.snapshot().level(at: 0, time: 10.06), 0)
    }

    func testEnvelopeReflectsDifferentPartsOfTheAudioBuffer() {
        let meter = AudioVisualization()
        var samples = [Float](repeating: 0, count: 1024)
        samples.replaceSubrange(512..<1024, with: repeatElement(Float(0.5), count: 512))
        samples.withUnsafeBufferPointer { meter.ingest($0.baseAddress!, count: $0.count, time: 10) }
        XCTAssertEqual(meter.snapshot().level(at: 0, time: 10.06), 0)
        XCTAssertGreaterThan(meter.snapshot().level(at: 31, time: 10.06), 0)
    }
}
