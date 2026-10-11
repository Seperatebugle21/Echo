import Foundation

enum MusicVibe: String, CaseIterable, Identifiable, Sendable {
    case chill, energy, focus, throwback
    var id: String { rawValue }
    var symbol: String {
        switch self { case .chill: return "leaf.fill"; case .energy: return "bolt.fill"; case .focus: return "scope"; case .throwback: return "clock.arrow.circlepath" }
    }
}
enum EchoFlowMode: String, CaseIterable, Sendable { case familiar, discover }

/// A value snapshot of the existing learning engine. No invented BPM/mood/audio features.
struct SmartMusicSelection: Sendable {
    struct Learning: Sendable {
        var plays: Int = 0
        var completions: Int = 0
        var skips: Int = 0
        var lastPlayed: Date?
    }
    let songs: [Song]
    let favorites: Set<UUID>
    let learning: [UUID: Learning]
    let now: Date
    var seed: UInt64 = 0

    static func artistKey(_ artist: String) -> String {
        artist.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private var affinity: [String: Double] {
        var totals: [String: Double] = [:], counts: [String: Int] = [:]
        for song in songs {
            let key = Self.artistKey(song.artist), data = learning[song.id] ?? Learning()
            totals[key, default: 0] += Double(data.plays) + Double(data.completions) * 3 + (favorites.contains(song.id) ? 8 : 0)
            counts[key, default: 0] += 1
        }
        return totals.mapValues { $0 }.reduce(into: [String: Double]()) { result, entry in
            result[entry.key] = entry.value / sqrt(Double(counts[entry.key, default: 1]))
        }
    }
    private func novelty(_ song: Song) -> Double {
        let data = learning[song.id] ?? Learning()
        let age = now.timeIntervalSince(data.lastPlayed ?? song.lastPlayed ?? .distantPast) / 86400
        return 12 / Double(data.plays + 1) + min(8, max(0, age) / 14) - (age < 3 ? 15 : 0) - min(8, Double(data.skips) * 1.5)
    }
    private func tie(_ id: UUID) -> Double {
        // Stable session variation, independent of Swift's randomized Hasher.
        var value = seed ^ 1469598103934665603
        for byte in id.uuidString.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }
        return Double(value % 1000) / 1000
    }
    func ranked(limit: Int, discover: Bool, excluding: Set<UUID> = [], anchor: Song? = nil) -> [Song] {
        let artists = affinity
        var scored: [(Song, Double)] = []
        for song in songs where !excluding.contains(song.id) {
            let data = learning[song.id] ?? Learning()
            var score = log1p(max(0, artists[Self.artistKey(song.artist), default: 0])) * 5
            if discover { score += novelty(song) }
            else {
                score += min(14, Double(data.plays) + Double(data.completions) * 2)
                score += favorites.contains(song.id) ? 12 : 0
                score += novelty(song) * 0.2
            }
            score -= min(6, Double(data.skips) * 0.75)
            if let anchor {
                if Self.artistKey(anchor.artist) == Self.artistKey(song.artist) { score += 3 }
                if let genre = anchor.genre, !genre.isEmpty, genre.caseInsensitiveCompare(song.genre ?? "") == .orderedSame { score += 4 }
            }
            scored.append((song, score + tie(song.id) * 4))
        }
        scored.sort { $0.1 == $1.1 ? $0.0.id.uuidString < $1.0.id.uuidString : $0.1 > $1.1 }
        return Self.diverse(scored.map { $0.0 }, limit: limit)
    }
    static func diverse(_ ranked: [Song], limit: Int) -> [Song] {
        guard limit > 0 else { return [] }
        var result: [Song] = [], deferred: [Song] = [], counts: [String: Int] = [:], seen: Set<UUID> = []
        for song in ranked where seen.insert(song.id).inserted {
            let key = artistKey(song.artist)
            if counts[key, default: 0] < 2 { result.append(song); counts[key, default: 0] += 1 }
            else { deferred.append(song) }
            if result.count == limit { return result }
        }
        return Array((result + deferred).prefix(max(0, limit)))
    }
    func vibe(_ vibe: MusicVibe, limit: Int = 25) -> [Song] {
        let preferredGenres: [String]
        switch vibe {
        case .chill: preferredGenres = ["ambient", "chill", "acoustic", "soul", "jazz", "downtempo"]
        case .energy: preferredGenres = ["dance", "rock", "metal", "punk", "electronic", "hip hop", "hip-hop"]
        case .focus: preferredGenres = ["instrumental", "classical", "ambient", "soundtrack", "lo-fi", "piano"]
        case .throwback: preferredGenres = []
        }
        let base = ranked(limit: songs.count, discover: false)
        let year = Calendar.current.component(.year, from: now)
        let matches = base.filter { song in
            if vibe == .throwback {
                return song.releaseYear.map { $0 > 0 && $0 <= year - 10 } == true ||
                    learning[song.id].map { $0.plays > 0 && now.timeIntervalSince($0.lastPlayed ?? now) > 90 * 86400 } == true
            }
            let genre = Self.artistKey(song.genre ?? "")
            return preferredGenres.contains { genre.contains($0) }
        }
        let matchedIDs = Set(matches.map(\.id))
        // Metadata is a preference, not a claim of measured mood. Small libraries still play.
        let pool = matches + base.filter { !matchedIDs.contains($0.id) }
        let familiar = pool.filter { favorites.contains($0.id) || learning[$0.id, default: Learning()].plays > 1 }
        let unfamiliar = pool.filter { !favorites.contains($0.id) && learning[$0.id, default: Learning()].plays <= 1 }
        var interleaved: [Song] = []
        for index in 0..<max(familiar.count, unfamiliar.count) {
            if familiar.indices.contains(index) { interleaved.append(familiar[index]) }
            if unfamiliar.indices.contains(index) { interleaved.append(unfamiliar[index]) }
        }
        return Self.diverse(interleaved, limit: limit)
    }
    func albums() -> [AlbumGroup] {
        let artists = affinity
        var ranked: [(AlbumGroup, Double)] = []
        for album in LibraryAlbums.groups(from: songs) where album.songs.count >= 2 {
            let last = album.songs.compactMap { learning[$0.id]?.lastPlayed ?? $0.lastPlayed }.max()
            let age = min(365, max(0, now.timeIntervalSince(last ?? .distantPast) / 86400))
            var score = age / 14
            score += log1p(artists[Self.artistKey(album.artist), default: 0]) * 4
            score += Double(min(album.songs.count, 12)) * 0.2
            ranked.append((album, score))
        }
        ranked.sort { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }
        return ranked.map { $0.0 }
    }
}

enum EchoFlowQueuePolicy {
    /// Repeat modes own automatic selection while enabled. Shuffle only reorders the same queue.
    static func shouldRefill(active: Bool, repeating: Bool, upcoming: Int, automatic: Int) -> Bool {
        active && !repeating && upcoming < 12 && automatic <= 4
    }
    static func exclusions(current: UUID?, upcoming: [UUID], recent: [UUID], libraryCount: Int) -> Set<UUID> {
        var excluded = Set(upcoming); if let current { excluded.insert(current) }
        let recentSet = Set(recent.suffix(min(20, max(0, libraryCount - excluded.count - 1))))
        excluded.formUnion(recentSet); return excluded
    }
}
