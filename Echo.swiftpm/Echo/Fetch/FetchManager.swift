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


    // MARK: - Raw Spotify URL

    func addSpotifyURL(
        _ string: String
    ) {

        guard
            let reference =
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


    // MARK: - Authorized YouTube Match

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

            // =====================================
            // APIFY
            // =====================================

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


                guard let firstResult =
                    results.first
                else {

                    print(
                        "Geen YouTube-resultaat voor:",
                        track.name
                    )


                    return
                }


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
                            firstResult.videoURL,

                        permissionConfirmed:
                            true
                    )


                items.append(
                    item
                )


            // =====================================
            // YT-DLP
            // =====================================

            case .spotify:

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
                            nil,

                        permissionConfirmed:
                            true
                    )


                items.append(
                    item
                )
            }


        } catch {

            print(
                "Playlist track voorbereiden mislukt:",
                track.name,
                error
            )
        }
    }


    // MARK: - Add Track

    func add(
        _ track: SpotifyTrack
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
                    track.artworkURL
            )


        items.append(
            item
        )


        startIfNeeded()
    }


    // MARK: - Add Playlist

    func add(
        _ playlist: SpotifyPlaylist
    ) {

        let item =
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


        items.append(
            item
        )


        startIfNeeded()
    }


    // MARK: - Authorized Spotify Track

    func addAuthorizedSpotifyTrack(
        _ track: SpotifyTrack
    ) {

        print(
            "Adding track to yt-dlp queue:",
            track.name
        )


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
                    nil,

                permissionConfirmed:
                    true
            )


        items.append(
            item
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


        guard
            items.contains(
                where: {

                    if case .queued =
                        $0.status {

                        return true
                    }


                    return false
                }
            )
        else {

            return
        }


        running =
            true


        Task {

            await processQueue()


            running =
                false


            if
                items.contains(
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

        while true {

            guard
                let nextItem =
                    items.first(
                        where: {

                            if case .queued =
                                $0.status {

                                return true
                            }


                            return false
                        }
                    )
            else {

                break
            }


            await process(
                nextItem
            )
        }
    }


    // MARK: - Process

    private func process(
        _ item: FetchItem
    ) async {

        item.status =
            .preparing


        UserDefaults.standard.set(
            "FETCH 1 - preparing",
            forKey: "fetchLastStage"
        )


        do {

            let method =
                ApifySettings.shared
                    .downloadMethod


            let downloadResult:
                FetchAudioResult


            print(
                "===================================="
            )

            print(
                "FETCH:",
                item.title
            )

            print(
                "Artist:",
                item.artist
            )

            print(
                "Album:",
                item.album ?? "nil"
            )

            print(
                "Method:",
                method.title
            )

            print(
                "===================================="
            )


            // =====================================
            // Resolve source
            // =====================================

            switch method {

            // =====================================
            // APIFY
            // =====================================

            case .youtube:

                guard let youtubeURL =
                    item.youtubeURL
                else {

                    throw
                        ApifyDownloadError
                            .invalidURL
                }


                let result =
                    try await
                    ApifyAudioSource.shared
                        .resolveMP3(

                            youtubeURL:
                                youtubeURL,

                            permissionConfirmed:
                                item
                                    .permissionConfirmed
                        )


                downloadResult =
                    FetchAudioResult(

                        downloadURL:
                            result.downloadURL,

                        suggestedFileName:
                            makeTemporaryApifyName(
                                item: item
                            )
                    )


            // =====================================
            // EMBEDDED YT-DLP
            // =====================================

            case .spotify:

                downloadResult =
                    try await
                    YTDLPAudioSource.shared
                        .resolve(
                            item: item
                        )
            }


            UserDefaults.standard.set(
                "FETCH 2 - source resolved",
                forKey: "fetchLastStage"
            )


            // =====================================
            // Download
            // =====================================

            item.status =
                .downloading(
                    0
                )


            let downloadedFile =
                try await
                FetchDownloadEngine.shared
                    .download(

                        item:
                            item,

                        result:
                            downloadResult

                    ) {

                        progress in


                        item.status =
                            .downloading(
                                progress
                            )
                    }


            UserDefaults.standard.set(
                "FETCH 3 - source downloaded",
                forKey: "fetchLastStage"
            )


            print(
                "Source downloaded:",
                downloadedFile.path
            )


            // =====================================
            // FINAL MP3
            // =====================================

            item.status =
                .processing


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
                    )


            UserDefaults.standard.set(
                "FETCH 4 - MP3 generated",
                forKey: "fetchLastStage"
            )


            let finalMP3URL =
                processedAudio
                    .fileURL


            print(
                "Final MP3:",
                finalMP3URL.path
            )


            // =====================================
            // Remove temporary source
            // =====================================

            if downloadedFile !=
                finalMP3URL {

                do {

                    try FileManager.default
                        .removeItem(
                            at:
                                downloadedFile
                        )

                } catch {

                    print(
                        "Could not remove source:",
                        error
                    )
                }
            }


            UserDefaults.standard.set(
                "FETCH 5 - source cleaned",
                forKey: "fetchLastStage"
            )


            // =====================================
            // DIRECTLY ADD TO ECHO LIBRARY
            //
            // Do NOT rescan AVAsset metadata.
            //
            // Spotify metadata is authoritative.
            // =====================================

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

            NotificationCenter.default.post(
    name: .echoFetchCompleted,
    object: nil
)
            

            UserDefaults.standard.set(
                "FETCH 6 - library updated",
                forKey: "fetchLastStage"
            )


            // =====================================
            // Complete
            // =====================================

            item.status =
                .completed


            UserDefaults.standard.set(
                "FETCH 7 - COMPLETE",
                forKey: "fetchLastStage"
            )


            print(
                "===================================="
            )

            print(
                "MP3 FETCH COMPLETE"
            )

            print(
                finalMP3URL.lastPathComponent
            )

            print(
                "Metadata:"
            )

            print(
                "Title:",
                processedAudio.title
            )

            print(
                "Artist:",
                processedAudio.artist
            )

            print(
                "Album:",
                processedAudio.album
                ?? "nil"
            )

            print(
                "Artwork:",
                processedAudio.artworkData?
                    .count
                ?? 0,
                "bytes"
            )

            print(
                "===================================="
            )


        } catch {

            item.status =
                .failed(
                    error.localizedDescription
                )


            UserDefaults.standard.set(
                "FETCH FAILED - \(error.localizedDescription)",
                forKey: "fetchLastStage"
            )


            print(
                "===================================="
            )

            print(
                "FETCH FAILED"
            )

            print(
                item.title
            )

            print(
                error
            )

            print(
                "===================================="
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
                    separator: ""
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
