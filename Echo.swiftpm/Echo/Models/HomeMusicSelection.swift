import Foundation

/// Local-only selection rules shared by Home's session cache and its tests.
enum HomeMusicSelection {
    static func diverse(_ ranked: [Song], limit: Int) -> [Song] {
        guard limit > 0 else { return [] }
        var remaining = ranked
        var result: [Song] = []
        var seen = Set<UUID>()
        var counts: [String: Int] = [:]
        while !remaining.isEmpty && result.count < limit {
            let least = remaining.map { counts[ArtistCredits.key($0.artist), default: 0] }.min() ?? 0
            let index = remaining.firstIndex {
                counts[ArtistCredits.key($0.artist), default: 0] == least
                    && (result.last.map { ArtistCredits.key($0.artist) } != ArtistCredits.key($0.artist))
            } ?? remaining.firstIndex { counts[ArtistCredits.key($0.artist), default: 0] == least } ?? 0
            let song = remaining.remove(at: index)
            guard seen.insert(song.id).inserted else { continue }
            result.append(song)
            counts[ArtistCredits.key(song.artist), default: 0] += 1
        }
        return result
    }

    static func rediscover(_ songs: [Song], now: Date = Date(), limit: Int = 24) -> [Song] {
        let cutoff = now.addingTimeInterval(-14 * 24 * 60 * 60)
        let eligible = songs.filter { ($0.lastPlayed ?? .distantPast) < cutoff }
            .sorted { ($0.lastPlayed ?? .distantPast) < ($1.lastPlayed ?? .distantPast) }
        return diverse(eligible, limit: limit)
    }

    static func similar(_ songs: [Song], favorites: Set<UUID>, plays: [UUID: Int], limit: Int = 24) -> [Song] {
        let seeds = songs.filter { favorites.contains($0.id) || $0.lastPlayed != nil }
        let artists = Set(seeds.flatMap { ArtistCredits.names(for: $0).map(ArtistCredits.key) })
        let genres = Set(seeds.compactMap { $0.genre?.lowercased() })
        func score(_ song: Song) -> Int {
            let related = ArtistCredits.names(for: song).contains { artists.contains(ArtistCredits.key($0)) }
            return (related ? 10 : 0) + (song.genre.map { genres.contains($0.lowercased()) } == true ? 5 : 0)
                + (favorites.contains(song.id) ? 3 : 0) + min(plays[song.id, default: 0], 5)
        }
        return diverse(songs.sorted { score($0) > score($1) }, limit: limit)
    }

    static func resolve(_ ids: [UUID], in songs: [Song]) -> [Song] {
        let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        return ids.compactMap { byID[$0] }.filter { seen.insert($0.id).inserted }
    }
}

struct HomeDailyMix: Codable {
    let day: Date
    let songIDs: [UUID]

    func isCurrent(at now: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, inSameDayAs: now)
    }
}
