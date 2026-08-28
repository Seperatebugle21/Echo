import Foundation


@MainActor
@Observable
final class FetchManager {

    static let shared =
        FetchManager()


    private(set) var items:
        [FetchItem] = []


    private var running =
        false


    private init() {}


    // MARK: - Spotify URL

    func addSpotifyURL(
        _ string: String
    ) {

        guard let reference =
            SpotifyURLParser.parse(
                string
            )
        else {
            return
        }


        let item =
            FetchItem(
                spotifyURL:
                    reference.url,
                title:
                    defaultTitle(
                        for:
                            reference.type
                    ),
                artist:
                    "Spotify"
            )


        items.append(
            item
        )


        startIfNeeded()
    }


    // MARK: - Authorized Match

    func addAuthorizedMatch(
        track: SpotifyTrack,
        youtubeResult: YouTubeSearchResult
    ) {

        let item =
            FetchItem(
                spotifyURL:
                    track.spotifyURL,
                title:
                    track.name,
                artist:
                    track.artist,
                album:
                    track.album,
                artworkURL:
                    track.artworkURL,
                youtubeURL:
                    youtubeResult.videoURL,
                permissionConfirmed:
                    true
            )


        items.append(
            item
        )


        startIfNeeded()
    }


    // MARK: - Playlist

    func preparePlaylist(
        _ playlist: SpotifyPlaylist
    ) async throws {

        let tracks =
            try await
            SpotifyAPI.shared
                .getPlaylistTracks(
                    playlistID:
                        playlist.id
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

            switch
                ApifySettings.shared
                    .downloadMethod {

            case .youtube:

                let results =
                    try await
                    YouTubeAPI.shared
                        .search(
                            title:
                                track.name,
                            artist:
                                track.artist,
                            maxResults:
                                1
                        )


                guard let result =
                    results.first
                else {
                    return
                }


                items.append(
                    FetchItem(
                        spotifyURL:
                            track.spotifyURL,
                        title:
                            track.name,
                        artist:
                            track.artist,
                        album:
                            track.album,
                        artworkURL:
                            track.artworkURL,
                        youtubeURL:
                            result.videoURL,
                        permissionConfirmed:
                            true
                    )
                )


            case .spotify:

                items.append(
                    FetchItem(
                        spotifyURL:
                            track.spotifyURL,
                        title:
                            track.name,
                        artist:
                            track.artist,
                        album:
                            track.album,
                        artworkURL:
                            track.artworkURL,
                        youtubeURL:
                            nil,
                        permissionConfirmed:
                            true
                    )
                )
            }

        } catch {

            print(
                "Playlist track failed:",
                track.name,
                error
            )
        }
    }


    // MARK: - Add Track

    func add(
        _ track: SpotifyTrack
    ) {

        items.append(
            FetchItem(
                spotifyURL:
                    track.spotifyURL,
                title:
                    track.name,
                artist:
                    track.artist,
                album:
                    track.album,
                artworkURL:
                    track.artworkURL
            )
        )


        startIfNeeded()
    }


    // MARK: - Add Playlist

    func add(
        _ playlist: SpotifyPlaylist
    ) {

        items.append(
            FetchItem(
                spotifyURL:
                    playlist.spotifyURL,
                title:
                    playlist.name,
                artist:
                    "\(playlist.trackCount) songs",
                artworkURL:
                    playlist.artworkURL
            )
        )


        startIfNeeded()
    }


    // MARK: - Authorized yt-dlp Track

    func addAuthorizedSpotifyTrack(
        _ track: SpotifyTrack
    ) {

        items.append(
            FetchItem(
                spotifyURL:
                    track.spotifyURL,
                title:
                    track.name,
                artist:
                    track.artist,
                album:
                    track.album,
                artworkURL:
                    track.artworkURL,
                youtubeURL:
                    nil,
                permissionConfirmed:
                    true
            )
        )


        startIfNeeded()
    }


    // MARK: - Remove

    func remove(
        _ item: FetchItem
    ) {

        items.removeAll {
            $0.id ==
                item.id
        }
    }


