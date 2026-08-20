import SwiftUI

struct SpotifyPlaylistDetailView: View {

    let playlist: SpotifyPlaylist

    @State private var tracks: [SpotifyTrack] = []

    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var searchText = ""

    var filteredTracks: [SpotifyTrack] {

        guard !searchText.isEmpty else {
            return tracks
        }

        return tracks.filter { track in

            track.name.localizedCaseInsensitiveContains(
                searchText
            )
            ||
            track.artist.localizedCaseInsensitiveContains(
                searchText
            )
            ||
            track.album.localizedCaseInsensitiveContains(
                searchText
            )
        }
    }


    var body: some View {

        List {

            if isLoading {

                HStack {

                    Spacer()

                    ProgressView()

                    Spacer()
                }
            }


            if let errorMessage {

                Section {

                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }


            if !isLoading &&
                errorMessage == nil &&
                tracks.isEmpty {

                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note.list",
                    description:
                        Text(
                            "No songs were found in this playlist."
                        )
                )
            }


            ForEach(filteredTracks) { track in

              
                                     
                                     
                NavigationLink {

                SpotifyFetchButton(
                 track: track
               ) 

                } label: {

                    SpotifyPlaylistTrackRow(
                        track: track
                    )
                }
            }
        }
        .navigationTitle(
            playlist.name
        )
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: "Search in playlist"
        )
        .task {
            await loadTracks()
        }
        .refreshable {
            await loadTracks()
        }
    }


    @MainActor
    private func loadTracks() async {

        guard !isLoading else {
            return
        }

        isLoading = true
        errorMessage = nil

        do {

            tracks =
                try await SpotifyAPI.shared
                    .getPlaylistTracks(
                        playlistID:
                            playlist.id
                    )

        } catch {

            errorMessage =
                error.localizedDescription

            print(
                "Failed loading playlist:",
                playlist.name,
                error
            )
        }

        isLoading = false
    }
}



struct SpotifyPlaylistTrackRow: View {

    let track: SpotifyTrack

    var body: some View {

        HStack(spacing: 12) {

            AsyncImage(
                url: track.artworkURL
            ) { image in

                image
                    .resizable()
                    .scaledToFill()

            } placeholder: {

                RoundedRectangle(
                    cornerRadius: 7
                )
                .fill(
                    .secondary.opacity(0.15)
                )
                .overlay {

                    Image(
                        systemName:
                            "music.note"
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }
            }
            .frame(
                width: 50,
                height: 50
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 7
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
                    .foregroundStyle(
                        .secondary
                    )
                    .lineLimit(1)

                Text(track.album)
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                    .lineLimit(1)
            }
        }
    }
}
