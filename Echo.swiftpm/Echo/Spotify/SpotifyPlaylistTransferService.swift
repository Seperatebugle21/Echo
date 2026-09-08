import Foundation

struct SpotifyPlaylistTransferResult {

    let existingSongCount: Int
    let queuedDownloadCount: Int
}

@MainActor
enum SpotifyPlaylistTransferService {

    static func transfer(
        playlist: SpotifyPlaylist,
        tracks: [SpotifyTrack]
    ) async -> SpotifyPlaylistTransferResult {

        let coverData =
            await loadPlaylistCover(
                from: playlist.artworkURL
            )

        let library =
            MusicLibraryManager.shared

        let echoPlaylist =
            library.createPlaylist(
                name: playlist.name,
                imageData: coverData
            )

        var missingTracks: [SpotifyTrack] = []
        var missingTrackPositions: [Int] = []

        for (position, track) in tracks.enumerated() {

            if let existingSong =
                library.songMatching(
                    title: track.name,
                    artist: track.artist
                ) {

                library.addSong(
                    existingSong,
                    toPlaylistID: echoPlaylist.id,
                    at: position
                )

            } else {

                missingTracks.append(track)
                missingTrackPositions.append(position)
            }
        }

        await FetchManager.shared
            .preparePlaylistTracks(
                missingTracks,
                destinationPlaylistID: echoPlaylist.id,
                destinationPositions: missingTrackPositions
            )

        return SpotifyPlaylistTransferResult(
            existingSongCount:
                tracks.count - missingTracks.count,
            queuedDownloadCount:
                missingTracks.count
        )
    }

    private static func loadPlaylistCover(
        from artworkURL: URL?
    ) async -> Data? {

        guard let artworkURL else {
            return nil
        }

        do {

            let (data, response) =
                try await URLSession.shared
                    .data(from: artworkURL)

            guard let httpResponse =
                response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode
            else {
                return nil
            }

            return data

        } catch {

            print(
                "Failed loading Spotify playlist cover:",
                error
            )

            return nil
        }
    }
}
