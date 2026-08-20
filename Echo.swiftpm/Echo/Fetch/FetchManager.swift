import Foundation

@MainActor
@Observable
final class FetchManager {

    static let shared = FetchManager()

    private(set) var items: [FetchItem] = []

    private var running = false

    private var audioSource: FetchAudioSource =
    DirectMP3AudioSource.shared

    private init() {}

    // MARK: - Raw Spotify URL

    func addSpotifyURL(_ string: String) {

        guard let reference =
            SpotifyURLParser.parse(string)
        else {
            return
        }

        let item = FetchItem(
            spotifyURL: reference.url,
            title: defaultTitle(for: reference.type),
            artist: "Spotify"
        )

        items.append(item)

        startIfNeeded()
    }


    // MARK: - Spotify Library Track

    func add(_ track: SpotifyTrack) {

        let item = FetchItem(
            spotifyURL: track.spotifyURL,
            title: track.name,
            artist: track.artist,
            album: track.album,
            artworkURL: track.artworkURL
        )

        items.append(item)

        startIfNeeded()
    }


    // MARK: - Spotify Playlist

    func add(_ playlist: SpotifyPlaylist) {

        let item = FetchItem(
            spotifyURL: playlist.spotifyURL,
            title: playlist.name,
            artist: "\(playlist.trackCount) songs",
            artworkURL: playlist.artworkURL
        )

        items.append(item)

        startIfNeeded()
    }


    // MARK: - Remove

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


    // MARK: - Queue

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


    // MARK: - Processing

    private func process(
    _ item: FetchItem
) async {

    item.status = .preparing

    do {

        let settings =
            FetchSettings.shared

        let audio =
            try await audioSource.resolveAudio(
                for: item,
                quality: settings.quality
            )

        item.status = .downloading(0)

        let fileURL =
            try await FetchDownloadEngine.shared
                .download(
                    item: item,
                    result: audio
                ) { progress in

                    item.status =
                        .downloading(progress)
                }

        item.status = .processing

        // Het bestand staat al in Echo/Documents.
        // Jouw MusicLibraryManager kan dit vervolgens
        // gewoon als een normale song importeren.
        MusicLibraryManager.shared
            .importSong(
                from: fileURL
            )

        item.status = .completed

    } catch {

        item.status =
            .failed(
                error.localizedDescription
            )
    }
}


    private func defaultTitle(
        for type: SpotifyContentType
    ) -> String {

        switch type {

        case .track:
            return "Spotify Track"

        case .album:
            return "Spotify Album"

        case .playlist:
            return "Spotify Playlist"
        }
    }
}
