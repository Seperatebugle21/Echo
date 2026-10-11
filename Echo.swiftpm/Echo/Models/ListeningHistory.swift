import Foundation

enum ListeningEndReason: String, Codable, Sendable { case completed, skipped, selected, failed }

struct ListeningSegment: Codable, Sendable {
    let start: Date
    let end: Date
    let seconds: Double
}

struct ListeningEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let songID: UUID
    let title: String
    let artist: String
    let startedAt: Date
    var segments: [ListeningSegment] = []
    var reason: ListeningEndReason?
    var seconds: Double { segments.reduce(0) { $0 + $1.seconds } }
}

/// Counts audible advancement, never a seek destination or time spent paused/buffering.
struct ListeningAccumulator {
    private(set) var event: ListeningEvent?
    private var anchor: (date: Date, position: Double)?
    private var pending: ListeningSegment?
    var audibleSeconds: Double { (event?.seconds ?? 0) + (pending?.seconds ?? 0) }

    mutating func begin(song: Song, at date: Date, position: Double = 0) {
        event = ListeningEvent(id: UUID(), songID: song.id, title: song.title, artist: song.artist, startedAt: date)
        anchor = (date, position); pending = nil
    }
    mutating func sample(at date: Date, position: Double, playing: Bool) {
        defer { anchor = (date, position) }
        guard position.isFinite, let old = anchor, playing, event != nil else { return }
        let elapsed = date.timeIntervalSince(old.date)
        let advancement = position - old.position
        guard elapsed > 0, advancement > 0 else { return }
        // Ignore discontinuities (seeks). A small tolerance accommodates audio snapshot jitter.
        guard advancement <= elapsed * 2 + 0.5 else { checkpoint(); return }
        let seconds = min(elapsed, advancement)
        if let previous = pending {
            pending = ListeningSegment(start: previous.start, end: date, seconds: previous.seconds + seconds)
        } else { pending = ListeningSegment(start: old.date, end: date, seconds: seconds) }
    }
    mutating func reanchor(at date: Date, position: Double) { checkpoint(); anchor = (date, position) }
    mutating func checkpoint() {
        if let pending { event?.segments.append(pending) }
        pending = nil
    }
    mutating func finish(_ reason: ListeningEndReason) -> ListeningEvent? {
        checkpoint(); event?.reason = reason
        defer { event = nil; anchor = nil }
        return event
    }
}

struct ListeningWeek: Sendable {
    struct RankedSong: Identifiable, Sendable { var id: UUID; var title: String; var artist: String; var seconds: Double }
    struct RankedArtist: Identifiable, Sendable { var id: String; var name: String; var seconds: Double }
    struct Day: Identifiable, Sendable { var id: Date; var seconds: Double }
    let interval: DateInterval
    var seconds: Double = 0
    var plays: Int = 0
    var artists: Int = 0
    var topSongs: [RankedSong] = []
    var topArtists: [RankedArtist] = []
    var days: [Day] = []

    static func calculate(events: [ListeningEvent], containing date: Date, calendar: Calendar = .current) -> Self {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 7 * 86400)
        var result = Self(interval: interval)
        var songs: [UUID: RankedSong] = [:], artistTotals: [String: RankedArtist] = [:], daily: [Date: Double] = [:]
        for event in events where event.seconds > 0 {
            var contribution = 0.0
            for segment in event.segments where segment.seconds > 0 && segment.end > segment.start {
                var cursor = max(segment.start, interval.start)
                let end = min(segment.end, interval.end)
                while cursor < end {
                    let day = calendar.startOfDay(for: cursor)
                    let boundary = min(end, calendar.date(byAdding: .day, value: 1, to: day) ?? end)
                    let value = segment.seconds * boundary.timeIntervalSince(cursor) / segment.end.timeIntervalSince(segment.start)
                    daily[day, default: 0] += value; contribution += value; cursor = boundary
                }
            }
            guard contribution > 0 else { continue }
            if interval.start <= event.startedAt && event.startedAt < interval.end { result.plays += 1 }
            result.seconds += contribution
            songs[event.songID, default: RankedSong(id: event.songID, title: event.title, artist: event.artist, seconds: 0)].seconds += contribution
            let key = SmartMusicSelection.artistKey(event.artist)
            if !key.isEmpty {
                artistTotals[key, default: RankedArtist(id: key, name: event.artist, seconds: 0)].seconds += contribution
            }
        }
        result.artists = artistTotals.count
        result.topSongs = Array(songs.values.sorted { $0.seconds == $1.seconds ? $0.id.uuidString < $1.id.uuidString : $0.seconds > $1.seconds }.prefix(5))
        result.topArtists = Array(artistTotals.values.sorted { $0.seconds == $1.seconds ? $0.id < $1.id : $0.seconds > $1.seconds }.prefix(5))
        var day = interval.start
        while day < interval.end {
            result.days.append(Day(id: day, seconds: daily[calendar.startOfDay(for: day), default: 0]))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }; day = next
        }
        return result
    }
}

struct HistoricalMusicPeriod: Identifiable, Sendable {
    let monthsAgo: Int
    let songIDs: [UUID]
    var id: Int { monthsAgo }
    static func available(daily: [UUID: [String: Int]], songIDs: Set<UUID>, now: Date = Date(), calendar: Calendar = .current) -> [Self] {
        [1, 3, 6, 12].compactMap { months in
            guard let date = calendar.date(byAdding: .month, value: -months, to: now),
                  let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
            let first = SmartListeningSnapshot.dayKey(interval.start, calendar: calendar), last = SmartListeningSnapshot.dayKey(interval.end, calendar: calendar)
            let ranked = daily.compactMap { id, days -> (UUID, Int)? in
                guard songIDs.contains(id) else { return nil }
                let count = days.filter { $0.key >= first && $0.key < last }.values.reduce(0, +)
                return count > 0 ? (id, count) : nil
            }.sorted { $0.1 == $1.1 ? $0.0.uuidString < $1.0.uuidString : $0.1 > $1.1 }
            return ranked.isEmpty ? nil : Self(monthsAgo: months, songIDs: ranked.map(\.0))
        }
    }
}
