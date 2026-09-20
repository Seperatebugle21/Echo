import Foundation

enum HomeDiscoverySelection {
    /// Never call an old, already-started, undated or future episode a new release.
    static func newEpisode(
        in feed: [PodcastEpisode],
        knownEpisodes: [PodcastEpisode],
        listening: [String: PodcastListeningState],
        now: Date = Date()
    ) -> PodcastEpisode? {
        guard let showID = feed.first?.show.id else { return nil }
        let heard = knownEpisodes.filter { episode in
            guard episode.show.id == showID, let status = listening[episode.id] else { return false }
            return status.played || status.position > 0
        }
        guard !heard.isEmpty else { return nil }
        let newestHeard = heard.compactMap(\.published).max()
        let recentCutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        return feed.filter { episode in
            guard let date = episode.published, date <= now, date >= recentCutoff else { return false }
            if let newestHeard, date <= newestHeard { return false }
            let status = listening[episode.id]
            return status?.played != true && (status?.position ?? 0) == 0
        }.max { ($0.published ?? .distantPast) < ($1.published ?? .distantPast) }
    }
}
