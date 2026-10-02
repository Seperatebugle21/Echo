import Foundation

struct PodcastFollow: Codable {
    var show: PodcastShow
    var enabledAt: Date
    var knownIDs: Set<String>
    var lastChecked: Date
}

enum PodcastReleaseDetection {
    static func fresh(_ episodes: [PodcastEpisode], follow: PodcastFollow, now: Date) -> [PodcastEpisode] {
        episodes.filter {
            guard !follow.knownIDs.contains($0.id) else { return false }
            guard let published = $0.published else { return true }
            return published >= follow.enabledAt && published <= now
        }.sorted { ($0.published ?? now) > ($1.published ?? now) }
    }
    static func knownIDs(after episodes: [PodcastEpisode], follow: PodcastFollow, now: Date) -> Set<String> {
        // Future items remain eligible when their publication date arrives.
        follow.knownIDs.union(episodes.filter { ($0.published ?? now) <= now }.map(\.id))
    }
}

