import UIKit
import Intents


// ============================================================
// MARK: - App Delegate
// ============================================================

final class EchoAppDelegate:
    NSObject,
    UIApplicationDelegate {


    // ========================================================
    // MARK: - Background yt-dlp downloads
    // ========================================================

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler:
            @escaping
            () -> Void
    ) {

        FetchDownloadEngine.shared
            .handleBackgroundEvents(
                identifier:
                    identifier,

                completionHandler:
                    completionHandler
            )
    }


    // ========================================================
    // MARK: - SiriKit Intent Handler
    // ========================================================

    func application(
        _ application: UIApplication,
        handlerFor intent: INIntent
    ) -> Any? {

        if intent is INPlayMediaIntent {

            return EchoMediaIntentHandler()
        }


        return nil
    }
}


// ============================================================
// MARK: - Echo Media Intent Handler
// ============================================================

final class EchoMediaIntentHandler:
    NSObject,
    INPlayMediaIntentHandling {


    // ========================================================
    // MARK: - Resolve Media
    // ========================================================

    func resolveMediaItems(
        for intent: INPlayMediaIntent,
        with completion:
            @escaping (
                [INPlayMediaMediaItemResolutionResult]
            ) -> Void
    ) {

        Task {
            @MainActor in


            let library =
                MusicLibraryManager.shared


            // ------------------------------------------------
            // Siri can already provide a resolved media ID.
            // ------------------------------------------------

            if
                let requestedItem =
                    intent.mediaItems?.first,

                let identifier =
                    requestedItem.identifier,

                let uuid =
                    UUID(
                        uuidString:
                            identifier
                    ),

                let song =
                    library.songs
                        .first(
                            where: {

                                $0.id ==
                                    uuid
                            }
                        ) {

                let mediaItem =
                    makeMediaItem(
                        from:
                            song
                    )


                completion(
                    [
                        .success(
                            with:
                                mediaItem
                        )
                    ]
                )


                return
            }


            // ------------------------------------------------
            // Search request from Siri
            // ------------------------------------------------

            guard let search =
                intent.mediaSearch

            else {

                completion(
                    [
                        .needsValue()
                    ]
                )


                return
            }


            let requestedName =
                normalize(
                    search.mediaName ??
                    ""
                )


            let requestedArtist =
                normalize(
                    search.artistName ??
                    ""
                )


            let requestedAlbum =
                normalize(
                    search.albumName ??
                    ""
                )


            // ------------------------------------------------
            // Playlist
            // ------------------------------------------------

            if search.mediaType ==
                .playlist {

                let matchingPlaylists =
                    library.playlists
                        .filter {
                            playlist in


                            let name =
                                normalize(
                                    playlist.name
                                )


                            return
                                requestedName.isEmpty
                                ||
                                name ==
                                    requestedName
                                ||
                                name.contains(
                                    requestedName
                                )
                                ||
                                requestedName.contains(
                                    name
                                )
                        }


                if matchingPlaylists.isEmpty {

                    completion(
                        [
                            .unsupported()
                        ]
                    )


                    return
                }


                let items =
                    matchingPlaylists
                        .prefix(
                            5
                        )
                        .map {
                            playlist in


                            INMediaItem(
                                identifier:
                                    playlist.id
                                        .uuidString,

                                title:
                                    playlist.name,

                                type:
                                    .playlist,

                                artwork:
                                    nil
                            )
                        }


                if items.count ==
                    1 {

                    completion(
                        [
                            .success(
                                with:
                                    items[0]
                            )
                        ]
                    )


                } else {

                    completion(
                        [
                            .disambiguation(
                                with:
                                    Array(
                                        items
                                    )
                            )
                        ]
                    )
                }


                return
            }


            // ------------------------------------------------
            // Song search
            // ------------------------------------------------

            let scoredSongs =
                library.songs
                    .map {
                        song in


                        (
                            song:
                                song,

                            score:
                                score(
                                    song:
                                        song,

                                    requestedName:
                                        requestedName,

                                    requestedArtist:
                                        requestedArtist,

                                    requestedAlbum:
                                        requestedAlbum
                                )
                        )
                    }
                    .filter {

                        $0.score >
                            0
                    }
                    .sorted {

                        $0.score >
                            $1.score
                    }


            guard !scoredSongs
                .isEmpty

            else {

                completion(
                    [
                        .unsupported()
                    ]
                )


                return
            }


            // ------------------------------------------------
            // If one result is clearly best, choose it.
            // ------------------------------------------------

            if
                scoredSongs.count ==
                    1
                ||
                (
                    scoredSongs.count >
                        1
                    &&
                    scoredSongs[0].score
                    >
                    scoredSongs[1].score
                    +
                    100
                ) {

                let item =
                    makeMediaItem(
                        from:
                            scoredSongs[0]
                                .song
                    )


                completion(
                    [
                        .success(
                            with:
                                item
                        )
                    ]
                )


                return
            }


            // ------------------------------------------------
            // Siri asks which one when multiple songs match.
            // ------------------------------------------------

            let items =
                scoredSongs
                    .prefix(
                        5
                    )
                    .map {

                        makeMediaItem(
                            from:
                                $0.song
                        )
                    }


            completion(
                [
                    .disambiguation(
                        with:
                            Array(
                                items
                            )
                    )
                ]
            )
        }
    }


    // ========================================================
    // MARK: - Confirm
    // ========================================================

    func confirm(
        intent: INPlayMediaIntent,
        completion:
            @escaping (
                INPlayMediaIntentResponse
            ) -> Void
    ) {

        let response =
            INPlayMediaIntentResponse(
                code:
                    .ready,

                userActivity:
                    nil
            )


        completion(
            response
        )
    }


    // ========================================================
    // MARK: - Handle
    // ========================================================

    func handle(
        intent: INPlayMediaIntent,
        completion:
            @escaping (
                INPlayMediaIntentResponse
            ) -> Void
    ) {

        Task {
            @MainActor in


            let library =
                MusicLibraryManager.shared


            let audio =
                AudioPlayerManager.shared


            // ------------------------------------------------
            // First try resolved mediaItems.
            // ------------------------------------------------

            if
                let mediaItem =
                    intent.mediaItems?
                        .first,

                let identifier =
                    mediaItem.identifier,

                let uuid =
                    UUID(
                        uuidString:
                            identifier
                    ) {

                // ============================================
                // Playlist
                // ============================================

                if mediaItem.type ==
                    .playlist {

                    if let playlist =
                        library.playlists
                            .first(
                                where: {

                                    $0.id ==
                                        uuid
                                }
                            ) {

                        let songs =
                            playlist.songIDs
                                .compactMap {
                                    songID in


                                    library.songs
                                        .first(
                                            where: {

                                                $0.id ==
                                                    songID
                                            }
                                        )
                                }


                        if let firstSong =
                            songs.first,

                           let url =
                            library.getURL(
                                for:
                                    firstSong
                            ) {

                            audio.allSongs =
                                library.songs


                            audio.play(
                                song:
                                    firstSong,

                                url:
                                    url,

                                queue:
                                    songs
                            )


                            applyPlaybackOptions(
                                intent:
                                    intent,

                                audio:
                                    audio
                            )


                            completion(
                                INPlayMediaIntentResponse(
                                    code:
                                        .success,

                                    userActivity:
                                        nil
                                )
                            )


                            return
                        }
                    }
                }


                // ============================================
                // Song
                // ============================================

                if let song =
                    library.songs
                        .first(
                            where: {

                                $0.id ==
                                    uuid
                            }
                        ),

                   let url =
                    library.getURL(
                        for:
                            song
                    ) {

                    audio.allSongs =
                        library.songs


                    audio.play(
                        song:
                            song,

                        url:
                            url,

                        queue:
                            library.songs
                    )


                    applyPlaybackOptions(
                        intent:
                            intent,

                        audio:
                            audio
                    )


                    completion(
                        INPlayMediaIntentResponse(
                            code:
                                .success,

                            userActivity:
                                nil
                        )
                    )


                    return
                }
            }


            // ------------------------------------------------
            // Fallback:
            // Search directly if Siri didn't resolve first.
            // ------------------------------------------------

            if
                let search =
                    intent.mediaSearch {

                let requestedName =
                    normalize(
                        search.mediaName ??
                        ""
                    )


                let requestedArtist =
                    normalize(
                        search.artistName ??
                        ""
                    )


                // ============================================
                // Playlist fallback
                // ============================================

                if search.mediaType ==
                    .playlist {

                    if let playlist =
                        library.playlists
                            .first(
                                where: {

                                    normalize(
                                        $0.name
                                    )
                                    .contains(
                                        requestedName
                                    )
                                }
                            ) {

                        let songs =
                            playlist.songIDs
                                .compactMap {
                                    id in


                                    library.songs
                                        .first(
                                            where: {

                                                $0.id ==
                                                    id
                                            }
                                        )
                                }


                        if
                            let first =
                                songs.first,

                            let url =
                                library.getURL(
                                    for:
                                        first
                                ) {

                            audio.play(
                                song:
                                    first,

                                url:
                                    url,

                                queue:
                                    songs
                            )


                            applyPlaybackOptions(
                                intent:
                                    intent,

                                audio:
                                    audio
                            )


                            completion(
                                INPlayMediaIntentResponse(
                                    code:
                                        .success,

                                    userActivity:
                                        nil
                                )
                            )


                            return
                        }
                    }
                }


                // ============================================
                // Song fallback
                // ============================================

                let song =
                    library.songs
                        .map {
                            song in


                            (
                                song:
                                    song,

                                score:
                                    score(
                                        song:
                                            song,

                                        requestedName:
                                            requestedName,

                                        requestedArtist:
                                            requestedArtist,

                                        requestedAlbum:
                                            ""
                                    )
                            )
                        }
                        .filter {

                            $0.score >
                                0
                        }
                        .sorted {

                            $0.score >
                                $1.score
                        }
                        .first?
                        .song


                if
                    let song,

                    let url =
                        library.getURL(
                            for:
                                song
                        ) {

                    audio.allSongs =
                        library.songs


                    audio.play(
                        song:
                            song,

                        url:
                            url,

                        queue:
                            library.songs
                    )


                    applyPlaybackOptions(
                        intent:
                            intent,

                        audio:
                            audio
                    )


                    completion(
                        INPlayMediaIntentResponse(
                            code:
                                .success,

                            userActivity:
                                nil
                        )
                    )


                    return
                }
            }


            // ------------------------------------------------
            // Nothing found
            // ------------------------------------------------

            completion(
                INPlayMediaIntentResponse(
                    code:
                        .failure,

                    userActivity:
                        nil
                )
            )
        }
    }


    // ========================================================
    // MARK: - Playback options
    // ========================================================

    @MainActor
    private func applyPlaybackOptions(
        intent: INPlayMediaIntent,
        audio: AudioPlayerManager
    ) {

        // ----------------------------------------------------
        // Shuffle
        // ----------------------------------------------------

        if let shuffled =
            intent.playShuffled {

            audio.setShuffle(
                shuffled
            )
        }


        // ----------------------------------------------------
        // Repeat
        // ----------------------------------------------------

        switch intent.playbackRepeatMode {

        case .all:

            audio.setRepeatMode(
                .all
            )


        case .one:

            audio.setRepeatMode(
                .one
            )


        case .none:

            audio.setRepeatMode(
                .off
            )


        default:

            break
        }
    }


    // ========================================================
    // MARK: - Convert Song -> INMediaItem
    // ========================================================

    @MainActor
    private func makeMediaItem(
        from song: Song
    ) -> INMediaItem {

        var artwork:
            INImage? =
            nil


        if let coverData =
            song.coverData {

            artwork =
                INImage(
                    imageData:
                        coverData
                )
        }


        return INMediaItem(
            identifier:
                song.id
                    .uuidString,

            title:
                song.title,

            type:
                .song,

            artwork:
                artwork,

            artist:
                song.artist
        )
    }


    // ========================================================
    // MARK: - Matching
    // ========================================================

    private func score(
        song: Song,
        requestedName: String,
        requestedArtist: String,
        requestedAlbum: String
    ) -> Int {

        let title =
            normalize(
                song.title
            )


        let artist =
            normalize(
                song.artist
            )


        let album =
            normalize(
                song.album ??
                ""
            )


        var score =
            0


        // ----------------------------------------------------
        // Title
        // ----------------------------------------------------

        if !requestedName
            .isEmpty {

            if title ==
                requestedName {

                score +=
                    1000


            } else if title
                .hasPrefix(
                    requestedName
                ) {

                score +=
                    850


            } else if title
                .contains(
                    requestedName
                ) {

                score +=
                    750


            } else if requestedName
                .contains(
                    title
                ) {

                score +=
                    700
            }
        }


        // ----------------------------------------------------
        // Artist
        // ----------------------------------------------------

        if !requestedArtist
            .isEmpty {

            if artist ==
                requestedArtist {

                score +=
                    500


            } else if artist
                .contains(
                    requestedArtist
                ) {

                score +=
                    350
            }
        }


        // ----------------------------------------------------
        // Album
        // ----------------------------------------------------

        if !requestedAlbum
            .isEmpty {

            if album ==
                requestedAlbum {

                score +=
                    250


            } else if album
                .contains(
                    requestedAlbum
                ) {

                score +=
                    150
            }
        }


        return score
    }


    private func normalize(
        _ string: String
    ) -> String {

        string
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive
                ],

                locale:
                    .current
            )
            .lowercased()
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
    }
}
