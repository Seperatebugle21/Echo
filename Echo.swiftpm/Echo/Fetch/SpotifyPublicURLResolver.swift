import Foundation


// MARK: - Error

enum SpotifyPublicURLResolverError:
    LocalizedError {

    case invalidURL
    case unsupportedType
    case requestFailed
    case accessDenied
    case invalidResponse
    case metadataNotFound
    case emptyPlaylist


    var errorDescription: String? {

        switch self {

        case .invalidURL:
            return "The Spotify URL is invalid."

        case .unsupportedType:
            return "This Spotify URL type is not supported."

        case .requestFailed:
            return "Echo could not load the public Spotify page."

        case .accessDenied:
            return "This Spotify content is not publicly accessible."

        case .invalidResponse:
            return "Spotify returned an invalid public page."

        case .metadataNotFound:
            return "Echo could not find the Spotify metadata."

        case .emptyPlaylist:
            return "No songs were found in this playlist."
        }
    }
}


// MARK: - Result

enum SpotifyPublicURLResult {

    case track(
        SpotifyTrack
    )

    case playlist(
        SpotifyPlaylist,
        [SpotifyTrack]
    )
}


// MARK: - Resolver

final class SpotifyPublicURLResolver:
    @unchecked Sendable {

    static let shared =
        SpotifyPublicURLResolver()


    private init() {}


    // MARK: - Resolve

    func resolve(
        reference: SpotifyReference
    ) async throws
        -> SpotifyPublicURLResult {

        switch reference.type {

        case .track:

            let track =
                try await
                resolveTrack(
                    id:
                        reference.id
                )


            return
                .track(
                    track
                )


        case .playlist:

            let result =
                try await
                resolvePlaylist(
                    id:
                        reference.id,
                    originalURL:
                        reference.url
                )


            return
                .playlist(
                    result.playlist,
                    result.tracks
                )


        case .album:

            throw SpotifyPublicURLResolverError
                .unsupportedType
        }
    }


    // MARK: - Playlist

    private func resolvePlaylist(
        id: String,
        originalURL: URL
    ) async throws
        -> (
            playlist: SpotifyPlaylist,
            tracks: [SpotifyTrack]
        ) {

        guard let embedURL =
            URL(
                string:
                    "https://open.spotify.com/embed/playlist/\(id)"
            )
        else {

            throw SpotifyPublicURLResolverError
                .invalidURL
        }


        let json =
            try await
            fetchEmbedJSON(
                url:
                    embedURL
            )


        guard let entity =
            extractEntity(
                from:
                    json
            )
        else {

            throw SpotifyPublicURLResolverError
                .metadataNotFound
        }


        // =====================================
        // Playlist Metadata
        // =====================================

        let playlistName =
            string(
                entity[
                    "name"
                ]
            )
            ??
            string(
                entity[
                    "title"
                ]
            )
            ??
            "Spotify Playlist"


        let playlistArtwork =
            artworkURL(
                from:
                    entity
            )


        guard let rawTrackList =
            entity[
                "trackList"
            ]
                as?
                [Any]
        else {

            throw SpotifyPublicURLResolverError
                .emptyPlaylist
        }


        // =====================================
        // Initial Track Metadata
        // =====================================

        var baseTracks:
            [SpotifyTrack] =
            []


        for rawItem
            in rawTrackList {

            guard let item =
                rawItem
                    as?
                    [String: Any]
            else {

                continue
            }


            guard let track =
                makeTrack(
                    from:
                        item,
                    fallbackArtwork:
                        playlistArtwork
                )
            else {

                continue
            }


            baseTracks.append(
                track
            )
        }


        guard !baseTracks.isEmpty else {

            throw SpotifyPublicURLResolverError
                .emptyPlaylist
        }


        // =====================================
        // Per-track artwork
        //
        // Spotify's playlist embed normally does
        // not include individual album artwork.
        //
        // Fetch each track embed separately.
        //
        // We process batches of four so a playlist
        // does not fire dozens of requests at once.
        // =====================================

        let tracks:
            [SpotifyTrack]


        do {

            let paginatedTracks =
                try await
                fetchAllPlaylistTracks(
                    id: id,
                    embedJSON: json
                )


            if paginatedTracks.isEmpty {

                tracks =
                    await enrichTracks(
                    baseTracks,
                    fallbackArtwork:
                        playlistArtwork
                )

            } else {

                tracks =
                    paginatedTracks
            }


        } catch {

            print(
                "Spotify public playlist pagination fallback:",
                error
            )


            tracks =
                await enrichTracks(
                    baseTracks,
                    fallbackArtwork:
                        playlistArtwork
                )
        }


        // =====================================
        // Playlist Object
        // =====================================

        let playlist =
            SpotifyPlaylist(

                id:
                    id,

                name:
                    playlistName,

                artworkURL:
                    playlistArtwork,

                spotifyURL:
                    originalURL,

                trackCount:
                    tracks.count
            )


        return (
            playlist,
            tracks
        )
    }


    // MARK: - Enrich Playlist Tracks

    private func enrichTracks(
        _ tracks:
            [SpotifyTrack],
        fallbackArtwork:
            URL?
    ) async -> [SpotifyTrack] {

        guard !tracks.isEmpty else {

            return []
        }


        let batchSize =
            4


        var result =
            tracks


        var startIndex =
            0


        while startIndex <
            tracks.count {

            let endIndex =
                min(
                    startIndex + batchSize,
                    tracks.count
                )


            let indexes =
                Array(
                    startIndex..<endIndex
                )


            let enriched =
                await withTaskGroup(
                    of:
                        TrackArtworkResult.self
                ) {
                    group in


                    for index
                        in indexes {

                        let track =
                            tracks[
                                index
                            ]


                        group.addTask {
                            [self] in


                            let metadata =
                                await fetchTrackMetadataSafely(
                                    id:
                                        track.id
                                )


                            return TrackArtworkResult(

                                index:
                                    index,

                                artworkURL:
                                    metadata?
                                        .artworkURL,

                                album:
                                    metadata?
                                        .album
                            )
                        }
                    }


                    var values:
                        [TrackArtworkResult] =
                        []


                    for await value
                        in group {

                        values.append(
                            value
                        )
                    }


                    return values
                }


            for item
                in enriched {

                let old =
                    result[
                        item.index
                    ]


                let artwork =
                    item.artworkURL
                    ??
                    old.artworkURL
                    ??
                    fallbackArtwork


                let album:
                    String


                if let fetchedAlbum =
                    item.album,
                   !fetchedAlbum.isEmpty,
                   fetchedAlbum !=
                    "Spotify" {

                    album =
                        fetchedAlbum

                } else {

                    album =
                        old.album
                }


                result[
                    item.index
                ] =
                    SpotifyTrack(

                        id:
                            old.id,

                        name:
                            old.name,

                        artist:
                            old.artist,

                        album:
                            album,

                        durationMS:
                            old.durationMS,

                        artworkURL:
                            artwork,

                        spotifyURL:
                            old.spotifyURL
                    )
            }


            startIndex =
                endIndex
        }


        return result
    }


    // MARK: - Paginated Public Playlist Tracks

    private func fetchAllPlaylistTracks(
        id: String,
        embedJSON: [String: Any]
    ) async throws -> [SpotifyTrack] {

        guard let session =
            dictionary(
                at: [
                    "props",
                    "pageProps",
                    "state",
                    "settings",
                    "session"
                ],
                in: embedJSON
            ),
              let accessToken =
            string(
                session[
                    "accessToken"
                ]
            )
        else {

            throw SpotifyPublicURLResolverError
                .metadataNotFound
        }


        guard var nextURL =
            URL(
                string:
                    "https://api.spotify.com/v1/playlists/\(id)/items?limit=50"
            )
        else {

            throw SpotifyPublicURLResolverError
                .invalidURL
        }


        var tracks:
            [SpotifyTrack] = []


        while true {

            var request =
                URLRequest(
                    url: nextURL
                )


            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField:
                    "Authorization"
            )


            request.setValue(
                "application/json",
                forHTTPHeaderField:
                    "Accept"
            )


            let (data, response) =
                try await URLSession.shared
                    .data(
                        for: request
                    )


            guard let httpResponse =
                response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode
            else {

                throw SpotifyPublicURLResolverError
                    .requestFailed
            }


            let page =
                try JSONDecoder()
                    .decode(
                        SpotifyPlaylistItemsResponse.self,
                        from: data
                    )


            tracks.append(
                contentsOf:
                    page.items.compactMap {
                        item in


                        guard let track =
                            item.item
                        else {

                            return nil
                        }


                        return SpotifyTrack(
                            id: track.id,
                            name: track.name,
                            artist:
                                track.artists
                                    .map(\.name)
                                    .joined(
                                        separator: ", "
                                    ),
                            album: track.album.name,
                            durationMS:
                                track.durationMS,
                            artworkURL:
                                track.album.images
                                    .first?
                                    .url,
                            spotifyURL:
                                track.externalURLs
                                    .spotify
                        )
                    }
            )


            guard let next =
                page.next,
                  let parsedURL =
                URL(
                    string: next
                )
            else {

                break
            }


            nextURL =
                parsedURL
        }


        return tracks
    }


    // MARK: - Safe Track Metadata

    private func fetchTrackMetadataSafely(
        id: String
    ) async
        -> PublicTrackMetadata? {

        do {

            return
                try await
                fetchTrackMetadata(
                    id:
                        id
                )

        } catch {

            print(
                "Spotify track metadata fallback failed:",
                id,
                error
            )


            return nil
        }
    }


    // MARK: - Track Metadata

    private func fetchTrackMetadata(
        id: String
    ) async throws
        -> PublicTrackMetadata {

        guard let embedURL =
            URL(
                string:
                    "https://open.spotify.com/embed/track/\(id)"
            )
        else {

            throw SpotifyPublicURLResolverError
                .invalidURL
        }


        let json =
            try await
            fetchEmbedJSON(
                url:
                    embedURL
            )


        guard let entity =
            extractEntity(
                from:
                    json
            )
        else {

            throw SpotifyPublicURLResolverError
                .metadataNotFound
        }


        let artwork =
            artworkURL(
                from:
                    entity
            )


        let album:
            String?


        if let albumDictionary =
            entity[
                "album"
            ]
                as?
                [String: Any] {

            album =
                string(
                    albumDictionary[
                        "name"
                    ]
                )

        } else {

            album =
                nil
        }


        return PublicTrackMetadata(

            artworkURL:
                artwork,

            album:
                album
        )
    }


    // MARK: - Single Track

    private func resolveTrack(
        id: String
    ) async throws
        -> SpotifyTrack {

        guard let embedURL =
            URL(
                string:
                    "https://open.spotify.com/embed/track/\(id)"
            )
        else {

            throw SpotifyPublicURLResolverError
                .invalidURL
        }


        let json =
            try await
            fetchEmbedJSON(
                url:
                    embedURL
            )


        guard let entity =
            extractEntity(
                from:
                    json
            )
        else {

            throw SpotifyPublicURLResolverError
                .metadataNotFound
        }


        let title =
            string(
                entity[
                    "title"
                ]
            )
            ??
            string(
                entity[
                    "name"
                ]
            )
            ??
            "Unknown Track"


        let artist =
            artistString(
                from:
                    entity
            )


        let duration =
            integer(
                entity[
                    "duration"
                ]
            )
            ??
            0


        let artwork =
            artworkURL(
                from:
                    entity
            )


        let album:
            String


        if let albumDictionary =
            entity[
                "album"
            ]
                as?
                [String: Any],
           let albumName =
            string(
                albumDictionary[
                    "name"
                ]
            ) {

            album =
                albumName

        } else {

            album =
                "Spotify"
        }


        guard let spotifyURL =
            URL(
                string:
                    "https://open.spotify.com/track/\(id)"
            )
        else {

            throw SpotifyPublicURLResolverError
                .invalidURL
        }


        return SpotifyTrack(

            id:
                id,

            name:
                title,

            artist:
                artist,

            album:
                album,

            durationMS:
                duration,

            artworkURL:
                artwork,

            spotifyURL:
                spotifyURL
        )
    }


    // MARK: - Fetch Embed

    private func fetchEmbedJSON(
        url: URL
    ) async throws
        -> [String: Any] {

        var request =
            URLRequest(
                url:
                    url
            )


        request.setValue(
            """
            Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148
            """,
            forHTTPHeaderField:
                "User-Agent"
        )


        request.setValue(
            "text/html,application/xhtml+xml",
            forHTTPHeaderField:
                "Accept"
        )


        request.setValue(
            "en-US,en;q=0.9",
            forHTTPHeaderField:
                "Accept-Language"
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


        guard let http =
            response
                as?
                HTTPURLResponse
        else {

            throw SpotifyPublicURLResolverError
                .invalidResponse
        }


        switch http.statusCode {

        case 200..<300:

            break


        case 401,
             403:

            throw SpotifyPublicURLResolverError
                .accessDenied


        default:

            throw SpotifyPublicURLResolverError
                .requestFailed
        }


        guard let html =
            String(
                data:
                    data,
                encoding:
                    .utf8
            )
        else {

            throw SpotifyPublicURLResolverError
                .invalidResponse
        }


        return
            try extractNextData(
                from:
                    html
            )
    }


    // MARK: - __NEXT_DATA__

    private func extractNextData(
        from html: String
    ) throws
        -> [String: Any] {

        let pattern =
            #"<script id="__NEXT_DATA__"[^>]*>([^<]+)</script>"#


        let regex =
            try NSRegularExpression(
                pattern:
                    pattern,
                options:
                    []
            )


        let range =
            NSRange(
                html.startIndex..<html.endIndex,
                in:
                    html
            )


        guard let match =
            regex.firstMatch(
                in:
                    html,
                options:
                    [],
                range:
                    range
            )
        else {

            throw SpotifyPublicURLResolverError
                .metadataNotFound
        }


        guard let jsonRange =
            Range(
                match.range(
                    at:
                        1
                ),
                in:
                    html
            )
        else {

            throw SpotifyPublicURLResolverError
                .invalidResponse
        }


        let jsonString =
            String(
                html[
                    jsonRange
                ]
            )


        guard let data =
            jsonString.data(
                using:
                    .utf8
            )
        else {

            throw SpotifyPublicURLResolverError
                .invalidResponse
        }


        let object =
            try JSONSerialization
                .jsonObject(
                    with:
                        data
                )


        guard let dictionary =
            object
                as?
                [String: Any]
        else {

            throw SpotifyPublicURLResolverError
                .invalidResponse
        }


        return dictionary
    }


    // MARK: - Entity

    private func extractEntity(
        from json:
            [String: Any]
    ) -> [String: Any]? {

        let paths:
            [[String]] =
            [

                [
                    "props",
                    "pageProps",
                    "state",
                    "data",
                    "entity"
                ],

                [
                    "props",
                    "pageProps",
                    "data",
                    "entity"
                ],

                [
                    "props",
                    "pageProps",
                    "entity"
                ]
            ]


        for path
            in paths {

            if let result =
                dictionary(
                    at:
                        path,
                    in:
                        json
                ) {

                return result
            }
        }


        return
            deepFindEntity(
                in:
                    json
            )
    }


    // MARK: - Dictionary Path

    private func dictionary(
        at path: [String],
        in root:
            [String: Any]
    ) -> [String: Any]? {

        var current:
            Any =
            root


        for key
            in path {

            guard let dictionary =
                current
                    as?
                    [String: Any]
            else {

                return nil
            }


            guard let next =
                dictionary[
                    key
                ]
            else {

                return nil
            }


            current =
                next
        }


        return current
            as?
            [String: Any]
    }


    // MARK: - Deep Find

    private func deepFindEntity(
        in value: Any,
        depth: Int = 0
    ) -> [String: Any]? {

        guard depth <
            10
        else {

            return nil
        }


        if let dictionary =
            value
                as?
                [String: Any] {

            if dictionary[
                "trackList"
            ] != nil {

                return dictionary
            }


            if let type =
                string(
                    dictionary[
                        "type"
                    ]
                ),
               type ==
                "track" {

                return dictionary
            }


            for child
                in dictionary.values {

                if let found =
                    deepFindEntity(
                        in:
                            child,
                        depth:
                            depth + 1
                    ) {

                    return found
                }
            }
        }


        if let array =
            value
                as?
                [Any] {

            for child
                in array {

                if let found =
                    deepFindEntity(
                        in:
                            child,
                        depth:
                            depth + 1
                    ) {

                    return found
                }
            }
        }


        return nil
    }


    // MARK: - Track Parser

    private func makeTrack(
        from dictionary:
            [String: Any],
        fallbackArtwork:
            URL?
    ) -> SpotifyTrack? {

        guard let uri =
            string(
                dictionary[
                    "uri"
                ]
            )
        else {

            return nil
        }


        let prefix =
            "spotify:track:"


        guard uri.hasPrefix(
            prefix
        ) else {

            return nil
        }


        let id =
            String(
                uri.dropFirst(
                    prefix.count
                )
            )


        guard !id.isEmpty else {

            return nil
        }


        let title =
            string(
                dictionary[
                    "title"
                ]
            )
            ??
            string(
                dictionary[
                    "name"
                ]
            )
            ??
            "Unknown Track"


        let artist =
            artistString(
                from:
                    dictionary
            )


        let duration =
            integer(
                dictionary[
                    "duration"
                ]
            )
            ??
            0


        let album:
            String


        if let albumDictionary =
            dictionary[
                "album"
            ]
                as?
                [String: Any],
           let albumName =
            string(
                albumDictionary[
                    "name"
                ]
            ) {

            album =
                albumName

        } else {

            album =
                "Spotify"
        }


        let artwork =
            artworkURL(
                from:
                    dictionary
            )
            ??
            fallbackArtwork


        guard let spotifyURL =
            URL(
                string:
                    "https://open.spotify.com/track/\(id)"
            )
        else {

            return nil
        }


        return SpotifyTrack(

            id:
                id,

            name:
                title,

            artist:
                artist,

            album:
                album,

            durationMS:
                duration,

            artworkURL:
                artwork,

            spotifyURL:
                spotifyURL
        )
    }


    // MARK: - Artist

    private func artistString(
        from dictionary:
            [String: Any]
    ) -> String {

        if let subtitle =
            string(
                dictionary[
                    "subtitle"
                ]
            ),
           !subtitle.isEmpty {

            return subtitle
        }


        if let artists =
            dictionary[
                "artists"
            ]
                as?
                [[String: Any]] {

            let names =
                artists.compactMap {
                    artist in


                    string(
                        artist[
                            "name"
                        ]
                    )
                }


            if !names.isEmpty {

                return
                    names.joined(
                        separator:
                            ", "
                    )
            }
        }


        return
            "Unknown Artist"
    }


    // MARK: - Artwork

    private func artworkURL(
        from dictionary:
            [String: Any]
    ) -> URL? {

        // =====================================
        // coverArt.sources
        // =====================================

        if let coverArt =
            dictionary[
                "coverArt"
            ]
                as?
                [String: Any],

           let sources =
            coverArt[
                "sources"
            ]
                as?
                [[String: Any]] {

            for source
                in sources.reversed() {

                if let value =
                    string(
                        source[
                            "url"
                        ]
                    ),
                   let url =
                    URL(
                        string:
                            value
                    ) {

                    return url
                }
            }
        }


        // =====================================
        // visualIdentity.image
        // =====================================

        if let visualIdentity =
            dictionary[
                "visualIdentity"
            ]
                as?
                [String: Any],

           let images =
            visualIdentity[
                "image"
            ]
                as?
                [[String: Any]] {

            for image
                in images.reversed() {

                if let value =
                    string(
                        image[
                            "url"
                        ]
                    ),
                   let url =
                    URL(
                        string:
                            value
                    ) {

                    return url
                }
            }
        }


        // =====================================
        // images
        // =====================================

        if let images =
            dictionary[
                "images"
            ]
                as?
                [[String: Any]] {

            for image
                in images.reversed() {

                if let value =
                    string(
                        image[
                            "url"
                        ]
                    ),
                   let url =
                    URL(
                        string:
                            value
                    ) {

                    return url
                }
            }
        }


        // =====================================
        // thumbnail
        // =====================================

        if let value =
            string(
                dictionary[
                    "thumbnail"
                ]
            ),
           let url =
            URL(
                string:
                    value
            ) {

            return url
        }


        return nil
    }


    // MARK: - Helpers

    private func string(
        _ value: Any?
    ) -> String? {

        if let string =
            value
                as?
                String {

            return string
        }


        return nil
    }


    private func integer(
        _ value: Any?
    ) -> Int? {

        if let value =
            value
                as?
                Int {

            return value
        }


        if let value =
            value
                as?
                NSNumber {

            return value.intValue
        }


        if let value =
            value
                as?
                String {

            return Int(
                value
            )
        }


        return nil
    }
}


// MARK: - Internal Metadata

private struct PublicTrackMetadata:
    Sendable {

    let artworkURL:
        URL?

    let album:
        String?
}


private struct TrackArtworkResult:
    Sendable {

    let index:
        Int

    let artworkURL:
        URL?

    let album:
        String?
}
