import Foundation
import XCTest

final class EchoPlaybackInteractionTests: XCTestCase {
    func testDragOnlyCommitsOnceAfterRelease() {
        let id = UUID()
        var scrub = PlaybackScrubState()
        scrub.begin(songID: id, position: 5, duration: 100)
        for position in stride(from: 10.0, through: 90, by: 0.5) { scrub.update(position) }
        XCTAssertTrue(scrub.isActive)
        XCTAssertEqual(scrub.finish(songID: id), 90)
        XCTAssertNil(scrub.finish(songID: id))
    }
    func testCancelledOrChangedTrackCannotSeek() {
        let id = UUID()
        var scrub = PlaybackScrubState()
        scrub.begin(songID: id, position: 5, duration: 100)
        scrub.update(80)
        scrub.cancel()
        XCTAssertNil(scrub.finish(songID: id))
        scrub.begin(songID: id, position: 5, duration: 100)
        XCTAssertNil(scrub.finish(songID: UUID()))
    }
    func testScrubBoundsAndUnavailableDuration() {
        let id = UUID()
        var scrub = PlaybackScrubState()
        scrub.begin(songID: id, position: 5, duration: .nan)
        XCTAssertFalse(scrub.isActive)
        scrub.begin(songID: id, position: 5, duration: 20)
        scrub.update(-4); XCTAssertEqual(scrub.position, 0)
        scrub.update(.infinity); XCTAssertEqual(scrub.position, 0)
        scrub.update(40); XCTAssertEqual(scrub.finish(songID: id), 20)
    }
    func testLatestTransportIntentionWinsAgainstDelayedCallbacks() {
        var intent = PlaybackIntent()
        let play = intent.set(true)
        let pause = intent.set(false)
        let resume = intent.set(true)
        intent.reconcile(false, revision: pause)
        intent.reconcile(false, revision: play)
        XCTAssertTrue(intent.wantsPlayback)
        intent.reconcile(false, revision: resume)
        XCTAssertFalse(intent.wantsPlayback)
    }
}
