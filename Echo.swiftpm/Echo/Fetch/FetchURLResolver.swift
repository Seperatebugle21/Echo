import Foundation
import PythonKit
import YoutubeDL


// MARK: - Resolved Content

enum FetchURLResolvedContent: Identifiable {

    case spotifyTrack(
        SpotifyTrack
    )

    case spotifyPlaylist(
        SpotifyPlaylist,
        [SpotifyTrack]
    )

    case youtubeTrack(
        FetchURLTrackPreview
    )

    case youtubePlaylist(
        FetchURLPlaylistPreview
    )


    var id: String {

        switch self {

        case .spotifyTrack(
            let track
        ):

            return
                "spotify-track-\(track.id)"


        case .spotifyPlaylist(
            let playlist,
            _
        ):

            return
                "spotify-playlist-\(playlist.id)"


        case .youtubeTrack(
            let track
        ):

            return
                "youtube-track-\(track.id)"


        case .youtubePlaylist(
            let playlist
        ):

            return
                "youtube-playlist-\(playlist.id)"
        }
    }


    var title: String {

        switch self {

        case .spotifyTrack(
            let track
        ):

            return track.name


        case .spotifyPlaylist(
            let playlist,
            _
        ):

            return playlist.name


        case .youtubeTrack(
            let track
        ):

            return track.title


        case .youtubePlaylist(
            let playlist
        ):

            return playlist.title
        }
    }


    var artworkURL: URL? {

        switch self {

        case .spotifyTrack(
            let track
        ):

            return track.artworkURL


        case .spotifyPlaylist(
            let playlist,
            _
        ):

            return playlist.artworkURL


        case .youtubeTrack(
            let track
        ):

            return track.artworkURL


        case .youtubePlaylist(
            let playlist
        ):

            return playlist.artworkURL
        }
    }


    var sourceTitle: String {

        switch self {

        case .spotifyTrack,
             .spotifyPlaylist:

            return "Spotify"


        case .youtubeTrack,
             .youtubePlaylist:

            return "YouTube Music"
        }
    }


    var isPlaylist: Bool {

        switch self {

        case .spotifyPlaylist,
             .youtubePlaylist:

            return true


        default:

            return false
        }
    }


    var trackCount: Int {

        switch self {

        case .spotifyTrack,
             .youtubeTrack:

            return 1


        case .spotifyPlaylist(
            _,
            let tracks
        ):

            return tracks.count


        case .youtubePlaylist(
            let playlist
        ):

            return playlist.tracks.count
        }
    }
}


// MARK: - YouTube Preview Models

struct FetchURLTrackPreview:
    Identifiable,
    Hashable,
    Sendable {

    let id: String

    let title: String

    let artist: String

    let artworkURL: URL?

    let sourceURL: URL
}


struct FetchURLPlaylistPreview:
    Identifiable,
    Hashable,
    Sendable {

    let id: String

    let title: String

    let artworkURL: URL?

    let sourceURL: URL

    let tracks:
        [FetchURLTrackPreview]
}


// MARK: - Resolver Error

enum FetchURLResolverError:
    LocalizedError {

    case invalidURL

    case unsupportedURL

    case spotifyLoginRequired

    case spotifyRequestFailed

    case unsupportedSpotifyType

    case youtubeMetadataFailed

    case emptyPlaylist


    var errorDescription:
        String? {

        switch self {

        case .invalidURL:

            return
                "Enter a valid Spotify or YouTube Music URL."


        case .unsupportedURL:

            return
                "Echo currently supports Spotify and YouTube Music URLs."


        case .spotifyLoginRequired:

            return
                "Connect Spotify first so Echo can load the track or playlist information."


        case .spotifyRequestFailed:

            return
                "Echo could not load the Spotify information."


        case .unsupportedSpotifyType:

            return
                "This Spotify URL type is not supported yet."


        case .youtubeMetadataFailed:

            return
                "Echo could not read the YouTube Music information."


        case .emptyPlaylist:

            return
                "No songs were found in this playlist."
        }
    }
}


