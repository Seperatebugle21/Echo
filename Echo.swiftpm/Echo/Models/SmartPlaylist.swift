import Foundation

enum SmartField: String, Codable, CaseIterable, Identifiable {
    case title, artist, album, genre, favorite, releaseYear, dateAdded, lastPlayed, playCount
    var id: String { rawValue }
    var key: String { "smart_field_" + rawValue }
    var text: Bool { [.title, .artist, .album, .genre].contains(self) }
    var date: Bool { self == .dateAdded || self == .lastPlayed }
}
enum SmartComparison: String, Codable, CaseIterable, Identifiable {
    case equals, contains, minimum, maximum, range, missing, withinDays, olderThanDays
    var id: String { rawValue }
    var key: String { "smart_compare_" + rawValue }
}
struct SmartRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var field: SmartField = .playCount
    var comparison: SmartComparison = .minimum
    var text = ""
    var value: Double = 1
    var upper: Double = 10
    var periodDays: Int? = nil
    var comparisons: [SmartComparison] {
        if field.text { return [.equals, .contains, .missing] }
        if field == .favorite { return [.equals] }
        if field.date { return [.withinDays, .olderThanDays, .missing] }
        return [.equals, .minimum, .maximum, .range] + (field == .releaseYear ? [.missing] : [])
    }
}
enum SmartSort: String, Codable, CaseIterable, Identifiable {
    case title, artist, newest, lastPlayed, mostPlayed, leastPlayed, oldestYear, newestYear
    var id: String { rawValue }
    var key: String { "smart_sort_" + rawValue }
}
struct SmartPlaylistDefinition: Codable, Equatable {
    var rules: [SmartRule] = []
    var matchAll = true
    var sort: SmartSort = .mostPlayed
    var limit: Int? = 50
    var periodDays: Int? = nil
}
/// Only reset songs have local counts. All other songs retain global listening history.
struct SmartSongOverride: Codable, Equatable {
    var manuallyIncluded = false
    var excludedUntil: Date?
    var totalSinceReset: Int?
    var dailySinceReset: [String: Int]?

    func isExcluded(at now: Date) -> Bool { excludedUntil.map { now < $0 } ?? false }
    mutating func remove(at now: Date) {
        manuallyIncluded = false
        excludedUntil = now.addingTimeInterval(120 * 3600)
        totalSinceReset = 0
        dailySinceReset = [:]
    }
    @discardableResult mutating func include(at now: Date) -> Bool {
        guard !isExcluded(at: now) else { return false }
        excludedUntil = nil
        manuallyIncluded = true
        return true
    }
    mutating func recordPlay(at now: Date) {
        guard let count = totalSinceReset else { return }
        totalSinceReset = count + 1
        var daily = dailySinceReset ?? [:]
        daily[SmartListeningSnapshot.dayKey(now), default: 0] += 1
        dailySinceReset = daily
    }
}

