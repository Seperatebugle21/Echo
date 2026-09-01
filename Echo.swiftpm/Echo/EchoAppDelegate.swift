import UIKit
import Intents


// ============================================================
// MARK: - App Delegate
// ============================================================

final class EchoAppDelegate:
    NSObject,
    UIApplicationDelegate {


    // ========================================================
    // MARK: - Launch
    // ========================================================

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        configureSiriMediaContext()

        return true
    }


    // ========================================================
    // MARK: - Siri Media Context
    // ========================================================

    private func configureSiriMediaContext() {

        Task {
            @MainActor in


            let context =
                INMediaUserContext()


            context.numberOfLibraryItems =
                MusicLibraryManager.shared
                    .songs
                    .count


            // Echo itself doesn't require a paid
            // music subscription.

            context.subscriptionStatus =
                .notSubscribed


            context.becomeCurrent()


            print(
                "Echo Siri media context actief:",
                MusicLibraryManager.shared
                    .songs
                    .count,
                "songs"
            )
        }
    }


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
    // MARK: - Siri Handler
    // ========================================================

    func application(
        _ application: UIApplication,
        handlerFor intent: INIntent
    ) -> Any? {

        if intent is
            INPlayMediaIntent {

            print(
                "Siri -> Echo INPlayMediaIntent"
            )


            return EchoMediaIntentHandler()
        }


        return nil
    }
}


