import AVFoundation
import XCTest
final class EchoAudioEngineTests: XCTestCase {
    private func fixture(rate: Double, channels: AVAudioChannelCount, seconds: Double = 2) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * seconds)))
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(buffer.frameLength) { buffer.floatChannelData![channel][frame] = 0.05 * sin(Float(frame) * 0.03) }
        }
        try file.write(from: buffer); return url
    }
    func testDurationSeekAndReplacingDifferentFormats() throws {
        let a = try fixture(rate: 44100, channels: 1), b = try fixture(rate: 48000, channels: 2)
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let player = try EqualizedAudioPlayer(contentsOf: a)
        XCTAssertEqual(player.duration, 2, accuracy: 0.001)
        player.currentTime = 1; XCTAssertEqual(player.currentTime, 1, accuracy: 0.001)
        player.currentTime = -1; XCTAssertEqual(player.currentTime, 0)
        try player.replace(with: b); XCTAssertEqual(player.duration, 2, accuracy: 0.001)
        XCTAssertFalse(player.isPlaying); player.stop(); XCTAssertEqual(player.currentTime, 0)
    }
    func testPreparedGaplessPromotesOnlyOnce() throws {
        let a = try fixture(rate: 44100, channels: 1, seconds: 1), b = try fixture(rate: 48000, channels: 2, seconds: 1)
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let player = try EqualizedAudioPlayer(contentsOf: a), id = UUID()
        let promoted = expectation(description: "Incoming track becomes current")
        promoted.assertForOverFulfill = true
        player.onStarted = { incoming in if incoming == nil { player.prepareNext(url: b, identifier: id, plan: AudioTransitionPlan()) } }
        player.onPromote = { incoming in XCTAssertEqual(incoming, id); promoted.fulfill() }
        XCTAssertTrue(player.play()); wait(for: [promoted], timeout: 5); player.stop()
    }
}
