import Foundation

@MainActor
final class HomeSessionManager {

    static let shared = HomeSessionManager()

    private(set) var recommendedSongs: [Song]?
    private(set) var recentlyPlayedSongs: [Song]?
    private(set) var favoriteSongs: [Song]?

    private init() {}

    func prepareIfNeeded(
        songs: [Song],
        favorites: [Song],
        favoriteSongIDs: [UUID],
        recommendationManager: RecommendationManager
    ) {

        guard !songs.isEmpty else {
            recommendedSongs = nil
            recentlyPlayedSongs = nil
            favoriteSongs = nil
            return
        }

        // Keep session order stable, but replace edited values and remove deleted
        // songs. Refill after imports so Home and the widget share actual picks.
        if let previous = recommendedSongs {
            let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var refreshed = previous.compactMap { byID[$0.id] }
            let desiredCount = min(12, songs.count)
            if refreshed.count < desiredCount {
                let selected = Set(refreshed.map(\.id))
                let additional = recommendationManager.recommendations(
                    from: songs, favoriteSongIDs: favoriteSongIDs, limit: songs.count
                ).filter { !selected.contains($0.id) }
                refreshed.append(contentsOf: additional.prefix(desiredCount - refreshed.count))
            }
            recommendedSongs = refreshed
        }

        // MARK: - Recommended

     
        if recommendedSongs == nil {

            recommendedSongs =
                recommendationManager
                    .recommendations(
                        from: songs,
                        favoriteSongIDs: favoriteSongIDs,
                        limit: 12
                    )
        }


        // MARK: - Recently Played

        if recentlyPlayedSongs == nil {

            recentlyPlayedSongs =
                Array(
                    songs
                        .filter {
                            $0.lastPlayed != nil
                        }
                        .sorted {
                            ($0.lastPlayed ?? .distantPast)
                            >
                            ($1.lastPlayed ?? .distantPast)
                        }
                        .prefix(10)
                )
        }


        // MARK: - Favorites

     
        if favoriteSongs == nil {

            favoriteSongs =
                Array(
                    favorites
                        .shuffled()
                        .prefix(10)
                )
        }
    }
}
