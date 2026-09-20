import Foundation
import Observation

/// Both entry points use the same recommendation policy and catalog cache.
@MainActor @Observable
final class PodcastRecommendationsModel {
    private(set) var shows: [PodcastShow] = []
    private(set) var loading = true
    private(set) var failed = false
    var retry = 0
    private var completedTaskID: String?

    var taskID: String {
        let ids = PodcastStore.shared.savedShows.map(\.id).sorted().map(String.init).joined(separator: ",")
        return "\(retry):\(ids)"
    }

    func load() async {
        let requestID = taskID
        guard completedTaskID != requestID else { return }
        loading = shows.isEmpty
        failed = false
        let saved = PodcastStore.shared.savedShows
        let savedIDs = Set(saved.map(\.id))
        let seed = saved.first(where: { !$0.author.isEmpty })?.author ?? "podcast"
        let country = Locale.current.region?.identifier ?? "US"
        do {
            var results = try await PodcastCatalog.shared.search(seed, country: country)
                .filter { !savedIDs.contains($0.id) }
            if results.isEmpty && seed != "podcast" {
                results = try await PodcastCatalog.shared.search("podcast", country: country)
                    .filter { !savedIDs.contains($0.id) }
            }
            try Task.checkCancellation()
            guard requestID == taskID else { return }
            shows = Array(results.prefix(12))
            completedTaskID = requestID
            loading = false
        } catch {
            guard !Task.isCancelled else { return }
            failed = shows.isEmpty
            loading = false
        }
    }
}
