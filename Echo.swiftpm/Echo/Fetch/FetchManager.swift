import Foundation

@MainActor
@Observable
final class FetchManager {

    static let shared = FetchManager()

    private(set) var items: [FetchItem] = []

    private var running = false

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
            title: defaultTitle(
                for: reference.type
            ),
            artist: "Spotify"
        )

        items.append(item)

        startIfNeeded()
    }


    // MARK: - Authorized YouTube Match

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
            youtubeURL: youtubeResult.videoURL,
            permissionConfirmed: true
        )

        items.append(item)

        startIfNeeded()
    }


   

    // MARK: - Playlist
    //
    // Voorlopig niet gebruiken vanuit de UI.
    // We laten de functie bestaan voor later.

    func preparePlaylist(
        _ playlist: SpotifyPlaylist
    ) async throws {

        let tracks =
            try await SpotifyAPI.shared
                .getPlaylistTracks(
                    playlistID: playlist.id
                )

        for track in tracks {

            await preparePlaylistTrack(
                track
            )
        }

        startIfNeeded()
    }


    private func preparePlaylistTrack(
        _ track: SpotifyTrack
    ) async {

        do {

            switch ApifySettings.shared.downloadMethod {

            case .youtube:

                let results =
                    try await YouTubeAPI.shared.search(
                        title: track.name,
                        artist: track.artist,
                        maxResults: 1
                    )

                guard let firstResult =
                        results.first
                else {

                    print(
                        "Geen YouTube-resultaat voor:",
                        track.name
                    )

                    return
                }

                let item = FetchItem(
                    spotifyURL: track.spotifyURL,
                    title: track.name,
                    artist: track.artist,
                    album: track.album,
                    artworkURL: track.artworkURL,
                    youtubeURL: firstResult.videoURL,
                    permissionConfirmed: true
                )

                items.append(item)


            case .spotify:

                let item = FetchItem(
                    spotifyURL: track.spotifyURL,
                    title: track.name,
                    artist: track.artist,
                    album: track.album,
                    artworkURL: track.artworkURL,
                    youtubeURL: nil,
                    permissionConfirmed: true
                )

                items.append(item)
            }

        } catch {

            print(
                "Playlist track voorbereiden mislukt:",
                track.name,
                error
            )
        }
    }


    // MARK: - Prepare Track

    private func prepareTrack(
        _ track: SpotifyTrack
    ) async {

        do {

            let results =
                try await YouTubeAPI.shared.search(
                    title: track.name,
                    artist: track.artist,
                    maxResults: 1
                )

            guard let firstResult =
                    results.first
            else {

                print(
                    "Geen match gevonden:",
                    track.name
                )

                return
            }

            print(
                "Match:",
                track.name,
                "→",
                firstResult.title
            )

        } catch {

            print(
                "YouTube zoeken mislukt:",
                track.name,
                error
            )
        }
    }


    // MARK: - Spotify Library Track

    func add(
        _ track: SpotifyTrack
    ) {

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

    func add(
        _ playlist: SpotifyPlaylist
    ) {

        let item = FetchItem(
            spotifyURL: playlist.spotifyURL,
            title: playlist.name,
            artist:
                "\(playlist.trackCount) songs",
            artworkURL:
                playlist.artworkURL
        )

        items.append(item)

        startIfNeeded()
    }


    // MARK: - Remove

    func remove(
        _ item: FetchItem
    ) {

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

  func addAuthorizedSpotifyTrack(
    _ track: SpotifyTrack
) {

    print(
        "Adding Spotify track to queue:",
        track.name,
        track.spotifyURL
    )

    let item = FetchItem(
        spotifyURL: track.spotifyURL,
        title: track.name,
        artist: track.artist,
        album: track.album,
        artworkURL: track.artworkURL,
        youtubeURL: nil,
        permissionConfirmed: true
    )

    items.append(item)

    print(
        "Fetch queue count:",
        items.count
    )

    startIfNeeded()
}


    // MARK: - Queue
private func startIfNeeded() {

    guard !running else {

        print(
            "Fetch queue already running"
        )

        return
    }

    guard items.contains(
        where: { item in

            if case .queued = item.status {
                return true
            }

            return false
        }
    ) else {

        print(
            "No queued Fetch items"
        )

        return
    }

    running = true

    Task {

        await processQueue()

        running = false

        // Voor het geval er exact op dit
        // moment nog iets toegevoegd werd.

        if items.contains(
            where: { item in

                if case .queued = item.status {
                    return true
                }

                return false
            }
        ) {
            startIfNeeded()
        }
    }
}


  private func processQueue() async {

    while true {

        guard let nextItem =
                items.first(
                    where: { item in

                        if case .queued = item.status {
                            return true
                        }

                        return false
                    }
                )
        else {
            break
        }

        await process(nextItem)
    }
}


    // MARK: - Process

   private func process(
    _ item: FetchItem
) async {

    item.status = .preparing

    do {

        let method =
            ApifySettings.shared
                .downloadMethod

        let downloadResult:
            FetchAudioResult


        print(
            "Processing:",
            item.title
        )

        print(
            "Selected method:",
            method.rawValue
        )

        print(
            "Spotify URL:",
            item.spotifyURL
        )

        print(
            "YouTube URL:",
            item.youtubeURL?.absoluteString
            ?? "NONE"
        )

        print(
            "Permission:",
            item.permissionConfirmed
        )


        // MARK: - Resolve download source

        switch method {

        // =========================================
        // YOUTUBE
        // =========================================

        case .youtube:

            guard let youtubeURL =
                    item.youtubeURL
            else {

                throw
                    ApifyDownloadError
                        .invalidURL
            }

            let apifyResult =
                try await
                ApifyAudioSource.shared
                    .resolveMP3(
                        youtubeURL:
                            youtubeURL,

                        permissionConfirmed:
                            item.permissionConfirmed
                    )

            downloadResult =
                FetchAudioResult(
                    downloadURL:
                        apifyResult.downloadURL,

                    suggestedFileName:
                        makeTemporaryVideoName(
                            item: item
                        )
                )


        // =========================================
        // SPOTIFY
        // =========================================

      case .spotify:

    guard item.permissionConfirmed else {
        throw ApifyDownloadError.permissionRequired
    }

    let spotifyResult =
        try await SpotifyApifyAudioSource.shared
            .resolve(
                spotifyURL: item.spotifyURL
            )

    print(
        "Spotify resolved URL:",
        spotifyResult.downloadURL
    )

    downloadResult =
        FetchAudioResult(
            downloadURL:
                spotifyResult.downloadURL,

            suggestedFileName:
                makeTemporarySpotifyName(
                    item: item
                )
        )
        }


        // MARK: - Download

        item.status =
            .downloading(0)

        let downloadedFile =
            try await
            FetchDownloadEngine.shared
                .download(
                    item: item,
                    result: downloadResult
                ) { progress in

                    item.status =
                        .downloading(
                            progress
                        )
                }


        print(
            "Downloaded source:",
            downloadedFile
        )


        // MARK: - Processing

        item.status =
            .processing


        /*
         Zowel YouTube als Spotify worden nu
         door dezelfde processor gestuurd.

         Daardoor krijgen beide:

         - echte M4A output
         - title metadata
         - artist metadata
         - album metadata
         - artwork
        */

        let finalAudioURL =
            try await
            FetchMediaProcessor.shared
                .convertToM4A(
                    sourceURL:
                        downloadedFile,
                    item: item
                )


        print(
            "Final Echo audio:",
            finalAudioURL
        )


        // MARK: - Remove temporary source

        if downloadedFile != finalAudioURL {

            try?
                FileManager.default
                    .removeItem(
                        at: downloadedFile
                    )
        }


        // MARK: - Refresh Echo Library

        NotificationCenter.default.post(
            name: .echoFetchCompleted,
            object: nil
        )


        // Als je MusicLibraryManager.shared
        // effectief gebruikt in je project,
        // mag dit ook blijven:
        //
        // MusicLibraryManager.shared
        //     .syncDocumentsFolder()


        item.status =
            .completed


        print(
            "Fetch completed:",
            item.title
        )


    } catch {

        item.status =
            .failed(
                error.localizedDescription
            )

        print(
            "Fetch failed:",
            item.title,
            error
        )
    }
}

    private func makeTemporaryVideoName(
        item: FetchItem
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
                    separatedBy:
                        illegal
                )
                .joined(
                    separator: ""
                )

        return
            "\(cleaned)-source.mp4"
    }


   private func makeTemporarySpotifyName(
    item: FetchItem
) -> String {

    let illegal =
        CharacterSet(
            charactersIn: "/\\:*?\"<>|"
        )

    let base =
        "\(item.title) - \(item.artist)"

    let cleaned =
        base
            .components(
                separatedBy: illegal
            )
            .joined(separator: "")

    return "\(cleaned)-spotify-source.mp3"
}

    private func makeSpotifyAudioName(
        item: FetchItem
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
                    separatedBy:
                        illegal
                )
                .joined(
                    separator: ""
                )

        return "\(cleaned).mp3"
    }


    // MARK: - Default Title

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


// MARK: - Notifications

extension Notification.Name {

    static let echoFetchCompleted =
        Notification.Name(
            "EchoFetchCompleted"
        )
}
