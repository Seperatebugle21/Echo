import Foundation
import XCTest

final class SmartMusicTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func song(_ title: String, artist: String = "Artist", album: String? = nil) -> Song {
        Song(title: title, artist: artist, fileName: title + ".mp3", album: album)
    }
    func testListeningExcludesPauseAndSeekAndCheckpointsDoNotDuplicate() {
        var tracker = ListeningAccumulator()
        tracker.begin(song: song("One"), at: now)
        tracker.sample(at: now.addingTimeInterval(10), position: 10, playing: true)
        tracker.checkpoint(); tracker.checkpoint()
        XCTAssertEqual(tracker.audibleSeconds, 10, accuracy: 0.001)
        tracker.sample(at: now.addingTimeInterval(20), position: 10, playing: false)
        tracker.reanchor(at: now.addingTimeInterval(20), position: 100)
        tracker.sample(at: now.addingTimeInterval(25), position: 105, playing: true)
        let event = tracker.finish(.skipped)!
        XCTAssertEqual(event.seconds, 15, accuracy: 0.001)
        XCTAssertEqual(event.reason, .skipped)
        XCTAssertNil(tracker.finish(.selected))
    }
    func testUnannouncedSeekAndBackwardSeekNeverInflateListening() {
        var tracker = ListeningAccumulator(); tracker.begin(song: song("One"), at: now)
        tracker.sample(at: now.addingTimeInterval(1), position: 90, playing: true)
        tracker.sample(at: now.addingTimeInterval(2), position: 91, playing: true)
        tracker.sample(at: now.addingTimeInterval(3), position: 20, playing: true)
        tracker.sample(at: now.addingTimeInterval(4), position: 21, playing: true)
        XCTAssertEqual(tracker.finish(.selected)?.seconds, 2)
    }
    func testWeekSplitsMidnightAndUsesUserFirstWeekday() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; calendar.firstWeekday = 2; calendar.minimumDaysInFirstWeek = 4
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 23, minute: 59))!
        let event = ListeningEvent(id: UUID(), songID: UUID(), title: "One", artist: "A", startedAt: start,
            segments: [.init(start: start, end: start.addingTimeInterval(120), seconds: 120)], reason: .completed)
        let current = ListeningWeek.calculate(events: [event], containing: start.addingTimeInterval(120), calendar: calendar)
        let previous = ListeningWeek.calculate(events: [event], containing: start, calendar: calendar)
        XCTAssertEqual(current.seconds, 60, accuracy: 0.001); XCTAssertEqual(previous.seconds, 60, accuracy: 0.001)
        XCTAssertEqual(current.plays, 0); XCTAssertEqual(previous.plays, 1)
        XCTAssertEqual(current.artists, 1); XCTAssertEqual(current.days.count, 7)
        XCTAssertEqual(current.days.reduce(0) { $0 + $1.seconds }, current.seconds)
    }
    func testStatisticsKeepTrackIDsAndNormalizeArtistNames() {
        let a = song("Same", artist: "Artist"), b = song("Same", artist: "ARTIST")
        let events = [a, b].map { ListeningEvent(id: UUID(), songID: $0.id, title: $0.title, artist: $0.artist, startedAt: now,
            segments: [.init(start: now, end: now.addingTimeInterval(60), seconds: 60)], reason: .completed) }
        let result = ListeningWeek.calculate(events: events, containing: now)
        XCTAssertEqual(result.plays, 2); XCTAssertEqual(result.artists, 1); XCTAssertEqual(result.topSongs.count, 2)
        XCTAssertEqual(result.seconds, 120)
    }
    func testHistoryPersistenceRoundTripPreservesPartialEvents() throws {
        var tracker = ListeningAccumulator(); tracker.begin(song: song("One"), at: now)
        tracker.sample(at: now.addingTimeInterval(4), position: 4, playing: true)
        let event = tracker.finish(.selected)!
        let decoded = try JSONDecoder().decode(ListeningEvent.self, from: JSONEncoder().encode(event))
        XCTAssertEqual(decoded.id, event.id); XCTAssertEqual(decoded.seconds, 4); XCTAssertEqual(decoded.reason, .selected)
    }
    func testGemsPreferRelevantForgottenSongsOverRecentFrequentPlayback() {
        let old = song("Old", artist: "Favorite"), current = song("Current", artist: "Favorite"), unrelated = song("Other", artist: "Other")
        let selection = SmartMusicSelection(songs: [old, current, unrelated], favorites: [old.id], learning: [
            current.id: .init(plays: 50, completions: 20, lastPlayed: now), old.id: .init(plays: 1, lastPlayed: now.addingTimeInterval(-90 * 86400))
        ], now: now, seed: 1)
        XCTAssertEqual(selection.ranked(limit: 3, discover: true).first?.id, old.id)
        XCTAssertEqual(selection.ranked(limit: 3, discover: true).last?.id, current.id)
        XCTAssertEqual(selection.ranked(limit: 3, discover: true).map(\.id), selection.ranked(limit: 3, discover: true).map(\.id))
    }
    func testSelectionBalancesArtistsAndRemovesDuplicates() {
        let a = (0..<8).map { song("A\($0)", artist: "A") }, b = (0..<3).map { song("B\($0)", artist: "B") }
        let result = SmartMusicSelection.diverse(a + a + b, limit: 5)
        XCTAssertEqual(Set(result.map(\.id)).count, 5); XCTAssertEqual(result.prefix(4).filter { $0.artist == "A" }.count, 2)
        XCTAssertTrue(SmartMusicSelection.diverse(a, limit: 0).isEmpty)
    }
    func testVibesUseRealGenreAndYearAndWorkWithoutMetadata() {
        var calm = song("Calm", artist: "A"), rock = song("Rock", artist: "B"), old = song("Old", artist: "C")
        calm.genre = "Ambient"; rock.genre = "Rock"; old.releaseYear = 1980
        let selection = SmartMusicSelection(songs: [calm, rock, old], favorites: [], learning: [:], now: now)
        XCTAssertEqual(selection.vibe(.focus, limit: 1).first?.id, calm.id)
        XCTAssertEqual(selection.vibe(.energy, limit: 1).first?.id, rock.id)
        XCTAssertEqual(selection.vibe(.throwback, limit: 1).first?.id, old.id)
        XCTAssertEqual(SmartMusicSelection(songs: [song("Untagged")], favorites: [], learning: [:], now: now).vibe(.chill).count, 1)
    }
    func testRevisitedAlbumsKeepArtistIdentityAndRequireMultipleTracks() {
        let songs = [song("A1", artist: "A", album: "Same"), song("A2", artist: "A", album: "Same"),
                     song("B1", artist: "B", album: "Same"), song("B2", artist: "B", album: "Same"), song("Single", album: "Single")]
        let result = SmartMusicSelection(songs: songs, favorites: [], learning: [:], now: now).albums()
        XCTAssertEqual(result.count, 2); XCTAssertEqual(Set(result.map(\.id)).count, 2)
        XCTAssertTrue(result.allSatisfy { $0.songs.count == 2 })
    }
    func testTimeMachineUsesOnlyRealAvailableHistoricalPeriods() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!, id = UUID(), removed = UUID()
        let daily = [id: ["2026-09-02": 4, "2026-09-03": 2, "2026-10-01": 99], removed: ["2026-07-02": 4]]
        let result = HistoricalMusicPeriod.available(daily: daily, songIDs: [id], now: now, calendar: calendar)
        XCTAssertEqual(result.map(\.monthsAgo), [1]); XCTAssertEqual(result.first?.songIDs, [id])
        XCTAssertTrue(HistoricalMusicPeriod.available(daily: [:], songIDs: [id], now: now, calendar: calendar).isEmpty)
    }
    func testFlowRefillSuspendsForRepeatAndPreservesManualQueueCapacity() {
        XCTAssertTrue(EchoFlowQueuePolicy.shouldRefill(active: true, repeating: false, upcoming: 4, automatic: 3))
        XCTAssertFalse(EchoFlowQueuePolicy.shouldRefill(active: false, repeating: false, upcoming: 0, automatic: 0))
        XCTAssertFalse(EchoFlowQueuePolicy.shouldRefill(active: true, repeating: true, upcoming: 0, automatic: 0))
        XCTAssertFalse(EchoFlowQueuePolicy.shouldRefill(active: true, repeating: false, upcoming: 12, automatic: 2))
    }
    func testFlowExclusionsLeaveCandidateInSmallLibrary() {
        let current = UUID(), previous = UUID(), manual = UUID()
        XCTAssertEqual(EchoFlowQueuePolicy.exclusions(current: current, upcoming: [], recent: [previous], libraryCount: 2), [current])
        let excluded = EchoFlowQueuePolicy.exclusions(current: current, upcoming: [manual], recent: [previous], libraryCount: 20)
        XCTAssertTrue(excluded.isSuperset(of: [current, manual, previous]))
    }
    func testEmptyLibraryProducesNoRecommendations() {
        let selection = SmartMusicSelection(songs: [], favorites: [], learning: [:], now: now)
        XCTAssertTrue(selection.ranked(limit: 10, discover: true).isEmpty); XCTAssertTrue(selection.vibe(.chill).isEmpty); XCTAssertTrue(selection.albums().isEmpty)
    }
}
