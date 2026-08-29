import Foundation


@MainActor
final class SpotifyAPI {

    static let shared =
        SpotifyAPI()

    private let spotify =
        SpotifyManager.shared

    private init() {}


    // MARK: - Liked Songs

    func getLikedSongs() async throws
        -> [SpotifyTrack] {

        var result:
            [SpotifyTrack] =
            []

        var nextURL:
            URL? =
            URL(
                string:
                    "https://api.spotify.com/v1/me/tracks?limit=50"
            )


        while let url =
            nextURL {

            let data =
                try await
                request(
                    url
                )


            let response =
                try JSONDecoder()
                    .decode(
                        SpotifySavedTracksResponse.self,
                        from:
                            data
                    )


            let tracks =
                response.items.map {
                    item in


                    let track =
                        item.track


                    return SpotifyTrack(

                        id:
                            track.id,

                        name:
                            track.name,

                        artist:
                            track.artists
                                .map(
                                    \.name
                                )
                                .joined(
                                    separator:
                                        ", "
                                ),

                        album:
                            track.album.name,

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


            result.append(
                contentsOf:
                    tracks
            )


            if let next =
                response.next {

                nextURL =
                    URL(
                        string:
                            next
                    )

            } else {

                nextURL =
                    nil
            }
        }


        return result
    }


    // MARK: - Search

    func searchTracks(
        query: String,
        offset: Int = 0
    ) async throws
        -> [SpotifyTrack] {

        let token =
            try await
            spotify.validAccessToken()


        var components =
            URLComponents(
                string:
                    "https://api.spotify.com/v1/search"
            )!


        components.queryItems = [

            URLQueryItem(
                name:
                    "q",
                value:
                    query
            ),

            URLQueryItem(
                name:
                    "type",
                value:
                    "track"
            ),

            URLQueryItem(
                name:
                    "limit",
                value:
                    "10"
            ),

            URLQueryItem(
                name:
                    "offset",
                value:
                    "\(offset)"
            )
        ]


        guard let url =
            components.url
        else {

            throw SpotifyAPIError
                .invalidResponse
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


        guard let http =
            response
                as?
                HTTPURLResponse
        else {

            throw SpotifyAPIError
                .invalidResponse
        }


        try validateStatus(
            http.statusCode
        )


        let decoded =
            try JSONDecoder()
                .decode(
                    SpotifySearchResponse.self,
                    from:
                        data
                )


        return decoded.tracks.items.map {
            track in


            SpotifyTrack(

                id:
                    track.id,

                name:
                    track.name,

                artist:
                    track.artists
                        .map(
                            \.name
                        )
                        .joined(
                            separator:
                                ", "
                        ),

                album:
                    track.album.name,

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
    }


    // MARK: - Playlists

    func getPlaylists() async throws
        -> [SpotifyPlaylist] {

        var result:
            [SpotifyPlaylist] =
            []


        var nextURL:
            URL? =
            URL(
                string:
                    "https://api.spotify.com/v1/me/playlists?limit=50"
            )


        while let url =
            nextURL {

            let data =
                try await
                request(
                    url
                )


            let response =
                try JSONDecoder()
                    .decode(
                        SpotifyPlaylistsResponse.self,
                        from:
                            data
                    )


            let playlists =
                response.items.map {
                    playlist in


                    SpotifyPlaylist(

                        id:
                            playlist.id,

                        name:
                            playlist.name,

                        artworkURL:
                            playlist.images
                                .first?
                                .url,

                        spotifyURL:
                            playlist.externalURLs
                                .spotify,

                        trackCount:
                            playlist.trackCount
                    )
                }


            result.append(
                contentsOf:
                    playlists
            )


            if let next =
                response.next {

                nextURL =
                    URL(
                        string:
                            next
                    )

            } else {

                nextURL =
                    nil
            }
        }


        return result
    }


    // MARK: - Playlist Tracks

    func getPlaylistTracks(
        playlistID: String
    ) async throws
        -> [SpotifyTrack] {

        var tracks:
            [SpotifyTrack] =
            []


        guard var nextURL =
            URL(
                string:
                    "https://api.spotify.com/v1/playlists/\(playlistID)/items?limit=50"
            )
        else {

            throw SpotifyAPIError
                .invalidResponse
        }


        while true {

            do {

                let data =
                    try await
                    request(
                        nextURL
                    )


                let response =
                    try JSONDecoder()
                        .decode(
                            SpotifyPlaylistItemsResponse.self,
                            from:
                                data
                        )


                for item
                    in response.items {

                    guard let track =
                        item.item
                    else {

                        continue
                    }


                    let spotifyTrack =
                        SpotifyTrack(

                            id:
                                track.id,

                            name:
                                track.name,

                            artist:
                                track.artists
                                    .map(
                                        \.name
                                    )
                                    .joined(
                                        separator:
                                            ", "
                                    ),

                            album:
                                track.album.name,

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


                    tracks.append(
                        spotifyTrack
                    )
                }


                guard let next =
                    response.next,
                      let parsedURL =
                    URL(
                        string:
                            next
                    )
                else {

                    break
                }


                nextURL =
                    parsedURL


            } catch let error
                as SpotifyAPIError {

                // Give the URL downloader a meaningful
                // error specifically for playlists that
                // Spotify does not expose to this account.

                if case .forbidden =
                    error {

                    throw SpotifyAPIError
                        .playlistItemsUnavailable
                }


                throw error
            }
        }


        return tracks
    }


    // MARK: - Request

    private func request(
        _ url: URL
    ) async throws
        -> Data {

        let token =
            try await
            spotify.validAccessToken()


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


        guard let http =
            response
                as?
                HTTPURLResponse
        else {

            throw SpotifyAPIError
                .invalidResponse
        }


        try validateStatus(
            http.statusCode
        )


        return data
    }


    // MARK: - HTTP Status

    private func validateStatus(
        _ statusCode: Int
    ) throws {

        switch statusCode {

        case 200..<300:

            return


        case 401:

            throw SpotifyAPIError
                .unauthorized


        case 403:

            throw SpotifyAPIError
                .forbidden


        case 404:

            throw SpotifyAPIError
                .notFound


        case 429:

            throw SpotifyAPIError
                .rateLimited


        default:

            throw SpotifyAPIError
                .httpError(
                    statusCode
                )
        }
    }
}


// MARK: - Spotify API Error

enum SpotifyAPIError:
    LocalizedError {

    case notAuthenticated

    case unauthorized

    case forbidden

    case notFound

    case rateLimited

    case invalidResponse

    case playlistItemsUnavailable

    case httpError(
        Int
    )


    var errorDescription:
        String? {

        switch self {

        case .notAuthenticated:

            return
                "Spotify is not connected."


        case .unauthorized:

            return
                "Your Spotify authorization has expired. Reconnect Spotify and try again."


        case .forbidden:

            return
                "Spotify denied access to this content."


        case .notFound:

            return
                "Spotify could not find this content. It may have been removed or may not be available for your account."


        case .rateLimited:

            return
                "Spotify is temporarily limiting requests. Try again shortly."


        case .invalidResponse:

            return
                "Spotify returned an invalid response."


        case .playlistItemsUnavailable:

            return
                "Spotify does not allow Echo to access the songs in this playlist. This can happen with playlists owned by another account."


        case .httpError(
            let code
        ):

            return
                "Spotify request failed with HTTP \(code)."
        }
    }
}