struct SmartListeningSnapshot {
    var total: [UUID: Int] = [:]
    var daily: [UUID: [String: Int]] = [:]
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
    func count(_ id: UUID, days: Int?, now: Date, calendar: Calendar = .current) -> Int {
        guard let days else { return total[id] ?? 0 }
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
        let lower = Self.dayKey(first, calendar: calendar), upper = Self.dayKey(today, calendar: calendar)
        return (daily[id] ?? [:]).reduce(0) { $0 + ($1.key >= lower && $1.key <= upper ? $1.value : 0) }
    }
    func counts(days: Int?, now: Date, calendar: Calendar = .current) -> [UUID: Int] {
        guard let days else { return total }
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
        let lower = Self.dayKey(first, calendar: calendar), upper = Self.dayKey(today, calendar: calendar)
        return daily.mapValues { entries in
            entries.reduce(0) { $0 + ($1.key >= lower && $1.key <= upper ? $1.value : 0) }
        }
    }
}
enum SmartPlaylistEvaluator {
    static func songs(_ definition: SmartPlaylistDefinition, from songs: [Song], favorites: Set<UUID>, listening: SmartListeningSnapshot, now: Date = Date(), overrides: [UUID: SmartSongOverride] = [:]) -> [Song] {
        var listening = listening
        for (id, override) in overrides {
            if let count = override.totalSinceReset {
                listening.total[id] = count
                listening.daily[id] = override.dailySinceReset ?? [:]
            }
        }
        // Compute each listening window once, rather than during every sort comparison.
        var counts: [Int?: [UUID: Int]] = [:]
        let periods = Set(definition.rules.filter { $0.field == .playCount }.map(\.periodDays))
        for period in periods { counts[period] = listening.counts(days: period, now: now) }
        let sortPeriod = definition.periodDays
        if definition.sort == .mostPlayed || definition.sort == .leastPlayed, counts[sortPeriod] == nil {
            counts[sortPeriod] = listening.counts(days: definition.periodDays, now: now)
        }
        let filtered = songs.filter { song in
            guard overrides[song.id]?.isExcluded(at: now) != true else { return false }
            // Manual songs are added after applying the automatic selection limit.
            guard overrides[song.id]?.manuallyIncluded != true else { return false }
            let ruleMatches: [Bool] = definition.rules.map { rule in
                Self.matches(rule, song: song, favorites: favorites, counts: counts, now: now)
            }
            return ruleMatches.isEmpty || (definition.matchAll ? ruleMatches.allSatisfy { $0 } : ruleMatches.contains(true))
        }
        let precedes: (Song, Song) -> Bool = { a, b in
            let ac = counts[sortPeriod]?[a.id] ?? 0
            let bc = counts[sortPeriod]?[b.id] ?? 0
            switch definition.sort {
            case .newest: if a.dateAdded != b.dateAdded { return a.dateAdded > b.dateAdded }
            case .lastPlayed: if a.lastPlayed != b.lastPlayed { return (a.lastPlayed ?? .distantPast) > (b.lastPlayed ?? .distantPast) }
            case .mostPlayed: if ac != bc { return ac > bc }
            case .leastPlayed: if ac != bc { return ac < bc }
            case .oldestYear: if a.releaseYear != b.releaseYear { return (a.releaseYear ?? Int.max) < (b.releaseYear ?? Int.max) }
            case .newestYear: if a.releaseYear != b.releaseYear { return (a.releaseYear ?? 0) > (b.releaseYear ?? 0) }
            case .artist: if a.artist != b.artist { return a.artist.localizedStandardCompare(b.artist) == .orderedAscending }
            case .title: break
            }
            let order = a.title.localizedStandardCompare(b.title)
            return order == .orderedSame ? a.id.uuidString < b.id.uuidString : order == .orderedAscending
        }
        let sorted = filtered.sorted(by: precedes)
        let automatic = definition.limit.map { Array(sorted.prefix(max(0, $0))) } ?? sorted
        let manual = songs.filter { overrides[$0.id]?.manuallyIncluded == true && overrides[$0.id]?.isExcluded(at: now) != true }
        var seen: Set<UUID> = []
        return (automatic + manual).filter { seen.insert($0.id).inserted }.sorted(by: precedes)
    }
    private static func matches(_ rule: SmartRule, song: Song, favorites: Set<UUID>, counts: [Int?: [UUID: Int]], now: Date) -> Bool {
        guard rule.value.isFinite, rule.upper.isFinite, abs(rule.value) <= 1_000_000, abs(rule.upper) <= 1_000_000 else { return false }
        if rule.field == .favorite { return favorites.contains(song.id) == (rule.value != 0) }
        if rule.field.text {
            let value: String?
            switch rule.field { case .title: value = song.title; case .artist: value = song.artist; case .album: value = song.album; case .genre: value = song.genre; default: value = nil }
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return rule.comparison == .missing }
            if rule.comparison == .missing { return false }
            let target = rule.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { return false }
            if rule.comparison == .contains { return value.localizedStandardContains(target) }
            let candidates = rule.field == .artist ? (song.artistNames ?? [value]) : [value]
            return candidates.contains { $0.compare(target, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        }
        if rule.field.date {
            let date = rule.field == .dateAdded ? song.dateAdded : song.lastPlayed
            guard let date else { return rule.comparison == .missing }
            if rule.comparison == .missing { return false }
            let cutoff = Calendar.current.date(byAdding: .day, value: -Int(rule.value), to: now) ?? now
            return rule.comparison == .withinDays ? date >= cutoff && date <= now : date < cutoff
        }
        let number = rule.field == .releaseYear ? song.releaseYear.map(Double.init) : Double(counts[rule.periodDays]?[song.id] ?? 0)
        guard let number else { return rule.comparison == .missing }
        switch rule.comparison {
        case .equals: return number == rule.value
        case .minimum: return number >= rule.value
        case .maximum: return number <= rule.value
        case .range: return number >= min(rule.value, rule.upper) && number <= max(rule.value, rule.upper)
        default: return false
        }
    }
}
enum SmartPreset: String, CaseIterable, Identifiable {
    case mostPlayed, trending, added, played, discover, forgotten, favorites, genre, eighties, nineties, twoThousands, tens, years, custom
    var id: String { rawValue }
    var key: String { "smart_preset_" + rawValue }
    var definition: SmartPlaylistDefinition {
        var result = SmartPlaylistDefinition()
        switch self {
        case .mostPlayed: result.rules = [SmartRule(value: 1)]
        case .trending: result.rules = [SmartRule(periodDays: 30)]; result.periodDays = 30
        case .added: result.rules = [SmartRule(field: .dateAdded, comparison: .withinDays, value: 30)]; result.sort = .newest
        case .played: result.rules = [SmartRule(field: .lastPlayed, comparison: .withinDays, value: 30)]; result.sort = .lastPlayed
        case .discover: result.rules = [SmartRule(comparison: .maximum, value: 1)]; result.sort = .leastPlayed
        case .forgotten: result.rules = [SmartRule(field: .lastPlayed, comparison: .olderThanDays, value: 90), SmartRule(field: .lastPlayed, comparison: .missing)]; result.matchAll = false; result.sort = .leastPlayed
        case .favorites: result.rules = [SmartRule(field: .favorite, comparison: .equals)]; result.sort = .title
        case .genre: result.rules = [SmartRule(field: .genre, comparison: .equals)]; result.sort = .title
        case .eighties, .nineties, .twoThousands, .tens, .years:
            let start = self == .eighties ? 1980 : self == .nineties ? 1990 : self == .tens ? 2010 : 2000
            result.rules = [SmartRule(field: .releaseYear, comparison: .range, value: Double(start), upper: Double(start + 9))]; result.sort = .oldestYear
        case .custom: result.sort = .title
        }
        return result
    }
}
