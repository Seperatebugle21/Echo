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
            return
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
