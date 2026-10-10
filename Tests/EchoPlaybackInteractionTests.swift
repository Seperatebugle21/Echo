import Foundation
import XCTest

final class EchoPlaybackInteractionTests: XCTestCase {
    func testAutoNextConsumesEachSelectionBeforeAsyncPlaybackAndDoesNotRepeat() {
        let songs = (0..<7).map { Song(title: "Song \($0)", artist: "Artist", fileName: "\($0).wav") }
        var queue = [songs[0]]
        var recommendations: [Song] = []
        PlaybackRecommendations.refill(&recommendations, from: songs + [songs[1]], queue: queue,
            currentSongID: songs[0].id, limit: 3, order: { $0 })
        var played: [UUID] = []
        while let next = recommendations.first {
            queue.append(next)
            XCTAssertTrue(PlaybackRecommendations.consume(next.id, from: &recommendations))
            XCTAssertFalse(recommendations.contains { $0.id == next.id })
            played.append(next.id)
            PlaybackRecommendations.refill(&recommendations, from: songs, queue: queue,
                currentSongID: next.id, limit: 3, order: { $0 })
            if played.count > songs.count { XCTFail("AutoNext repeated a consumed song"); break }
        }
        XCTAssertEqual(played, songs.dropFirst().map(\.id))
    }

    func testSelectingRecommendationRemovesOnlyThatSongIncludingDuplicates() {
        let a = Song(title: "A", artist: "Artist", fileName: "a.wav")
        let b = Song(title: "B", artist: "Artist", fileName: "b.wav")
        let c = Song(title: "C", artist: "Artist", fileName: "c.wav")
        var recommendations = [a, b, b, c]
        XCTAssertTrue(PlaybackRecommendations.consume(b.id, from: &recommendations))
        XCTAssertEqual(recommendations, [a, c])
        XCTAssertFalse(PlaybackRecommendations.consume(b.id, from: &recommendations))
    }
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
