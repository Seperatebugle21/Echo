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


    func addAuthorizedMatch(
    track: SpotifyTrack,
    youtubeResult: YouTubeSearchResult
) {

    let item = FetchItem(
        spotifyURL: track.spotifyURL,
        title: track.name,
        artist: track.artist,
        album: track.album,
        artworkURL: track.artworkURL,

        youtubeURL:
            youtubeResult.videoURL,

        permissionConfirmed: true
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


    private func process(
    _ item: FetchItem
) async {

    item.status = .preparing


    do {

        guard let youtubeURL =
            item.youtubeURL
        else {

            throw ApifyDownloadError.invalidURL
        }


        // MARK: Apify

        let apifyResult =
            try await ApifyAudioSource.shared
                .resolveMP3(
                    youtubeURL: youtubeURL,
                    permissionConfirmed:
                        item.permissionConfirmed
                )


        item.status =
            .downloading(0)


        // MARK: Download generated MP3

        let audioResult =
            FetchAudioResult(
                downloadURL:
                    apifyResult.downloadURL,

                suggestedFileName:
                    makeMP3Name(
                        item: item,
                        apifyName:
                            apifyResult.fileName
                    )
            )


        _ =
            try await FetchDownloadEngine.shared
                .download(
                    item: item,
                    result: audioResult
                ) { progress in

                    item.status =
                        .downloading(progress)
                }


        item.status = .processing


        /*
         MP3 staat nu in Documents.

         Echo's MusicLibraryManager scant die map.
        */

        NotificationCenter.default.post(
            name: .echoFetchCompleted,
            object: nil
        )


        item.status = .completed


    } catch {

        item.status =
            .failed(
                error.localizedDescription
            )

        print(
            "Fetch failed:",
            error
        )
    }
}

    private func makeMP3Name(
    item: FetchItem,
    apifyName: String?
) -> String {

    let illegal =
        CharacterSet(
            charactersIn:
                "/\\:*?\"<>|"
        )

    let base =
        "\(item.title) - \(item.artist)"

    let cleaned =
        base
            .components(
                separatedBy: illegal
            )
            .joined(separator: "")

    return "\(cleaned).mp3"
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

extension Notification.Name {

    static let echoFetchCompleted =
        Notification.Name(
            "EchoFetchCompleted"
        )
}
