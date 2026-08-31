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
        favoriteSongIDs: Set<UUID>,
        recommendationManager: RecommendationManager
    ) {
        // Aanbevolen wordt maar één keer per app-run berekend.
        if recommendedSongs == nil {
            recommendedSongs =
                recommendationManager
                    .recommendations(
                        from: songs,
                        favoriteSongIDs: favoriteSongIDs,
                        limit: 12
                    )
        }

        // Recent afgespeeld wordt ook als snapshot bewaard.
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

        // Eerst ALLE favorieten shufflen en daarna pas 10 nemen.
        // Daardoor krijg je bij een nieuwe app-start ook andere songs,
        // niet alleen dezelfde songs in een andere volgorde.
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
