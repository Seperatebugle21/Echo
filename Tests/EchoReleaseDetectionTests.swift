import Foundation
import XCTest
final class EchoReleaseDetectionTests: XCTestCase {
    private let show = PodcastShow(id: 42, title: "Show", author: "Author", artworkURL: nil, feedURL: URL(string: "https://example.com/rss")!)
    private func episode(_ id: String, _ published: Date?) -> PodcastEpisode {
        PodcastEpisode(id: id, show: show, title: id, description: "", published: published, duration: 100,
                       audioURL: URL(string: "https://example.com/\(id).mp3")!, artworkURL: nil)
    }
    func testBaselineOldDuplicatesAndFutureDates() {
        let now = Date(timeIntervalSince1970: 1000)
        let follow = PodcastFollow(show: show, enabledAt: now.addingTimeInterval(-100), knownIDs: ["known"], lastChecked: now)
        let episodes = [episode("known", now), episode("archive", now.addingTimeInterval(-500)), episode("fresh", now), episode("future", now.addingTimeInterval(100)), episode("undated", nil)]
        XCTAssertEqual(Set(PodcastReleaseDetection.fresh(episodes, follow: follow, now: now).map(\.id)), ["fresh", "undated"])
        let known = PodcastReleaseDetection.knownIDs(after: episodes, follow: follow, now: now)
        XCTAssertTrue(known.contains("archive")); XCTAssertFalse(known.contains("future"))
        let updated = PodcastFollow(show: show, enabledAt: follow.enabledAt, knownIDs: known, lastChecked: now)
        XCTAssertTrue(PodcastReleaseDetection.fresh(episodes, follow: updated, now: now).isEmpty)
        XCTAssertEqual(PodcastReleaseDetection.fresh(episodes, follow: updated, now: now.addingTimeInterval(200)).map(\.id), ["future"])
    }
    func testFollowPersistence() throws {
        let follow = PodcastFollow(show: show, enabledAt: Date(timeIntervalSince1970: 10), knownIDs: ["a"], lastChecked: Date(timeIntervalSince1970: 20))
        let restored = try JSONDecoder().decode(PodcastFollow.self, from: JSONEncoder().encode(follow))
        XCTAssertEqual(restored.knownIDs, follow.knownIDs); XCTAssertEqual(restored.show, show)
    }
}
