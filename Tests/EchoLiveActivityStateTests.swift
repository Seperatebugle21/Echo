import Foundation
import XCTest

final class EchoLiveActivityStateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func state(playing: Bool = true, elapsed: Double = 30, duration: Double = 200,
                       rate: Double = 1, at date: Date? = nil) -> EchoLiveActivityAttributes.ContentState {
        .init(songID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Song", artist: "Artist",
              isPodcast: false, isPlaying: playing, elapsed: elapsed, duration: duration,
              rate: rate, updatedAt: date ?? start)
    }

    func testProgressIntervalCoversWholeTrackAtPlaybackRate() throws {
        let normal = try XCTUnwrap(state().progressInterval)
        XCTAssertEqual(normal.lowerBound, start.addingTimeInterval(-30))
        XCTAssertEqual(normal.upperBound, start.addingTimeInterval(170))

        let fast = try XCTUnwrap(state(rate: 2).progressInterval)
        XCTAssertEqual(fast.lowerBound, start.addingTimeInterval(-15))
        XCTAssertEqual(fast.upperBound, start.addingTimeInterval(85))
    }

    func testPausedOrUnknownDurationHasStaticProgress() {
        XCTAssertNil(state(playing: false).progressInterval)
        XCTAssertNil(state(duration: 0).progressInterval)
        XCTAssertEqual(state(playing: false).progress, 0.15, accuracy: 0.0001)
        XCTAssertEqual(state(elapsed: 500).progress, 1)
    }

    func testMatchesSkipsUpdatesThatFollowTheExpectedPosition() {
        let earlier = state()
        let later = start.addingTimeInterval(10)
        XCTAssertTrue(earlier.matches(state(elapsed: 40, at: later), at: later))
        XCTAssertFalse(earlier.matches(state(elapsed: 90, at: later), at: later), "a seek must update")
        XCTAssertFalse(earlier.matches(state(playing: false, elapsed: 40, at: later), at: later), "pausing must update")
        XCTAssertTrue(state(playing: false).matches(state(playing: false, at: later), at: later))
    }
}
