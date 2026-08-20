import Foundation

@MainActor
@Observable
final class FetchManager {

    static let shared = FetchManager()

    private(set) var items: [FetchItem] = []

    private var running = false

    private init() {}

    func addSpotifyURL(_ string: String) {

        guard let url = URL(string: string) else {
            return
        }

        guard isSpotifyURL(url) else {
            return
        }

        let item = FetchItem(
            spotifyURL: url
        )

        items.append(item)

        startIfNeeded()
    }

    func remove(_ item: FetchItem) {
        items.removeAll {
            $0.id == item.id
        }
    }

    func clearCompleted() {
        items.removeAll {
            if case .completed = $0.status {
                return true
            }

            return false
        }
    }

    private func startIfNeeded() {

        guard !running else {
            return
        }

        running = true

        Task {
            await processQueue()

            running = false
        }
    }

    private func processQueue() async {

        for item in items {

            guard case .queued = item.status else {
                continue
            }

            await process(item)
        }
    }

    private func process(
        _ item: FetchItem
    ) async {

        item.status = .preparing

        do {

            /*
             The actual Sunnify processing layer
             will be connected here.

             Spotify URL
                 ↓
             metadata
                 ↓
             matching
                 ↓
             authorized audio source
                 ↓
             MP3 processing
                 ↓
             Echo Library
            */

            try await Task.sleep(
                for: .milliseconds(500)
            )

            item.status = .downloading(0)

            for step in 1...20 {

                try await Task.sleep(
                    for: .milliseconds(100)
                )

                item.status =
                    .downloading(
                        Double(step) / 20
                    )
            }

            item.status = .processing

            try await Task.sleep(
                for: .milliseconds(300)
            )

            item.status = .completed

        } catch {

            item.status =
                .failed(error.localizedDescription)
        }
    }

    private func isSpotifyURL(
        _ url: URL
    ) -> Bool {

        guard
            let host = url.host?.lowercased()
        else {
            return false
        }

        return host == "open.spotify.com"
            || host == "spotify.com"
    }
}
