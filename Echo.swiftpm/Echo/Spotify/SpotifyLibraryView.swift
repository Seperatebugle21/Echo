import SwiftUI

struct SpotifyLibraryView: View {

    @State private var likedSongs: [SpotifyTrack] = []
    @State private var playlists: [SpotifyPlaylist] = []

    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {

        List {

            // MARK: - Playlists

            Section("Playlists") {

                if playlists.isEmpty && !isLoading {

                    Text("No playlists")
                        .foregroundStyle(.secondary)

                } else {

                    ForEach(playlists) { playlist in

                        SpotifyPlaylistRow(
                            playlist: playlist
                        )
                    }
                }
            }


            // MARK: - Liked Songs

            Section("Liked Songs") {

                if likedSongs.isEmpty && !isLoading {

                    Text("No liked songs")
                        .foregroundStyle(.secondary)

                } else {

                    ForEach(likedSongs) { track in

                        SpotifyTrackRow(
                            track: track
                        )
                    }
                }
            }


            // MARK: - Error

            if let errorMessage {

                Section {

                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Spotify")
        .overlay {

            if isLoading {

                ProgressView("Loading Spotify…")
            }
        }
        .task {

            await loadLibrary()
        }
        .refreshable {

            await loadLibrary()
        }
    }


    // MARK: - Load

    private func loadLibrary() async {

        isLoading = true
        errorMessage = nil

        do {

            async let songs =
                SpotifyAPI.shared.getLikedSongs()

            async let userPlaylists =
                SpotifyAPI.shared.getPlaylists()

            let (
                loadedSongs,
                loadedPlaylists
            ) = try await (
                songs,
                userPlaylists
            )

            likedSongs = loadedSongs
            playlists = loadedPlaylists

        } catch {

            errorMessage =
                "Spotify error: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
