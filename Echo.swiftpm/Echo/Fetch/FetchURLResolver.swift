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

        let result =
            try await
            SpotifyPublicURLResolver.shared
                .resolve(
                    reference:
                        reference
                )


        switch result {

        case .track(
            let track
        ):

            return
                .spotifyTrack(
                    track
                )


        case .playlist(
            let playlist,
            let tracks
        ):

            guard !tracks.isEmpty else {

                throw FetchURLResolverError
                    .emptyPlaylist
            }


            return
                .spotifyPlaylist(
                    playlist,
                    tracks
                )
        }
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


                        // =====================================
                        // ID
                        // =====================================

                        let idValue =
                            Self.stringValue(
                                idObject
                            )


                        let id =
                            idValue
                            ??
                            UUID()
                                .uuidString


                        // =====================================
                        // Title
                        // =====================================

                        let titleValue =
                            Self.stringValue(
                                titleObject
                            )


                        let title =
                            titleValue
                            ??
                            "YouTube Music"


                        // =====================================
                        // Artist
                        // =====================================

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


                        // =====================================
                        // Thumbnail
                        // =====================================

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

                                if let parsedEntry =
                                    Self.parseYouTubeEntry(
                                        entry
                                    ) {

                                    entries.append(
                                        parsedEntry
                                    )
                                }
                            }
                        }


                        // =====================================
                        // Result
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
        _ entry:
            PythonObject
    ) -> YouTubeInspectionEntry? {

        // =====================================
        // Python values
        // =====================================

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

        let entryID =
            stringValue(
                idObject
            )
            ??
            UUID()
                .uuidString


        // =====================================
        // Title
        // =====================================

        let entryTitle =
            stringValue(
                titleObject
            )
            ??
            "Unknown"


        // =====================================
        // Artist
        // =====================================

        let artistValue =
            stringValue(
                artistObject
            )


        let uploaderValue =
            stringValue(
                uploaderObject
            )


        let channelValue =
            stringValue(
                channelObject
            )


        let entryArtist =
            artistValue
            ??
            uploaderValue
            ??
            channelValue
            ??
            "YouTube Music"


        // =====================================
        // Artwork
        // =====================================

        let thumbnail =
            stringValue(
                thumbnailObject
            )


        let entryArtworkURL =
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
                        "https://www.youtube.com/watch?v=\(entryID)"
                )
        }


        guard sourceURL != nil else {

            return nil
        }


        return YouTubeInspectionEntry(

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


        let value =
            String(
                object
            )


        guard let value else {

            return nil
        }


        let cleaned =
            value
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
