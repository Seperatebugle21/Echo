import Foundation

/// The days of Schakel, counted in the player's own calendar from the first puzzle.
enum PuzzleCalendar {
    /// Puzzle 1 was on 1 January 2026.
    static let firstDay = DateComponents(year: 2026, month: 1, day: 1)

    static func dayIndex(for date: Date = .init(), calendar: Calendar = .current) -> Int {
        let start = calendar.date(from: firstDay) ?? .distantPast
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return max(days, 0)
    }

    static func date(forDay index: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.date(from: firstDay) ?? .init()
        return calendar.date(byAdding: .day, value: index, to: start) ?? start
    }

    /// The moment the next daily puzzle unlocks.
    static func nextPuzzleDate(after date: Date = .init(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }
}

/// The result of one finished day.
struct DayResult: Codable, Equatable {
    var dayIndex: Int
    var score: Int
    var squares: String
    /// Played on the day itself, so it counts for the streak.
    var onTheDay: Bool
}

/// Everything the player achieved in one language.
struct PlayerStats: Codable, Equatable {
    var days: [Int: DayResult] = [:]
    var bestEndlessRun: Int = 0
    var bestEndlessScore: Int = 0
    var endlessRoundsSolved: Int = 0
    var endlessRunsPlayed: Int = 0

    var daysPlayed: Int { days.count }
    var bestDayScore: Int { days.values.map(\.score).max() ?? 0 }
    var averageDayScore: Int {
        days.isEmpty ? 0 : days.values.reduce(0) { $0 + $1.score } / days.count
    }
    var perfectDays: Int { days.values.filter { $0.score == GameSession.dailyRoundCount * Round.maxPoints }.count }

    /// Days in a row played on the day, ending today or yesterday.
    func currentStreak(today: Int) -> Int {
        var day = days[today]?.onTheDay == true ? today : today - 1
        var count = 0
        while days[day]?.onTheDay == true {
            count += 1
            day -= 1
        }
        return count
    }

    var longestStreak: Int {
        let played = days.values.filter(\.onTheDay).map(\.dayIndex).sorted()
        var best = 0, run = 0, previous: Int?
        for day in played {
            run = (previous == day - 1) ? run + 1 : 1
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// How many days scored in each band of 1000 points (0–999, 1000–1999 … 5000).
    var scoreBands: [Int] {
        var bands = Array(repeating: 0, count: 6)
        for result in days.values {
            bands[min(result.score / 1000, 5)] += 1
        }
        return bands
    }

    mutating func record(_ session: GameSession, today: Int) {
        switch session.mode {
        case .daily, .archive:
            guard let day = session.dayIndex, days[day] == nil else { return }
            days[day] = DayResult(dayIndex: day, score: session.score, squares: session.resultSquares,
                                  onTheDay: session.mode == .daily && day == today)
        case .endless:
            endlessRunsPlayed += 1
            let solved = session.correctRounds
            endlessRoundsSolved += solved
            bestEndlessRun = max(bestEndlessRun, solved)
            bestEndlessScore = max(bestEndlessScore, session.score)
        }
    }
}