// ============================================================
// MARK: - Media Handler
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
            // Already has Echo identifier
            // ------------------------------------------------

            if
                let existing =
                    intent.mediaItems?
                        .first,

                let identifier =
                    existing.identifier,

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
                                    makeSongItem(
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
                                    makePlaylistItem(
                                        playlist
                                    )
                            )
                        ]
                    )


                    return
                }
            }


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


            let name =
                search.mediaName ??
                ""


            let artist =
                search.artistName ??
                ""


            let album =
                search.albumName ??
                ""


            print(
                "Siri zoekt:",
                name,
                "| artist:",
                artist,
                "| album:",
                album,
                "| type:",
                search.mediaType.rawValue
            )


            // =================================================
            // Playlist
            // =================================================

            if search.mediaType ==
                .playlist {

                resolvePlaylist(
                    query:
                        name,

                    library:
                        library,

                    completion:
                        completion
                )


                return
            }


            // =================================================
            // Songs
            // =================================================

            let songResults =
                scoredSongs(
                    library:
                        library,

                    name:
                        name,

                    artist:
                        artist,

                    album:
                        album
                )


            if let top =
                songResults.first {

                // Strong match

                if
                    songResults.count ==
                        1
                    ||
                    top.score >=
                        850
                    ||
                    (
                        songResults.count >
                            1
                        &&
                        top.score -
                        songResults[1].score
                        >=
                        120
                    ) {

                    completion(
                        [
                            .success(
                                with:
                                    makeSongItem(
                                        top.song
                                    )
                            )
                        ]
                    )


                    return
                }


                let alternatives =
                    Array(
                        songResults
                            .prefix(
                                5
                            )
                            .map {

                                makeSongItem(
                                    $0.song
                                )
                            }
                    )


                completion(
                    [
                        .disambiguation(
                            with:
                                alternatives
                        )
                    ]
                )


                return
            }


            // ------------------------------------------------
            // Maybe Siri failed to classify a playlist.
            // Try playlist names as fallback.
            // ------------------------------------------------

            let playlists =
                scoredPlaylists(
                    library:
                        library,

                    query:
                        name
                )


            if let playlist =
                playlists.first,
               playlist.score >=
                650 {

                completion(
                    [
                        .success(
                            with:
                                makePlaylistItem(
                                    playlist.playlist
                                )
                        )
                    ]
                )


                return
            }


            completion(
                [
                    .unsupported()
                ]
            )
        }
    }


    // ========================================================
    // MARK: - Playlist Resolve
    // ========================================================

    @MainActor
    private func resolvePlaylist(
        query: String,
        library: MusicLibraryManager,
        completion:
            @escaping (
                [INPlayMediaMediaItemResolutionResult]
            ) -> Void
    ) {

        let results =
            scoredPlaylists(
                library:
                    library,

                query:
                    query
            )


        guard let first =
            results.first
        else {

            completion(
                [
                    .unsupported()
                ]
            )


            return
        }


        if
            results.count ==
                1
            ||
            first.score >=
                850
            ||
            (
                results.count >
                    1
                &&
                first.score -
                results[1].score
                >=
                120
            ) {

            completion(
                [
                    .success(
                        with:
                            makePlaylistItem(
                                first.playlist
                            )
                    )
                ]
            )


            return
        }


        completion(
            [
                .disambiguation(
                    with:
                        Array(
                            results
                                .prefix(
                                    5
                                )
                                .map {

                                    makePlaylistItem(
                                        $0.playlist
                                    )
                                }
                        )
                )
            ]
        )
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


            // =================================================
            // Resolved identifier
            // =================================================

            if
                let item =
                    intent.mediaItems?
                        .first,

                let identifier =
                    item.identifier,

                let uuid =
                    UUID(
                        uuidString:
                            identifier
                    ) {


                if let playlist =
                    library.playlists
                        .first(
                            where: {

                                $0.id ==
                                    uuid
                            }
                        ) {

                    if play(
                        playlist:
                            playlist,

                        library:
                            library,

                        audio:
                            audio,

                        intent:
                            intent
                    ) {

                        success(
                            completion
                        )


                        return
                    }
                }


                if let song =
                    library.songs
                        .first(
                            where: {

                                $0.id ==
                                    uuid
                            }
                        ) {

                    if play(
                        song:
                            song,

                        library:
                            library,

                        audio:
                            audio,

                        intent:
                            intent
                    ) {

                        success(
                            completion
                        )


                        return
                    }
                }
            }


            // =================================================
            // Fallback search
            // =================================================

            if let search =
                intent.mediaSearch {

                let name =
                    search.mediaName ??
                    ""


                if search.mediaType ==
                    .playlist {

                    if let result =
                        scoredPlaylists(
                            library:
                                library,

                            query:
                                name
                        )
                        .first {

                        if play(
                            playlist:
                                result.playlist,

                            library:
                                library,

                            audio:
                                audio,

                            intent:
                                intent
                        ) {

                            success(
                                completion
                            )


                            return
                        }
                    }
                }


                if let result =
                    scoredSongs(
                        library:
                            library,

                        name:
                            name,

                        artist:
                            search.artistName ??
                            "",

                        album:
                            search.albumName ??
                            ""
                    )
                    .first {

                    if play(
                        song:
                            result.song,

                        library:
                            library,

                        audio:
                            audio,

                        intent:
                            intent
                    ) {

                        success(
                            completion
                        )


                        return
                    }
                }


                // Siri may have classified playlist incorrectly.

                if let result =
                    scoredPlaylists(
                        library:
                            library,

                        query:
                            name
                    )
                    .first,
                   result.score >=
                    650 {

                    if play(
                        playlist:
                            result.playlist,

                        library:
                            library,

                        audio:
                            audio,

                        intent:
                            intent
                    ) {

                        success(
                            completion
                        )


                        return
                    }
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
    // MARK: - Song Search
    // ========================================================

    @MainActor
    private func scoredSongs(
        library: MusicLibraryManager,
        name: String,
        artist: String,
        album: String
    ) -> [
        (
            song: Song,
            score: Int
        )
    ] {

        let fullQuery =
            [
                name,
                artist
            ]
            .filter {
                !$0.isEmpty
            }
            .joined(
                separator: " "
            )


        return library.songs
            .map {
                song in


                var value =
                    EchoSiriMatcher
                        .songScore(
                            song:
                                song,

                            query:
                                fullQuery.isEmpty
                                ? name
                                : fullQuery
                        )


                if !name.isEmpty {

                    value =
                        max(
                            value,

                            EchoSiriMatcher
                                .score(
                                    candidate:
                                        song.title,

                                    query:
                                        name
                                )
                        )
                }


                if !artist.isEmpty {

                    let artistValue =
                        EchoSiriMatcher
                            .score(
                                candidate:
                                    song.artist,

                                query:
                                    artist
                            )


                    if artistValue >=
                        600 {

                        value +=
                            250
                    }
                }


                if
                    !album.isEmpty,
                    let songAlbum =
                        song.album {

                    let albumValue =
                        EchoSiriMatcher
                            .score(
                                candidate:
                                    songAlbum,

                                query:
                                    album
                            )


                    if albumValue >=
                        600 {

                        value +=
                            150
                    }
                }


                return (
                    song:
                        song,

                    score:
                        value
                )
            }
            .filter {

                $0.score >=
                    500
            }
            .sorted {

                $0.score >
                    $1.score
            }
    }


    // ========================================================
    // MARK: - Playlist Search
    // ========================================================

    @MainActor
    private func scoredPlaylists(
        library: MusicLibraryManager,
        query: String
    ) -> [
        (
            playlist: Playlist,
            score: Int
        )
    ] {

        library.playlists
            .map {
                playlist in


                (
                    playlist:
                        playlist,

                    score:
                        EchoSiriMatcher
                            .score(
                                candidate:
                                    playlist.name,

                                query:
                                    query
                            )
                )
            }
            .filter {

                $0.score >=
                    500
            }
            .sorted {

                $0.score >
                    $1.score
            }
    }


    // ========================================================
    // MARK: - Play Song
    // ========================================================

    @MainActor
    private func play(
        song: Song,
        library: MusicLibraryManager,
        audio: AudioPlayerManager,
        intent: INPlayMediaIntent
    ) -> Bool {

        guard
            let url =
                library.getURL(
                    for:
                        song
                ),

            FileManager.default
                .fileExists(
                    atPath:
                        url.path
                )
        else {

            return false
        }


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


        return true
    }


    // ========================================================
    // MARK: - Play Playlist
    // ========================================================

    @MainActor
    private func play(
        playlist: Playlist,
        library: MusicLibraryManager,
        audio: AudioPlayerManager,
        intent: INPlayMediaIntent
    ) -> Bool {

        var songs =
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


        guard !songs.isEmpty
        else {

            return false
        }


        // If Siri asks for shuffled playback,
        // shuffle before selecting the first song.

        if intent.playShuffled ==
            true {

            songs.shuffle()
        }


        guard
            let first =
                songs.first,

            let url =
                library.getURL(
                    for:
                        first
                )
        else {

            return false
        }


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


        return true
    }


    // ========================================================
    // MARK: - Options
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
    // MARK: - INMediaItem
    // ========================================================

    private func makeSongItem(
        _ song: Song
    ) -> INMediaItem {

        let artwork =
            song.coverData.map {

                INImage(
                    imageData:
                        $0
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


    private func makePlaylistItem(
        _ playlist: Playlist
    ) -> INMediaItem {

        let artwork =
            playlist.imageData.map {

                INImage(
                    imageData:
                        $0
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
    // MARK: - Success
    // ========================================================

    private func success(
        _ completion:
            @escaping (
                INPlayMediaIntentResponse
            ) -> Void
    ) {

        completion(
            INPlayMediaIntentResponse(
                code:
                    .success,

                userActivity:
                    nil
            )
        )
    }
}
