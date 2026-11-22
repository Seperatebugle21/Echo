import Foundation

enum ListeningRecapPeriod: String, CaseIterable, Identifiable, Sendable {
    case week, month, year, allTime
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .week: "recap_period_week"
        case .month: "recap_period_month"
        case .year: "recap_period_year"
        case .allTime: "recap_period_all_time"
        }
    }

    var calendarComponent: Calendar.Component? {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .allTime: nil
        }
    }
}

/// Listening totals and rankings for one period. Play counts come from the daily
/// start counts (which go back furthest); listening time from the audible segments.
struct ListeningRecap: Sendable {
    struct Ranked: Identifiable, Sendable, Hashable {
        var id: String
        var title: String
        var subtitle: String
        /// A library song to show artwork for (and to play).
        var songID: UUID?
        var plays: Int
        var seconds: Double
    }

    struct Bucket: Identifiable, Sendable, Hashable {
        var id: Date
        var seconds: Double
        var plays: Int
    }

    enum BucketUnit: Sendable { case day, month, year }

    let period: ListeningRecapPeriod
    /// Nil for all time.
    let interval: DateInterval?
    var seconds: Double = 0
    var plays = 0
    var distinctSongs = 0
    var distinctArtists = 0
    var activeDays = 0
    var longestStreak = 0
    var peakHour: Int?
    var hours: [Double] = Array(repeating: 0, count: 24)
    var topSongs: [Ranked] = []
    var topArtists: [Ranked] = []
    var topAlbums: [Ranked] = []
    var topGenres: [Ranked] = []
    var buckets: [Bucket] = []
    var bucketUnit: BucketUnit = .day

    var isEmpty: Bool { plays == 0 && seconds < 1 }

    static func interval(for period: ListeningRecapPeriod, offset: Int, now: Date, calendar: Calendar) -> DateInterval? {
        guard let component = period.calendarComponent else { return nil }
        let date = calendar.date(byAdding: component, value: -offset, to: now) ?? now
        return calendar.dateInterval(of: component, for: date)
    }

