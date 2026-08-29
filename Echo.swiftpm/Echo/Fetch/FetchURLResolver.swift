import Foundation
import PythonKit
import YoutubeDL


// MARK: - Resolved Content

enum FetchURLResolvedContent:
    Identifiable {

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

            return
                track.name


        case .spotifyPlaylist(
            let playlist,
            _
        ):

            return
                playlist.name


        case .youtubeTrack(
            let track
        ):

            return
                track.title


        case .youtubePlaylist(
            let playlist
        ):

            return
                playlist.title
        }
    }


    var artworkURL: URL? {

        switch self {

        case .spotifyTrack(
            let track
        ):

            return
                track.artworkURL


        case .spotifyPlaylist(
            let playlist,
            _
        ):

            return
                playlist.artworkURL


        case .youtubeTrack(
            let track
        ):

            return
                track.artworkURL


        case .youtubePlaylist(
            let playlist
        ):

            return
                playlist.artworkURL
        }
    }


    var sourceTitle: String {

        switch self {

        case .spotifyTrack,
             .spotifyPlaylist:

            return
                "Spotify"


        case .youtubeTrack,
             .youtubePlaylist:

            return
                "YouTube Music"
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

            return
                tracks.count


        case .youtubePlaylist(
            let playlist
        ):

            return
                playlist.tracks.count
        }
    }
}


// MARK: - YouTube Preview Models

struct FetchURLTrackPreview:
    Identifiable,
    Hashable,
    Sendable {

    let id:
        String

    let title:
        String

    let artist:
        String

    let artworkURL:
        URL?

    let sourceURL:
        URL
}


