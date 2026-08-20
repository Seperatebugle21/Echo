import Foundation

@MainActor
final class SpotifyAPI {

    static let shared = SpotifyAPI()

    private let spotify = SpotifyManager.shared

    private init() {}

    // MARK: - Liked Songs

    func getLikedSongs() async throws -> [SpotifyTrack] {

        var result: [SpotifyTrack] = []

        var nextURL: URL? = URL(
            string:
                "https://api.spotify.com/v1/me/tracks?limit=50"
        )

        while let url = nextURL {

            let data = try await request(url)

            let response = try JSONDecoder().decode(
                SpotifySavedTracksResponse.self,
                from: data
            )

            let tracks = response.items.map { item in

                let track = item.track

                return SpotifyTrack(
                    id: track.id,
                    name: track.name,
                    artist: track.artists
                        .map(\.name)
                        .joined(separator: ", "),
                    album: track.album.name,
                    durationMS: track.durationMS,
                    artworkURL:
                        track.album.images.first?.url,
                    spotifyURL:
                        track.externalURLs.spotify
                )
            }

            result.append(contentsOf: tracks)

            if let next = response.next {
                nextURL = URL(string: next)
            } else {
                nextURL = nil
            }
        }

        return result
    }


    // MARK: - Playlists

    func getPlaylists() async throws -> [SpotifyPlaylist] {

        var result: [SpotifyPlaylist] = []

        var nextURL: URL? = URL(
            string:
                "https://api.spotify.com/v1/me/playlists?limit=50"
        )

        while let url = nextURL {

            let data = try await request(url)

            let response = try JSONDecoder().decode(
                SpotifyPlaylistsResponse.self,
                from: data
            )

            let playlists = response.items.map { playlist in

                SpotifyPlaylist(
                    id: playlist.id,
                    name: playlist.name,
                    artworkURL:
                        playlist.images.first?.url,
                    spotifyURL:
                        playlist.externalURLs.spotify,
                    trackCount:
                        playlist.trackCount
                )
            }

            result.append(contentsOf: playlists)

            if let next = response.next {
                nextURL = URL(string: next)
            } else {
                nextURL = nil
            }
        }

        return result
    }


    // MARK: - Request

    private func request(
        _ url: URL
    ) async throws -> Data {

        let token =
    try await spotify.validAccessToken()

        var request = URLRequest(url: url)

        request.setValue(
            "Bearer \(token)",
            forHTTPHeaderField: "Authorization"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        let (data, response) =
            try await URLSession.shared.data(for: request)

        guard let http =
            response as? HTTPURLResponse
        else {
            throw SpotifyAPIError.invalidResponse
        }

        guard 200..<300 ~= http.statusCode else {

            if http.statusCode == 401 {
                throw SpotifyAPIError.unauthorized
            }

            throw SpotifyAPIError.httpError(
                http.statusCode
            )
        }

        return data
    }
}


enum SpotifyAPIError: Error {
    case notAuthenticated
    case unauthorized
    case invalidResponse
    case httpError(Int)
}
