import Foundation
import XCTest

final class HomeDiscoverySelectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let show = PodcastShow(id: 1, title: "Show", author: "Author", artworkURL: nil,
        feedURL: URL(string: "https://example.com/feed")!)

    private func episode(_ id: String, daysAgo: Double?) -> PodcastEpisode {
        PodcastEpisode(id: id, show: show, title: id, description: "", published: daysAgo.map {
            now.addingTimeInterval(-$0 * 86_400)
        }, duration: 300, audioURL: URL(string: "https://example.com/\(id).mp3")!, artworkURL: nil)
    }

    func testNeverRecommendsAnUnfamiliarShow() {
        XCTAssertNil(HomeDiscoverySelection.newEpisode(in: [episode("new", daysAgo: 1)],
            knownEpisodes: [], listening: [:], now: now))
    }

    func testSelectsNewestUnheardReleaseOfAListenedShow() {
        let heard = episode("heard", daysAgo: 10)
        let feed = [episode("older", daysAgo: 20), episode("new", daysAgo: 2), episode("newest", daysAgo: 1)]
        let result = HomeDiscoverySelection.newEpisode(in: feed, knownEpisodes: [heard],
            listening: [heard.id: PodcastListeningState(position: 30)], now: now)
        XCTAssertEqual(result?.id, "newest")
    }

    func testRejectsStartedCompletedUndatedFutureAndStaleEpisodes() {
        let heard = episode("heard", daysAgo: 60)
        let feed = [episode("started", daysAgo: 1), episode("completed", daysAgo: 2),
            episode("undated", daysAgo: nil), episode("future", daysAgo: -1), episode("stale", daysAgo: 31)]
        XCTAssertNil(HomeDiscoverySelection.newEpisode(in: feed, knownEpisodes: [heard], listening: [
            heard.id: PodcastListeningState(played: true),
            "started": PodcastListeningState(position: 1),
            "completed": PodcastListeningState(played: true)
        ], now: now))
    }

    func testRejectsBackCatalogEvenWhenRecent() {
        let heard = episode("heard", daysAgo: 2)
        XCTAssertNil(HomeDiscoverySelection.newEpisode(in: [episode("older", daysAgo: 3)],
            knownEpisodes: [heard], listening: [heard.id: PodcastListeningState(played: true)], now: now))
    }
}