    func clearCompleted() {

        items.removeAll {

            if case .completed =
                $0.status {

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


        guard items.contains(
            where: {

                if case .queued =
                    $0.status {

                    return true
                }

                return false
            }
        ) else {
            return
        }


        running =
            true


        Task {

            await processQueue()


            running =
                false


            if items.contains(
                where: {

                    if case .queued =
                        $0.status {

                        return true
                    }

                    return false
                }
            ) {

                startIfNeeded()
            }
        }
    }


    private func processQueue()
        async {

        while let next =
            items.first(
                where: {

                    if case .queued =
                        $0.status {

                        return true
                    }

                    return false
                }
            ) {

            await process(
                next
            )
        }
    }


    // MARK: - Process

    private func process(
        _ item: FetchItem
    ) async {

        // =========================================
        // 0 - 10%
        // Resolve source
        // =========================================

        item.status =
            .preparing(
                0.02
            )


        do {

            let method =
                ApifySettings.shared
                    .downloadMethod


            let downloadResult:
                FetchAudioResult


            item.status =
                .preparing(
                    0.05
                )


            switch method {

            // =====================================
            // Existing Apify method
            // =====================================

            case .youtube:

                guard let youtubeURL =
                    item.youtubeURL
                else {

                    throw
                        ApifyDownloadError
                            .invalidURL
                }


                item.status =
                    .preparing(
                        0.07
                    )


                let result =
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
                            result.downloadURL,
                        suggestedFileName:
                            makeTemporaryApifyName(
                                item:
                                    item
                            )
                    )


            // =====================================
            // yt-dlp
            // =====================================

            case .spotify:

                item.status =
                    .preparing(
                        0.07
                    )


                downloadResult =
                    try await
                    YTDLPAudioSource.shared
                        .resolve(
                            item:
                                item
                        )
            }


            item.status =
                .preparing(
                    0.10
                )


            // =====================================
            // 10 - 60%
            // Actual HTTP download
            // =====================================

            let downloadedFile =
                try await
                FetchDownloadEngine.shared
                    .download(
                        item:
                            item,
                        result:
                            downloadResult
                    ) {
                        localProgress in


                        let overall =
                            0.10
                            +
                            (
                                localProgress
                                *
                                0.50
                            )


                        item.status =
                            .downloading(
                                overall
                            )
                    }


            item.status =
                .processing(
                    0.60
                )


            // =====================================
            // 60 - 95%
            // Actual MP3 encode
            // =====================================

            let processedAudio =
                try await
                FetchAudioProcessor.shared
                    .process(
                        sourceURL:
                            downloadedFile,
                        item:
                            item,
                        quality:
                            FetchSettings.shared
                                .quality
                    ) {
                        localProgress in


                        let overall =
                            0.60
                            +
                            (
                                localProgress
                                *
                                0.35
                            )


                        item.status =
                            .processing(
                                overall
                            )
                    }


            // =====================================
            // Remove temporary source
            // =====================================

            if downloadedFile !=
                processedAudio.fileURL {

                try? FileManager.default
                    .removeItem(
                        at:
                            downloadedFile
                    )
            }


            // =====================================
            // 95 - 100%
            // Library + metadata
            // =====================================

            item.status =
                .processing(
                    0.96
                )


            MusicLibraryManager.shared
                .addProcessedFetch(
                    fileURL:
                        processedAudio.fileURL,
                    title:
                        processedAudio.title,
                    artist:
                        processedAudio.artist,
                    album:
                        processedAudio.album,
                    coverData:
                        processedAudio.artworkData
                )


            item.status =
                .processing(
                    0.99
                )


            NotificationCenter.default
                .post(
                    name:
                        .echoFetchCompleted,
                    object:
                        nil
                )


            item.status =
                .completed


            print(
                "FETCH COMPLETE:",
                processedAudio.title
            )


        } catch {

            item.status =
                .failed(
                    error.localizedDescription
                )


            print(
                "FETCH FAILED:",
                item.title,
                error
            )
        }
    }


    // MARK: - Apify temp filename

    private func makeTemporaryApifyName(
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
                    separator:
                        ""
                )


        return
            "\(cleaned)-apify-source.mp3"
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
