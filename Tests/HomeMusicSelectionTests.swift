import Foundation
import XCTest

final class HomeMusicSelectionTests: XCTestCase {
    private func song(_ title: String, artist: String = "A", played: Date? = nil) -> Song {
        Song(title: title, artist: artist, fileName: title + ".mp3", lastPlayed: played)
    }

    func testDiversificationKeepsDistinctSongsAndBalancesArtists() {
        let a = (1...10).map { song("A\($0)") }
        let b = (1...4).map { song("B\($0)", artist: "B") }
        let c = (1...4).map { song("C\($0)", artist: "C") }
        let result = HomeMusicSelection.diverse(a + [a[0]] + b + c, limit: 12)
        XCTAssertEqual(result.count, 12)
        XCTAssertEqual(Set(result.map(\.id)).count, 12)
        XCTAssertEqual(Dictionary(grouping: result, by: \.artist).mapValues(\.count), ["A": 4, "B": 4, "C": 4])
        for pair in zip(result, result.dropFirst()) { XCTAssertNotEqual(pair.0.artist, pair.1.artist) }
        XCTAssertTrue(HomeMusicSelection.diverse(a, limit: 0).isEmpty)
    }

    func testRediscoveryExcludesRecentPlaybackAndHasAnUnheardFallback() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = song("Recent", played: now.addingTimeInterval(-3600))
        let old = song("Old", played: now.addingTimeInterval(-60 * 24 * 3600))
        let unheard = song("Unheard")
        XCTAssertEqual(Set(HomeMusicSelection.rediscover([recent, old, unheard], now: now).map(\.id)), [old.id, unheard.id])
        XCTAssertEqual(HomeMusicSelection.rediscover([unheard, old], now: now).first?.id, old.id)
        XCTAssertTrue(HomeMusicSelection.rediscover([recent], now: now).isEmpty)
    }

    func testQuickPicksIncludeLearnedRecentAndForgottenTracks() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let learned = (1...8).map { song("Learned \($0)") }
        let recent = song("Recent", played: now.addingTimeInterval(-3600))
        let forgotten = song("Forgotten", played: now.addingTimeInterval(-60 * 24 * 3600))
        let extras = (1...8).map { song("Extra \($0)") }
        let available = learned + [recent, forgotten] + extras
        let result = HomeMusicSelection.quickPicks(learned + extras + [recent, forgotten], songs: available, now: now)
        XCTAssertEqual(result.count, 12)
        XCTAssertTrue(result.contains { $0.id == recent.id })
        XCTAssertTrue(result.contains { $0.id == forgotten.id })
        XCTAssertTrue(result.contains { $0.id == learned[0].id })
        XCTAssertEqual(Set(result.map(\.id)).count, result.count)
    }

    func testRelatedSelectionUsesStructuredArtistCreditsAndGenre() {
        let favorite = song("Favorite", artist: "Seed")
        var related = song("Related", artist: "Other")
        related.artistNames = ["Other", "Seed"]
        let unrelated = song("Unrelated", artist: "Unknown")
        let result = HomeMusicSelection.similar([unrelated, related, favorite], favorites: [favorite.id], plays: [:])
        XCTAssertEqual(result.first?.id, favorite.id)
        XCTAssertLessThan(result.firstIndex { $0.id == related.id }!, result.firstIndex { $0.id == unrelated.id }!)
    }

    func testResolvingCachedIDsKeepsOrderAndReflectsEditsAndDeletion() {
        let a = song("A"), b = song("B"), removed = song("Removed")
        var edited = a; edited.title = "Edited"
        let result = HomeMusicSelection.resolve([b.id, removed.id, a.id, b.id], in: [edited, b])
        XCTAssertEqual(result.map(\.id), [b.id, a.id])
        XCTAssertEqual(result.last?.title, "Edited")
    }

    func testDailyMixSurvivesRelaunchUntilLocalCalendarDayChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 8))!
        let mix = HomeDailyMix(day: morning, songIDs: [UUID(), UUID()])
        let restored = try JSONDecoder().decode(HomeDailyMix.self, from: JSONEncoder().encode(mix))
        XCTAssertEqual(restored.songIDs, mix.songIDs)
        XCTAssertTrue(restored.isCurrent(at: morning.addingTimeInterval(12 * 3600), calendar: calendar))
        XCTAssertFalse(restored.isCurrent(at: morning.addingTimeInterval(24 * 3600), calendar: calendar))
    }
}