// MARK: - Resolver

@MainActor
final class FetchURLResolver {

    static let shared =
        FetchURLResolver()


    private init() {}


    // MARK: Resolve

    func resolve(
        _ input: String
    ) async throws
        -> FetchURLResolvedContent {

        let value =
            input
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        guard !value.isEmpty else {

            throw FetchURLResolverError
                .invalidURL
        }


        // =====================================
        // Spotify
        // =====================================

        if let spotifyReference =
            SpotifyURLParser.parse(
                value
            ) {

            return
                try await
                resolveSpotify(
                    spotifyReference
                )
        }


        // =====================================
        // YouTube / YouTube Music
        // =====================================

        guard let url =
            URL(
                string:
                    value
            )

        else {

            throw FetchURLResolverError
                .invalidURL
        }


        guard
            isYouTubeURL(
                url
            )
        else {

            throw FetchURLResolverError
                .unsupportedURL
        }


        return
            try await
            resolveYouTube(
                url
            )
    }


    // MARK: - Spotify

    private func resolveSpotify(
        _ reference:
            SpotifyReference
    ) async throws
        -> FetchURLResolvedContent {

        guard
            SpotifyManager.shared
                .isConnected
        else {

            throw FetchURLResolverError
                .spotifyLoginRequired
        }


        switch reference.type {

        case .track:

            let track =
                try await
                getSpotifyTrack(
                    id:
                        reference.id
                )


            return
                .spotifyTrack(
                    track
                )


        case .playlist:

            let playlist =
                try await
                getSpotifyPlaylist(
                    id:
                        reference.id
                )


            let tracks =
                try await
                SpotifyAPI.shared
                    .getPlaylistTracks(
                        playlistID:
                            reference.id
                    )


            guard !tracks.isEmpty else {

                throw FetchURLResolverError
                    .emptyPlaylist
            }


            return
                .spotifyPlaylist(
                    playlist,
                    tracks
                )


        case .album:

            throw FetchURLResolverError
                .unsupportedSpotifyType
        }
    }


    // MARK: Spotify Track

    private func getSpotifyTrack(
        id: String
    ) async throws
        -> SpotifyTrack {

        let data =
            try await
            spotifyRequest(
                path:
                    "/v1/tracks/\(id)"
            )


        let decoded =
            try JSONDecoder()
                .decode(
                    SpotifyAPITrack.self,
                    from:
                        data
                )


        return SpotifyTrack(

            id:
                decoded.id,

            name:
                decoded.name,

            artist:
                decoded.artists
                    .map(
                        \.name
                    )
                    .joined(
                        separator:
                            ", "
                    ),

            album:
                decoded.album.name,

            durationMS:
                decoded.durationMS,

            artworkURL:
                decoded.album.images
                    .first?
                    .url,

            spotifyURL:
                decoded.externalURLs
                    .spotify
        )
    }


    // MARK: Spotify Playlist

    private func getSpotifyPlaylist(
        id: String
    ) async throws
        -> SpotifyPlaylist {

        let data =
            try await
            spotifyRequest(
                path:
                    "/v1/playlists/\(id)"
            )


        let decoded =
            try JSONDecoder()
                .decode(
                    SpotifyAPIPlaylist.self,
                    from:
                        data
                )


        return SpotifyPlaylist(

            id:
                decoded.id,

            name:
                decoded.name,

            artworkURL:
                decoded.images
                    .first?
                    .url,

            spotifyURL:
                decoded.externalURLs
                    .spotify,

            trackCount:
                decoded.trackCount
        )
    }


    // MARK: Spotify Request

    private func spotifyRequest(
        path: String
    ) async throws
        -> Data {

        let token =
            try await
            SpotifyManager.shared
                .validAccessToken()


        guard let url =
            URL(
                string:
                    "https://api.spotify.com\(path)"
            )
        else {

            throw FetchURLResolverError
                .spotifyRequestFailed
        }


        var request =
            URLRequest(
                url:
                    url
            )


        request.setValue(
            "Bearer \(token)",
            forHTTPHeaderField:
                "Authorization"
        )


        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Accept"
        )


