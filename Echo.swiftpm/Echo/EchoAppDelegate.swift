import UIKit
import Intents


// ============================================================
// MARK: - Echo App Delegate
// ============================================================

final class EchoAppDelegate:
    NSObject,
    UIApplicationDelegate {


    // ========================================================
    // MARK: - Background Downloads
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
    // MARK: - Siri Intent Routing
    // ========================================================

    func application(
        _ application: UIApplication,
        handlerFor intent: INIntent
    ) -> Any? {

        if intent is INPlayMediaIntent {

            print(
                "Siri stuurde INPlayMediaIntent naar Echo"
            )


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
    // MARK: - Resolve media items
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


            // =================================================
            // Already resolved identifier
            // =================================================

            if
                let item =
                    intent.mediaItems?.first,

                let identifier =
                    item.identifier,

                let uuid =
                    UUID(
                        uuidString:
                            identifier
                    ) {


                if let song =
                    library.songs
                        .first(
                            where: {
                                $0.id ==
                                    uuid
                            }
                        ) {

                    completion(
                        [
                            .success(
                                with:
                                    makeSongMediaItem(
                                        song
                                    )
                            )
                        ]
                    )


                    return
                }


                if let playlist =
                    library.playlists
                        .first(
                            where: {
                                $0.id ==
                                    uuid
                            }
                        ) {

                    completion(
                        [
                            .success(
                                with:
                                    makePlaylistMediaItem(
                                        playlist
                                    )
                            )
                        ]
                    )


                    return
                }
            }


            // =================================================
            // Siri media search
            // =================================================

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


            print(
                "Siri media search:",
                requestedName,
                requestedArtist,
                requestedAlbum
            )


            // =================================================
            // Playlist search
            // =================================================

            if search.mediaType ==
                .playlist {

                let playlists =
                    library.playlists
                        .filter {
                            playlist in


                            let name =
                                normalize(
                                    playlist.name
                                )


                            if requestedName.isEmpty {
                                return true
                            }


                            return
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


                guard !playlists.isEmpty
                else {

                    completion(
                        [
                            .unsupported()
                        ]
                    )


                    return
                }


                let items =
                    playlists
                        .prefix(
                            5
                        )
                        .map {
                            makePlaylistMediaItem(
                                $0
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


            // =================================================
            // Song search
            // =================================================

            let results =
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


            guard !results.isEmpty
            else {

                completion(
                    [
                        .unsupported()
                    ]
                )


                return
            }


            if results.count ==
                1 {

                completion(
                    [
                        .success(
                            with:
                                makeSongMediaItem(
                                    results[0]
                                        .song
                                )
                        )
                    ]
                )


                return
            }


            // Pick a clearly better result automatically.

            if
                results[0].score
                >
                results[1].score
                +
                100 {

                completion(
                    [
                        .success(
                            with:
                                makeSongMediaItem(
                                    results[0]
                                        .song
                                )
                        )
                    ]
                )


                return
            }


            let items =
                results
                    .prefix(
                        5
                    )
                    .map {
                        makeSongMediaItem(
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

        completion(
            INPlayMediaIntentResponse(
                code:
                    .ready,

                userActivity:
                    nil
            )
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


            print(
                "Echo behandelt Siri PlayMedia intent"
            )


            // =================================================
            // Resolved media item
            // =================================================

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


                // =============================================
                // Playlist
                // =============================================

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

                        audio.allSongs =
                            library.songs


                        audio.play(
                            song:
                                first,

                            url:
                                url,

                            queue:
                                songs
                        )


                        applyOptions(
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


                // =============================================
                // Song
                // =============================================

                if
                    let song =
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


                    applyOptions(
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


            // =================================================
            // Direct search fallback
            // =================================================

            if let search =
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


                let requestedAlbum =
                    normalize(
                        search.albumName ??
                        ""
                    )


                // =============================================
                // Playlist
                // =============================================

                if search.mediaType ==
                    .playlist {

                    let playlist =
                        library.playlists
                            .first {
                                playlist in


                                let name =
                                    normalize(
                                        playlist.name
                                    )


                                if requestedName.isEmpty {
                                    return false
                                }


                                return
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


                    if let playlist {

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

                            audio.allSongs =
                                library.songs


                            audio.play(
                                song:
                                    first,

                                url:
                                    url,

                                queue:
                                    songs
                            )


                            applyOptions(
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


                // =============================================
                // Song
                // =============================================

                let best =
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
                        .first


                if
                    let best,

                    let url =
                        library.getURL(
                            for:
                                best.song
                        ) {

                    audio.allSongs =
                        library.songs


                    audio.play(
                        song:
                            best.song,

                        url:
                            url,

                        queue:
                            library.songs
                    )


                    applyOptions(
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
    // MARK: - Playback Options
    // ========================================================

    @MainActor
    private func applyOptions(
        intent: INPlayMediaIntent,
        audio: AudioPlayerManager
    ) {

        if let shuffled =
            intent.playShuffled {

            audio.setShuffle(
                shuffled
            )
        }


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
    // MARK: - Song Media Item
    // ========================================================

    private func makeSongMediaItem(
        _ song: Song
    ) -> INMediaItem {

        var artwork:
            INImage? =
            nil


        if let data =
            song.coverData {

            artwork =
                INImage(
                    imageData:
                        data
                )
        }


        return INMediaItem(
            identifier:
                song.id.uuidString,

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
    // MARK: - Playlist Media Item
    // ========================================================

    private func makePlaylistMediaItem(
        _ playlist: Playlist
    ) -> INMediaItem {

        var artwork:
            INImage? =
            nil


        if let data =
            playlist.imageData {

            artwork =
                INImage(
                    imageData:
                        data
                )
        }


        return INMediaItem(
            identifier:
                playlist.id.uuidString,

            title:
                playlist.name,

            type:
                .playlist,

            artwork:
                artwork
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


        var value =
            0


        // ====================================================
        // Title
        // ====================================================

        if !requestedName.isEmpty {

            if title ==
                requestedName {

                value +=
                    1000


            } else if title.hasPrefix(
                requestedName
            ) {

                value +=
                    900


            } else if title.contains(
                requestedName
            ) {

                value +=
                    800


            } else if requestedName.contains(
                title
            ) {

                value +=
                    750
            }
        }


        // ====================================================
        // Artist
        // ====================================================

        if !requestedArtist.isEmpty {

            if artist ==
                requestedArtist {

                value +=
                    500


            } else if artist.contains(
                requestedArtist
            ) {

                value +=
                    350


            } else if requestedArtist.contains(
                artist
            ) {

                value +=
                    300
            }
        }


        // ====================================================
        // Album
        // ====================================================

        if !requestedAlbum.isEmpty {

            if album ==
                requestedAlbum {

                value +=
                    250


            } else if album.contains(
                requestedAlbum
            ) {

                value +=
                    150
            }
        }


        return value
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
