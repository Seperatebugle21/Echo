import Foundation

struct SmartPlaylistRule: Identifiable, Codable, Equatable {
    enum Field: String, Codable, CaseIterable {
        case favorite, artist, album, addedWithinDays, playedWithinDays
        case notPlayedInDays, neverPlayed, playCountAtLeast, playCountAtMost

        var labelKey: String { "smart_field_" + rawValue }
        var needsText: Bool { self == .artist || self == .album }
        var needsDays: Bool {
            self == .addedWithinDays || self == .playedWithinDays || self == .notPlayedInDays
        }
        var needsCount: Bool { self == .playCountAtLeast || self == .playCountAtMost }
    }

    var id = UUID()
    var field: Field = .favorite
    var text = ""
    var number = 30
    var favorite = true

    var isValid: Bool {
        if field.needsText { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if field.needsDays { return (1...3650).contains(number) }
        if field.needsCount { return (0...100000).contains(number) }
        return true
    }

    func matches(_ song: Song, favorites: Set<UUID>, now: Date, calendar: Calendar) -> Bool {
        guard isValid else { return false }
        let cutoff = calendar.date(byAdding: .day, value: -number, to: now) ?? .distantPast
        switch field {
        case .favorite: return favorites.contains(song.id) == favorite
        case .artist:
            return song.artist.localizedCaseInsensitiveContains(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case .album:
            return song.album?.localizedCaseInsensitiveContains(text.trimmingCharacters(in: .whitespacesAndNewlines)) == true
        case .addedWithinDays: return song.dateAdded >= cutoff && song.dateAdded <= now
        case .playedWithinDays:
            guard let lastPlayed = song.lastPlayed else { return false }
            return lastPlayed >= cutoff && lastPlayed <= now
        case .notPlayedInDays:
            // Unknown history is not evidence of an old listen. Use Never Played for that.
            guard let lastPlayed = song.lastPlayed else { return false }
            return lastPlayed < cutoff
        case .neverPlayed: return song.lastPlayed == nil && song.recordedPlayCount == 0
        case .playCountAtLeast: return song.recordedPlayCount >= number
        case .playCountAtMost: return song.recordedPlayCount <= number
        }
    }
}

struct SmartPlaylistConfiguration: Codable, Equatable {
    enum MatchMode: String, Codable, CaseIterable {
        case all, any
        var labelKey: String { "smart_match_" + rawValue }
    }

    enum SortOrder: String, Codable, CaseIterable {
        case newest, mostPlayed, recentlyPlayed, title, random
        var labelKey: String { "smart_sort_" + rawValue }
    }

    var rules: [SmartPlaylistRule] = [SmartPlaylistRule()]
    var matchMode: MatchMode = .all
    var sortOrder: SortOrder = .newest
    // Zero means unlimited.
    var limit = 0
    // Stable randomized order: UI refreshes must not reshuffle or change the limited subset.
    var randomSeed = UUID().uuidString

    var isValid: Bool {
        !rules.isEmpty && rules.allSatisfy(\.isValid) && [0, 25, 50, 100].contains(limit)
    }

    func songs(in library: [Song], favorites: Set<UUID>, now: Date = Date(), calendar: Calendar = .current) -> [Song] {
        guard isValid else { return [] }
        let matching = library.filter { song in
            switch matchMode {
            case .all: return rules.allSatisfy { $0.matches(song, favorites: favorites, now: now, calendar: calendar) }
            case .any: return rules.contains { $0.matches(song, favorites: favorites, now: now, calendar: calendar) }
            }
        }
        let sorted = matching.sorted { lhs, rhs in
            switch sortOrder {
            case .newest:
                if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded > rhs.dateAdded }
            case .mostPlayed:
                if lhs.recordedPlayCount != rhs.recordedPlayCount { return lhs.recordedPlayCount > rhs.recordedPlayCount }
            case .recentlyPlayed:
                let left = lhs.lastPlayed ?? .distantPast
                let right = rhs.lastPlayed ?? .distantPast
                if left != right { return left > right }
            case .title:
                let result = lhs.title.localizedStandardCompare(rhs.title)
                if result != .orderedSame { return result == .orderedAscending }
            case .random:
                let left = randomRank(lhs.id)
                let right = randomRank(rhs.id)
                if left != right { return left < right }
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return limit == 0 ? sorted : Array(sorted.prefix(limit))
    }

    private func randomRank(_ id: UUID) -> UInt64 {
        // FNV-1a is deterministic across launches (unlike Swift's Hasher).
        (randomSeed + id.uuidString).utf8.reduce(UInt64(14695981039346656037)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
    }
}

enum SmartPlaylistPreset: String, CaseIterable, Identifiable {
    case recentlyAdded, topSongs, forgottenFavorites, undiscovered
    var id: String { rawValue }
    var nameKey: String { "smart_preset_" + rawValue }

    var configuration: SmartPlaylistConfiguration {
        switch self {
        case .recentlyAdded:
            return SmartPlaylistConfiguration(rules: [SmartPlaylistRule(field: .addedWithinDays, number: 30)])
        case .topSongs:
            return SmartPlaylistConfiguration(rules: [SmartPlaylistRule(field: .playCountAtLeast, number: 1)], sortOrder: .mostPlayed, limit: 50)
        case .forgottenFavorites:
            return SmartPlaylistConfiguration(rules: [SmartPlaylistRule(), SmartPlaylistRule(field: .notPlayedInDays, number: 30)])
        case .undiscovered:
            return SmartPlaylistConfiguration(rules: [SmartPlaylistRule(field: .neverPlayed)])
        }
    }
}