        let (
            data,
            response
        ) =
            try await
            URLSession.shared
                .data(
                    for:
                        request
                )


        guard
            let http =
                response
                    as?
                    HTTPURLResponse,

            200..<300 ~=
                http.statusCode

        else {

            throw FetchURLResolverError
                .spotifyRequestFailed
        }


        return data
    }


    // MARK: - YouTube

    private func resolveYouTube(
        _ url: URL
    ) async throws
        -> FetchURLResolvedContent {

        let inspection =
            try await
            inspectYouTube(
                url
            )


        if !inspection.entries
            .isEmpty {

            let tracks =
                inspection.entries
                    .compactMap {
                        entry
                        ->
                        FetchURLTrackPreview?
                        in


                        guard let sourceURL =
                            entry.sourceURL
                        else {

                            return nil
                        }


                        return FetchURLTrackPreview(

                            id:
                                entry.id,

                            title:
                                entry.title,

                            artist:
                                entry.artist,

                            artworkURL:
                                entry.artworkURL,

                            sourceURL:
                                sourceURL
                        )
                    }


            guard !tracks.isEmpty else {

                throw FetchURLResolverError
                    .emptyPlaylist
            }


            let playlist =
                FetchURLPlaylistPreview(

                    id:
                        inspection.id,

                    title:
                        inspection.title,

                    artworkURL:
                        inspection.artworkURL
                        ??
                        tracks.first?
                            .artworkURL,

                    sourceURL:
                        url,

                    tracks:
                        tracks
                )


            return
                .youtubePlaylist(
                    playlist
                )
        }


        let track =
            FetchURLTrackPreview(

                id:
                    inspection.id,

                title:
                    inspection.title,

                artist:
                    inspection.artist,

                artworkURL:
                    inspection.artworkURL,

                sourceURL:
                    url
            )


        return
            .youtubeTrack(
                track
            )
    }


    // MARK: - YouTube Inspection

    private func inspectYouTube(
        _ url: URL
    ) async throws
        -> YouTubeInspection {

        do {

            return
                try await
                YTDLPRunner.shared
                    .runIsolated {

                        let _ =
                            try await
                            YtDlp()


                        let module =
                            try Python
                                .attemptImport(
                                    "yt_dlp"
                                )


                        var options =
                            PythonObject(
                                [:]
                                    as
                                [String:
                                    PythonObject]
                            )


                        options[
                            "quiet"
                        ] =
                            true


                        options[
                            "no_warnings"
                        ] =
                            true


                        options[
                            "skip_download"
                        ] =
                            true


                        options[
                            "noplaylist"
                        ] =
                            false


                        options[
                            "extract_flat"
                        ] =
                            true


                        options[
                            "socket_timeout"
                        ] =
                            30.0


                        let ydl =
                            module.YoutubeDL(
                                options
                            )


                        let info =
                            try ydl
                                .extract_info
                                .throwing
                                .dynamicallyCall(
                                    withArguments: [

                                        url
                                            .absoluteString,

                                        false
                                    ]
                                )


                        let id =
                            info
                                .checking[
                                    "id"
                                ]
                                .flatMap(
                                    String.init
                                )
                            ??
                            UUID()
                                .uuidString


                        let title =
                            info
                                .checking[
                                    "title"
                                ]
                                .flatMap(
                                    String.init
                                )
                            ??
                            "YouTube Music"


                        let artist =
                            info
                                .checking[
                                    "artist"
                                ]
                                .flatMap(
                                    String.init
                                )
                            ??
                            info
                                .checking[
                                    "uploader"
                                ]
                                .flatMap(
                                    String.init
                                )
                            ??
                            info
                                .checking[
                                    "channel"
                                ]
                                .flatMap(
                                    String.init
                                )
                            ??
                            "YouTube Music"


                        let thumbnail =
                            info
                                .checking[
                                    "thumbnail"
                                ]
                                .flatMap(
                                    String.init
                                )


                        let artworkURL =
                            thumbnail
                                .flatMap(
                                    URL.init(
                                        string:
                                    )
                                )


                        var entries:
                            [YouTubeInspectionEntry] =
                            []


                        if let entriesObject =
                            info
                                .checking[
                                    "entries"
                                ] {

                            let pythonEntries:
                                [PythonObject] =
                                Array(
                                    entriesObject
                                )


                            for entry
                                in pythonEntries {

                                let entryID =
                                    entry
                                        .checking[
                                            "id"
                                        ]
                                        .flatMap(
                                            String.init
                                        )
                                    ??
                                    UUID()
                                        .uuidString


                                let entryTitle =
                                    entry
                                        .checking[
                                            "title"
                                        ]
                                        .flatMap(
                                            String.init
                                        )
                                    ??
                                    "Unknown"


                                let entryArtist =
                                    entry
                                        .checking[
                                            "artist"
                                        ]
                                        .flatMap(
                                            String.init
                                        )
                                    ??
                                    entry
                                        .checking[
                                            "uploader"
                                        ]
                                        .flatMap(
                                            String.init
                                        )
                                    ??
                                    entry
                                        .checking[
                                            "channel"
                                        ]
                                        .flatMap(
                                            String.init
                                        )
                                    ??
                                    "YouTube Music"


                                let entryThumbnail =
                                    entry
                                        .checking[
                                            "thumbnail"
                                        ]
                                        .flatMap(
                                            String.init
                                        )


                                let entryArtworkURL =
                                    entryThumbnail
                                        .flatMap(
                                            URL.init(
                                                string:
                                            )
                                        )


                                let webpage =
                                    entry
                                        .checking[
                                            "webpage_url"
                                        ]
                                        .flatMap(
                                            String.init
                                        )


                                let sourceURL:
                                    URL?


                                if let webpage,
                                   let parsed =
                                    URL(
                                        string:
                                            webpage
                                    ) {

                                    sourceURL =
                                        parsed


                                } else {

                                    sourceURL =
                                        URL(
                                            string:
                                                "https://www.youtube.com/watch?v=\(entryID)"
                                        )
                                }


                                entries.append(
                                    YouTubeInspectionEntry(

                                        id:
                                            entryID,

                                        title:
                                            entryTitle,

                                        artist:
                                            entryArtist,

                                        artworkURL:
                                            entryArtworkURL,

                                        sourceURL:
                                            sourceURL
                                    )
                                )
                            }
                        }


                        return YouTubeInspection(

                            id:
                                id,

                            title:
                                title,

                            artist:
                                artist,

                            artworkURL:
                                artworkURL,

                            entries:
                                entries
                        )
                    }


        } catch {

            print(
                "URL yt-dlp inspection failed:",
                error
            )


            throw FetchURLResolverError
                .youtubeMetadataFailed
        }
    }


    // MARK: - URL Detection

    private func isYouTubeURL(
        _ url: URL
    ) -> Bool {

        guard let host =
            url.host?
                .lowercased()
        else {

            return false
        }


        return
            host ==
                "music.youtube.com"
            ||
            host ==
                "youtube.com"
            ||
            host ==
                "www.youtube.com"
            ||
            host ==
                "m.youtube.com"
            ||
            host ==
                "youtu.be"
    }
}


// MARK: - Internal YouTube Models

private struct YouTubeInspection:
    Sendable {

    let id: String

    let title: String

    let artist: String

    let artworkURL: URL?

    let entries:
        [YouTubeInspectionEntry]
}


private struct YouTubeInspectionEntry:
    Sendable {

    let id: String

    let title: String

    let artist: String

    let artworkURL: URL?

    let sourceURL: URL?
}