struct FetchURLPlaylistPreview:
    Identifiable,
    Hashable,
    Sendable {

    let id:
        String

    let title:
        String

    let artworkURL:
        URL?

    let sourceURL:
        URL

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


    // MARK: - Resolve

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


        guard isYouTubeURL(
            url
        ) else {

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


    // MARK: - Spotify Track

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


        let artist =
            decoded.artists
                .map(
                    \.name
                )
                .joined(
                    separator:
                        ", "
                )


        let artwork =
            decoded.album.images
                .first?
                .url


        return SpotifyTrack(

            id:
                decoded.id,

            name:
                decoded.name,

            artist:
                artist,

            album:
                decoded.album.name,

            durationMS:
                decoded.durationMS,

            artworkURL:
                artwork,

            spotifyURL:
                decoded.externalURLs
                    .spotify
        )
    }


    // MARK: - Spotify Playlist

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


        let artwork =
            decoded.images
                .first?
                .url


        return SpotifyPlaylist(

            id:
                decoded.id,

            name:
                decoded.name,

            artworkURL:
                artwork,

            spotifyURL:
                decoded.externalURLs
                    .spotify,

            trackCount:
                decoded.trackCount
        )
    }


    // MARK: - Spotify Request

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


        let result =
            try await
            URLSession.shared
                .data(
                    for:
                        request
                )


        let data =
            result.0

        let response =
            result.1


        guard let http =
            response
                as?
                HTTPURLResponse
        else {

            throw FetchURLResolverError
                .spotifyRequestFailed
        }


        guard
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


        // =====================================
        // Playlist
        // =====================================

        if !inspection.entries.isEmpty {

            var tracks:
                [FetchURLTrackPreview] =
                []


            for entry
                in inspection.entries {

                guard let sourceURL =
                    entry.sourceURL
                else {

                    continue
                }


                let track =
                    FetchURLTrackPreview(

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


                tracks.append(
                    track
                )
            }


            guard !tracks.isEmpty else {

                throw FetchURLResolverError
                    .emptyPlaylist
            }


            let playlistArtwork:
                URL?


            if let artwork =
                inspection.artworkURL {

                playlistArtwork =
                    artwork

            } else {

                playlistArtwork =
                    tracks.first?
                        .artworkURL
            }


            let playlist =
                FetchURLPlaylistPreview(

                    id:
                        inspection.id,

                    title:
                        inspection.title,

                    artworkURL:
                        playlistArtwork,

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


        // =====================================
        // Single Track
        // =====================================

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

                        // =====================================
                        // Initialize Python / yt-dlp
                        // =====================================

                        let _ =
                            try await
                            YtDlp()


                        let module =
                            try Python
                                .attemptImport(
                                    "yt_dlp"
                                )


                        // =====================================
                        // Options
                        // =====================================

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


                        // =====================================
                        // Extract
                        // =====================================

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


                        // =====================================
                        // Main Metadata
                        // =====================================

                        let idObject =
                            info.checking[
                                "id"
                            ]


                        let titleObject =
                            info.checking[
                                "title"
                            ]


                        let artistObject =
                            info.checking[
                                "artist"
                            ]


                        let uploaderObject =
                            info.checking[
                                "uploader"
                            ]


                        let channelObject =
                            info.checking[
                                "channel"
                            ]


                        let thumbnailObject =
                            info.checking[
                                "thumbnail"
                            ]


                        // ID

                        let idValue =
                            Self.stringValue(
                                idObject
                            )


                        let id =
                            idValue
                            ??
                            UUID()
                                .uuidString


                        // Title

                        let titleValue =
                            Self.stringValue(
                                titleObject
                            )


                        let title =
                            titleValue
                            ??
                            "YouTube Music"


                        // Artist

                        let artistValue =
                            Self.stringValue(
                                artistObject
                            )


                        let uploaderValue =
                            Self.stringValue(
                                uploaderObject
                            )


                        let channelValue =
                            Self.stringValue(
                                channelObject
                            )


                        let artist =
                            artistValue
                            ??
                            uploaderValue
                            ??
                            channelValue
                            ??
                            "YouTube Music"


                        // Thumbnail

                        let thumbnail =
                            Self.stringValue(
                                thumbnailObject
                            )


                        let artworkURL =
                            Self.makeURL(
                                thumbnail
                            )


                        // =====================================
                        // Playlist Entries
                        // =====================================

                        var entries:
                            [YouTubeInspectionEntry] =
                            []


                        let entriesObject =
                            info.checking[
                                "entries"
                            ]


                        if let entriesObject {

                            let pythonEntries:
                                [PythonObject] =
                                Array(
                                    entriesObject
                                )


                            for entry
                                in pythonEntries {

                                let parsedEntry =
                                    Self.parseYouTubeEntry(
                                        entry
                                    )


                                if let parsedEntry {

                                    entries.append(
                                        parsedEntry
                                    )
                                }
                            }
                        }


                        // =====================================
                        // Return
                        // =====================================

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


    // MARK: - Parse YouTube Entry

    nonisolated
    private static func parseYouTubeEntry(
        _ entry: PythonObject
    ) -> YouTubeInspectionEntry? {

        let idObject =
            entry.checking[
                "id"
            ]


        let titleObject =
            entry.checking[
                "title"
            ]


        let artistObject =
            entry.checking[
                "artist"
            ]


        let uploaderObject =
            entry.checking[
                "uploader"
            ]


        let channelObject =
            entry.checking[
                "channel"
            ]


        let thumbnailObject =
            entry.checking[
                "thumbnail"
            ]


        let webpageObject =
            entry.checking[
                "webpage_url"
            ]


        // =====================================
        // ID
        // =====================================

        let id =
            stringValue(
                idObject
            )
            ??
            UUID()
                .uuidString


        // =====================================
        // Title
        // =====================================

        let title =
            stringValue(
                titleObject
            )
            ??
            "Unknown"


        // =====================================
        // Artist
        // =====================================

        let artist =
            stringValue(
                artistObject
            )
            ??
            stringValue(
                uploaderObject
            )
            ??
            stringValue(
                channelObject
            )
            ??
            "YouTube Music"


        // =====================================
        // Artwork
        // =====================================

        let thumbnail =
            stringValue(
                thumbnailObject
            )


        let artworkURL =
            makeURL(
                thumbnail
            )


        // =====================================
        // Source URL
        // =====================================

        let webpage =
            stringValue(
                webpageObject
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
                        "https://www.youtube.com/watch?v=\(id)"
                )
        }


        guard sourceURL != nil else {

            return nil
        }


        return YouTubeInspectionEntry(

            id:
                id,

            title:
                title,

            artist:
                artist,

            artworkURL:
                artworkURL,

            sourceURL:
                sourceURL
        )
    }


    // MARK: - Python Helpers

    nonisolated
    private static func stringValue(
        _ object:
            PythonObject?
    ) -> String? {

        guard let object else {

            return nil
        }


        let result =
            String(
                object
            )


        guard let result else {

            return nil
        }


        let cleaned =
            result
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        guard !cleaned.isEmpty else {

            return nil
        }


        if cleaned ==
            "None" {

            return nil
        }


        return cleaned
    }


    nonisolated
    private static func makeURL(
        _ value:
            String?
    ) -> URL? {

        guard let value else {

            return nil
        }


        return URL(
            string:
                value
        )
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


        switch host {

        case "music.youtube.com",
             "youtube.com",
             "www.youtube.com",
             "m.youtube.com",
             "youtu.be":

            return true


        default:

            return false
        }
    }
}


// MARK: - Internal YouTube Models

private struct YouTubeInspection:
    Sendable {

    let id:
        String

    let title:
        String

    let artist:
        String

    let artworkURL:
        URL?

    let entries:
        [YouTubeInspectionEntry]
}


private struct YouTubeInspectionEntry:
    Sendable {

    let id:
        String

    let title:
        String

    let artist:
        String

    let artworkURL:
        URL?

    let sourceURL:
        URL?
}