    static func calculate(
        period: ListeningRecapPeriod,
        offset: Int = 0,
        events: [ListeningEvent],
        daily: [UUID: [String: Int]],
        songs: [Song],
        now: Date = Date(),
        calendar: Calendar = .current,
        limit: Int = 10
    ) -> ListeningRecap {
        let interval = interval(for: period, offset: offset, now: now, calendar: calendar)
        var recap = ListeningRecap(period: period, interval: interval)
        let library = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let firstKey = interval.map { SmartListeningSnapshot.dayKey($0.start, calendar: calendar) }
        let lastKey = interval.map { SmartListeningSnapshot.dayKey($0.end, calendar: calendar) }

        var songPlays: [UUID: Int] = [:]
        var songSeconds: [UUID: Double] = [:]
        var fallbackNames: [UUID: (title: String, artist: String)] = [:]
        var dayPlays: [String: Int] = [:]
        var daySeconds: [String: Double] = [:]

        // Starts per day.
        for (id, days) in daily {
            for (key, count) in days where count > 0 {
                if let firstKey, let lastKey, !(key >= firstKey && key < lastKey) { continue }
                songPlays[id, default: 0] += count
                dayPlays[key, default: 0] += count
            }
        }

        // Audible time, clipped to the period and split at day boundaries.
        for event in events where event.seconds > 0 {
            var contribution = 0.0
            for segment in event.segments where segment.seconds > 0 && segment.end > segment.start {
                let total = segment.end.timeIntervalSince(segment.start)
                var cursor = max(segment.start, interval?.start ?? segment.start)
                let end = min(segment.end, interval?.end ?? segment.end)
                while cursor < end {
                    // Split at hour boundaries (which are also day boundaries) for the hour chart.
                    let boundary = min(end, calendar.dateInterval(of: .hour, for: cursor)?.end ?? end)
                    let value = segment.seconds * boundary.timeIntervalSince(cursor) / total
                    daySeconds[SmartListeningSnapshot.dayKey(cursor, calendar: calendar), default: 0] += value
                    let hour = calendar.component(.hour, from: cursor)
                    if recap.hours.indices.contains(hour) { recap.hours[hour] += value }
                    contribution += value
                    guard boundary > cursor else { break }
                    cursor = boundary
                }
            }
            guard contribution > 0 else { continue }
            songSeconds[event.songID, default: 0] += contribution
            if fallbackNames[event.songID] == nil { fallbackNames[event.songID] = (event.title, event.artist) }
        }

        recap.seconds = daySeconds.values.reduce(0, +)
        recap.plays = dayPlays.values.reduce(0, +)

        // Rankings.
        var artistTotals: [String: Ranked] = [:]
        var albumTotals: [String: Ranked] = [:]
        var genreTotals: [String: Ranked] = [:]
        var songRanking: [Ranked] = []
        for id in Set(songPlays.keys).union(songSeconds.keys) {
            let plays = songPlays[id] ?? 0, seconds = songSeconds[id] ?? 0
            guard plays > 0 || seconds > 0 else { continue }
            let song = library[id]
            guard let title = song?.title ?? fallbackNames[id]?.title,
                  let artist = song?.artist ?? fallbackNames[id]?.artist else { continue }
            songRanking.append(Ranked(id: id.uuidString, title: title, subtitle: artist,
                                      songID: song?.id, plays: plays, seconds: seconds))
            let artistKey = SmartMusicSelection.artistKey(artist)
            if !artistKey.isEmpty {
                artistTotals[artistKey, default: Ranked(id: artistKey, title: artist, subtitle: "", songID: song?.id, plays: 0, seconds: 0)]
                    .add(plays: plays, seconds: seconds, songID: song?.id)
            }
            if let song, let album = song.album?.trimmingCharacters(in: .whitespacesAndNewlines), !album.isEmpty {
                let key = LibraryAlbumDestination(name: album, artist: song.artist).identity
                albumTotals[key, default: Ranked(id: key, title: album, subtitle: song.artist, songID: song.id, plays: 0, seconds: 0)]
                    .add(plays: plays, seconds: seconds, songID: song.id)
            }
            if let genre = song?.genre?.trimmingCharacters(in: .whitespacesAndNewlines), !genre.isEmpty {
                let key = genre.lowercased()
                genreTotals[key, default: Ranked(id: key, title: genre, subtitle: "", songID: nil, plays: 0, seconds: 0)]
                    .add(plays: plays, seconds: seconds, songID: nil)
            }
        }
        recap.distinctSongs = songRanking.count
        recap.distinctArtists = artistTotals.count
        recap.topSongs = Array(songRanking.sorted(by: Ranked.ranksBefore).prefix(limit))
        recap.topArtists = Array(artistTotals.values.sorted(by: Ranked.ranksBefore).prefix(limit))
        recap.topAlbums = Array(albumTotals.values.sorted(by: Ranked.ranksBefore).prefix(limit))
        recap.topGenres = Array(genreTotals.values.sorted(by: Ranked.ranksBefore).prefix(6))

        // Days and streaks.
        let activeKeys = Set(dayPlays.filter { $0.value > 0 }.keys).union(daySeconds.filter { $0.value >= 30 }.keys)
        recap.activeDays = activeKeys.count
        recap.longestStreak = longestStreak(activeKeys.compactMap { date(fromKey: $0, calendar: calendar) }, calendar: calendar)
        if recap.hours.contains(where: { $0 > 0 }) {
            recap.peakHour = recap.hours.indices.max { recap.hours[$0] < recap.hours[$1] }
        }

        // Chart buckets.
        switch period {
        case .week, .month:
            recap.bucketUnit = .day
            if let interval {
                var day = interval.start
                while day < interval.end {
                    let key = SmartListeningSnapshot.dayKey(day, calendar: calendar)
                    recap.buckets.append(Bucket(id: day, seconds: daySeconds[key] ?? 0, plays: dayPlays[key] ?? 0))
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
                    day = next
                }
            }
        case .year:
            recap.bucketUnit = .month
            if let interval {
                var month = interval.start
                while month < interval.end {
                    let prefix = String(SmartListeningSnapshot.dayKey(month, calendar: calendar).prefix(7))
                    recap.buckets.append(Bucket(id: month,
                        seconds: daySeconds.filter { $0.key.hasPrefix(prefix) }.values.reduce(0, +),
                        plays: dayPlays.filter { $0.key.hasPrefix(prefix) }.values.reduce(0, +)))
                    guard let next = calendar.date(byAdding: .month, value: 1, to: month), next > month else { break }
                    month = next
                }
            }
        case .allTime:
            recap.bucketUnit = .year
            let years = Set(activeKeys.compactMap { Int($0.prefix(4)) })
            if let first = years.min(), let last = years.max() {
                for year in first...last {
                    let prefix = String(format: "%04d", year)
                    guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { continue }
                    recap.buckets.append(Bucket(id: start,
                        seconds: daySeconds.filter { $0.key.hasPrefix(prefix) }.values.reduce(0, +),
                        plays: dayPlays.filter { $0.key.hasPrefix(prefix) }.values.reduce(0, +)))
                }
            }
        }
        return recap
    }

    /// The earliest day with any recorded listening, to limit going back in time.
    static func earliestActivity(events: [ListeningEvent], daily: [UUID: [String: Int]], calendar: Calendar = .current) -> Date? {
        let firstKey = daily.values.flatMap(\.keys).min()
        let fromDaily = firstKey.flatMap { date(fromKey: $0, calendar: calendar) }
        let fromEvents = events.map(\.startedAt).min()
        return [fromDaily, fromEvents].compactMap { $0 }.min()
    }

    static func date(fromKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func longestStreak(_ days: [Date], calendar: Calendar) -> Int {
        let sorted = Set(days.map { calendar.startOfDay(for: $0) }).sorted()
        var best = 0, current = 0
        var previous: Date?
        for day in sorted {
            if let previous, let expected = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(expected, inSameDayAs: day) {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            previous = day
        }
        return best
    }
}

extension ListeningRecap.Ranked {
    mutating func add(plays: Int, seconds: Double, songID: UUID?) {
        self.plays += plays
        self.seconds += seconds
        if self.songID == nil { self.songID = songID }
    }

    static func ranksBefore(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.plays != rhs.plays { return lhs.plays > rhs.plays }
        if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
        return lhs.id < rhs.id
    }
}
