import Foundation

/// Hard constraints applied before recommendation scoring and before continuous Flow admission.
/// These are metadata filters, not claims about measured acoustic mood or tempo.
enum AIDJSelection {
    static func admits(_ song: Song, query: String, excluded: [String], selectedIDs: Set<UUID>) -> Bool {
        guard song.podcastEpisodeID == nil else { return false }
        let metadata = [song.title, song.artist, song.album ?? "", song.genre ?? ""].joined(separator: " ")
        guard !excluded.contains(where: { term in
            !term.isEmpty && (UUID(uuidString: term) == song.id || metadata.localizedStandardContains(term))
        }) else { return false }
        if !selectedIDs.isEmpty { return selectedIDs.contains(song.id) }
        return query.isEmpty || metadata.localizedStandardContains(query)
    }
    static func preferUnplayed(_ ranked: [Song], recent: Set<UUID>, current: UUID?, limit: Int) -> [Song] {
        var seen = Set<UUID>()
        let unique = ranked.filter { $0.id != current && seen.insert($0.id).inserted }
        return Array((unique.filter { !recent.contains($0.id) } + unique.filter { recent.contains($0.id) }).prefix(max(0, min(100, limit))))
    }
}
