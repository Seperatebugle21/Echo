import Foundation

@MainActor
final class HomeSessionManager {

    static let shared = HomeSessionManager()

    private(set) var recommendedSongs: [Song]?
    private(set) var recentlyPlayedSongs: [Song]?
    private(set) var favoriteSongs: [Song]?
    private var dailyMix: HomeDailyMix?
    private var similarIDs: [UUID]?
    private var rediscoveryIDs: [UUID]?
    private var albumIDs: [String] = []
    private var artistIDs: [String] = []

    private init() {
        dailyMix = UserDefaults.standard.data(forKey: "EchoHomeDailyMixV1")
            .flatMap { try? JSONDecoder().decode(HomeDailyMix.self, from: $0) }
    }

    func refreshRecommendations(songs: [Song], favoriteSongIDs: [UUID], recommendationManager: RecommendationManager) {
        let ranked = recommendationManager.recommendations(from: songs, favoriteSongIDs: favoriteSongIDs, limit: songs.count)
        let previousIDs = (recommendedSongs ?? []).map(\.id)
        let previous = Set(previousIDs)
        // Rotate in other eligible songs when the library has more than twelve.
        recommendedSongs = HomeMusicSelection.diverse(
            ranked.filter { !previous.contains($0.id) } + ranked.filter { previous.contains($0.id) }, limit: 12
        )
        if recommendedSongs?.map(\.id) == previousIDs,
           let first = recommendedSongs?.first, (recommendedSongs?.count ?? 0) > 1 {
            recommendedSongs = Array((recommendedSongs ?? []).dropFirst()) + [first]
        }
        EchoWidgetSnapshotPublisher.requestUpdate()
    }

    func mixes(songs: [Song], favoriteSongIDs: [UUID], recommendationManager: RecommendationManager,
               now: Date = Date()) -> [[Song]] {
        guard !songs.isEmpty else { return [[], [], []] }
        if dailyMix?.isCurrent(at: now) != true {
            let ranked = recommendationManager.recommendations(from: songs, favoriteSongIDs: favoriteSongIDs, limit: songs.count)
            dailyMix = HomeDailyMix(day: now, songIDs: HomeMusicSelection.diverse(ranked, limit: 24).map(\.id))
            if let data = try? JSONEncoder().encode(dailyMix) {
                UserDefaults.standard.set(data, forKey: "EchoHomeDailyMixV1")
            }
        }
        if similarIDs == nil || HomeMusicSelection.resolve(similarIDs ?? [], in: songs).isEmpty {
            similarIDs = HomeMusicSelection.similar(songs, favorites: Set(favoriteSongIDs),
                plays: recommendationManager.learningData.mapValues(\.playCount)).map(\.id)
        }
        if rediscoveryIDs == nil {
            rediscoveryIDs = HomeMusicSelection.rediscover(songs, now: now).map(\.id)
        }
        return [HomeMusicSelection.resolve(dailyMix?.songIDs ?? [], in: songs),
                HomeMusicSelection.resolve(similarIDs ?? [], in: songs),
                HomeMusicSelection.resolve(rediscoveryIDs ?? [], in: songs).filter {
                    ($0.lastPlayed ?? .distantPast) < now.addingTimeInterval(-14 * 24 * 60 * 60)
                }]
    }


    // Random once per process; returning to Home keeps the same selection.
    func artistSelection(from artists: [ArtistGroup]) -> [String] {
        let available = Set(artists.map(\.id))
        artistIDs.removeAll { !available.contains($0) }
        let selected = Set(artistIDs)
        let remaining = artists.map(\.id).filter { !selected.contains($0) }.shuffled()
        artistIDs.append(contentsOf: remaining.prefix(max(0, 12 - artistIDs.count)))
        return artistIDs
    }

    func albumSelection(from available: [String]) -> [String] {
        albumIDs = OnlineCatalogLogic.refillSelection(albumIDs, available: available)
        return albumIDs
    }

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
                HomeMusicSelection.quickPicks(recommendationManager.recommendations(
                    from: songs, favoriteSongIDs: favoriteSongIDs, limit: songs.count
                ), songs: songs)
        }


        recentlyPlayedSongs = Array(songs.filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }.prefix(12))
        favoriteSongs = Array(favorites.prefix(12))
    }
}
