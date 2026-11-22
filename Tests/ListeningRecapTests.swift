import Foundation
import XCTest

final class ListeningRecapTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func event(_ song: Song, start: Date, seconds: Double) -> ListeningEvent {
        ListeningEvent(id: UUID(), songID: song.id, title: song.title, artist: song.artist, startedAt: start,
                       segments: [ListeningSegment(start: start, end: start.addingTimeInterval(seconds), seconds: seconds)])
    }

    func testMonthRanksByPlaysAndClipsTimeToThePeriod() {
        var first = Song(title: "One", artist: "Alpha", fileName: "1.mp3", album: "Debut")
        first.genre = "Pop"
        let second = Song(title: "Two", artist: "Beta", fileName: "2.mp3", album: "Second")
        let daily: [UUID: [String: Int]] = [
            first.id: ["2026-11-02": 2, "2026-11-03": 1, "2026-10-31": 9],
            second.id: ["2026-11-03": 1]
        ]
        // Starts at 23:30 on Oct 31: only the 30 minutes after midnight belong to November.
        let events = [
            event(first, start: date(2026, 10, 31, 23).addingTimeInterval(1800), seconds: 3600),
            event(second, start: date(2026, 11, 3, 8), seconds: 600)
        ]
        let recap = ListeningRecap.calculate(period: .month, events: events, daily: daily, songs: [first, second],
                                             now: date(2026, 11, 22), calendar: calendar)
        XCTAssertEqual(recap.plays, 4)
        XCTAssertEqual(recap.seconds, 1800 + 600, accuracy: 0.01)
        XCTAssertEqual(recap.topSongs.map(\.title), ["One", "Two"])
        XCTAssertEqual(recap.topArtists.first?.title, "Alpha")
        XCTAssertEqual(recap.topAlbums.first?.title, "Debut")
        XCTAssertEqual(recap.topGenres.map(\.title), ["Pop"])
        XCTAssertEqual(recap.buckets.count, 30)
        XCTAssertEqual(recap.peakHour, 0)
        // Nov 1 (30 audible minutes), Nov 2 and Nov 3.
        XCTAssertEqual(recap.longestStreak, 3)
    }

    func testPreviousYearAndAllTime() {
        let song = Song(title: "Old", artist: "Gamma", fileName: "o.mp3")
        let daily: [UUID: [String: Int]] = [song.id: ["2025-03-01": 3, "2026-01-01": 1]]
        let lastYear = ListeningRecap.calculate(period: .year, offset: 1, events: [], daily: daily, songs: [song],
                                                now: date(2026, 11, 22), calendar: calendar)
        XCTAssertEqual(lastYear.plays, 3)
        XCTAssertEqual(lastYear.buckets.count, 12)
        XCTAssertEqual(lastYear.buckets[2].plays, 3)
        let allTime = ListeningRecap.calculate(period: .allTime, events: [], daily: daily, songs: [song],
                                               now: date(2026, 11, 22), calendar: calendar)
        XCTAssertEqual(allTime.plays, 4)
        XCTAssertEqual(allTime.buckets.count, 2)
        XCTAssertEqual(ListeningRecap.earliestActivity(events: [], daily: daily, calendar: calendar), date(2025, 3, 1, 0))
    }

    func testStreakCountsConsecutiveDaysOnly() {
        let days = [date(2026, 1, 1), date(2026, 1, 2), date(2026, 1, 3), date(2026, 1, 5)]
        XCTAssertEqual(ListeningRecap.longestStreak(days, calendar: calendar), 3)
        XCTAssertEqual(ListeningRecap.longestStreak([], calendar: calendar), 0)
    }

    func testEmptyHistory() {
        let recap = ListeningRecap.calculate(period: .week, events: [], daily: [:], songs: [], now: date(2026, 11, 22), calendar: calendar)
        XCTAssertTrue(recap.isEmpty)
        XCTAssertNil(recap.peakHour)
        XCTAssertEqual(recap.buckets.count, 7)
    }
}
