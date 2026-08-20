import SwiftUI

struct SpotifyLibraryView: View {

    @State private var likedSongs: [SpotifyTrack] = []
    @State private var playlists: [SpotifyPlaylist] = []

    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {

        List {

            Section {

    NavigationLink {
        SpotifySearchView()
    } label: {

        Label(
            "Search Spotify",
            systemImage: "magnifyingglass"
        )
    }
}

            // MARK: - Playlists

            Section("Playlists") {

                if playlists.isEmpty && !isLoading {

                    Text("No playlists")
                        .foregroundStyle(.secondary)

                } else {

                   ForEach(playlists) { playlist in

    NavigationLink {
        SpotifyPlaylistDetailView(
            playlist: playlist
        )
    } label: {

        SpotifyPlaylistRow(
            playlist: playlist
        )
    }
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

        } catch let DecodingError.keyNotFound(key, context) {

    errorMessage =
        "Spotify mist veld '\(key.stringValue)' — \(context.debugDescription)"

    print("Spotify decoding keyNotFound:", key.stringValue)
    print(context)

} catch let DecodingError.typeMismatch(type, context) {

    errorMessage =
        "Spotify typefout bij \(type): \(context.debugDescription)"

    print("Spotify typeMismatch:", type)
    print(context)

} catch let DecodingError.valueNotFound(type, context) {

    errorMessage =
        "Spotify lege waarde bij \(type): \(context.debugDescription)"

    print("Spotify valueNotFound:", type)
    print(context)

} catch {

    errorMessage =
        "Spotify error: \(error.localizedDescription)"

    print("Spotify error:", error)
}

        isLoading = false
    }
}


struct SpotifyTrackRow: View {

    let track: SpotifyTrack

    @State private var fetch =
        FetchManager.shared

    var body: some View {

        HStack(spacing: 12) {

            AsyncImage(
                url: track.artworkURL
            ) { image in

                image
                    .resizable()
                    .scaledToFill()

            } placeholder: {

                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
            .frame(
                width: 52,
                height: 52
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 8
                )
            )


            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                Text(track.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }


            Spacer()


            Menu {

                  SpotifyFetchButton(
                     track: track
                )

            } label: {

                Image(
                    systemName: "ellipsis"
                )
                .frame(
                    width: 32,
                    height: 32
                )
            }
        }
    }
}


struct SpotifyPlaylistRow: View {

    let playlist: SpotifyPlaylist

    @State private var fetch =
        FetchManager.shared

    var body: some View {

        HStack(spacing: 12) {

            AsyncImage(
                url: playlist.artworkURL
            ) { image in

                image
                    .resizable()
                    .scaledToFill()

            } placeholder: {

                Image(
                    systemName:
                        "music.note.list"
                )
                .foregroundStyle(.secondary)
            }
            .frame(
                width: 52,
                height: 52
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 8
                )
            )


            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                Text(playlist.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(
                    "\(playlist.trackCount) songs"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }


            Spacer()


            /*
           Menu {
   Button {
    Task {
        do {
            try await FetchManager.shared
                .preparePlaylist(playlist)
        } catch {
            print(
                "Playlist fetch failed:",
                error
            )
        }
    }
} label: {
    Label(
        "Fetch Playlist",
        systemImage: "arrow.down.circle.fill"
    )
}
} label: {
    Image(systemName: "ellipsis")
}
            */
            
        }
    }
}
