import SwiftUI


struct SpotifyLibraryView: View {

    @State private var likedSongs:
        [SpotifyTrack] = []

    @State private var playlists:
        [SpotifyPlaylist] = []


    @State private var isLoading =
        false

    @State private var errorMessage:
        String?


    @State private var selectedTrack:
        SpotifyTrack?


    var body: some View {

        List {

            Section {

                NavigationLink {

                    SpotifySearchView()

                } label: {

                    Label(
                        "Search Spotify",
                        systemImage:
                            "magnifyingglass"
                    )
                }
            }


            // MARK: - Playlists

            Section(
                "Playlists"
            ) {

                if playlists.isEmpty &&
                    !isLoading {

                    Text(
                        "No playlists"
                    )
                    .foregroundStyle(
                        .secondary
                    )

                } else {

                    ForEach(
                        playlists
                    ) {
                        playlist in


                        NavigationLink {

                            SpotifyPlaylistDetailView(
                                playlist:
                                    playlist
                            )

                        } label: {

                            SpotifyPlaylistRow(
                                playlist:
                                    playlist
                            )
                        }
                    }
                }
            }


            // MARK: - Liked Songs

            Section(
                "Liked Songs"
            ) {

                if likedSongs.isEmpty &&
                    !isLoading {

                    Text(
                        "No liked songs"
                    )
                    .foregroundStyle(
                        .secondary
                    )

                } else {

                    ForEach(
                        likedSongs
                    ) {
                        track in


                        Button {

                            selectedTrack =
                                track

                        } label: {

                            SpotifyTrackRow(
                                track:
                                    track
                            )
                        }
                        .buttonStyle(
                            .plain
                        )
                    }
                }
            }


            if let errorMessage {

                Section {

                    Text(
                        errorMessage
                    )
                    .foregroundStyle(
                        .red
                    )
                    .font(
                        .caption
                    )
                }
            }
        }

        .navigationTitle(
            "Spotify"
        )

        .overlay {

            if isLoading {

                ProgressView(
                    "Loading Spotify…"
                )
            }
        }

        .task {

            await loadLibrary()
        }

        .refreshable {

            await loadLibrary()
        }

        .sheet(
            item:
                $selectedTrack
        ) {
            track in


            SpotifyTrackDetailView(

                track:
                    track,

                onClose: {

                    selectedTrack =
                        nil
                },

                onViewDownloads: {

                    selectedTrack =
                        nil


                    DispatchQueue.main.async {

                        NotificationCenter
                            .default
                            .post(
                                name:
                                    .echoOpenFetchDownloads,
                                object:
                                    nil
                            )
                    }
                }
            )
        }
    }


    private func loadLibrary()
        async {

        isLoading =
            true

        errorMessage =
            nil


        do {

            async let songs =
                SpotifyAPI.shared
                    .getLikedSongs()


            async let userPlaylists =
                SpotifyAPI.shared
                    .getPlaylists()


            let (
                loadedSongs,
                loadedPlaylists
            ) =
                try await (
                    songs,
                    userPlaylists
                )


            likedSongs =
                loadedSongs

            playlists =
                loadedPlaylists


        } catch {

            errorMessage =
                "Spotify error: \(error.localizedDescription)"
        }


        isLoading =
            false
    }
}


// MARK: - Track Row

struct SpotifyTrackRow: View {

    let track:
        SpotifyTrack


    var body: some View {

        HStack(
            spacing:
                12
        ) {

            AsyncImage(
                url:
                    track.artworkURL
            ) {
                image in

                image
                    .resizable()
                    .scaledToFill()

            } placeholder: {

                Image(
                    systemName:
                        "music.note"
                )
                .foregroundStyle(
                    .secondary
                )
            }
            .frame(
                width:
                    52,
                height:
                    52
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius:
                        8
                )
            )


            VStack(
                alignment:
                    .leading,
                spacing:
                    3
            ) {

                Text(
                    track.name
                )
                .font(
                    .headline
                )
                .foregroundStyle(
                    .primary
                )
                .lineLimit(
                    1
                )


                Text(
                    track.artist
                )
                .font(
                    .subheadline
                )
                .foregroundStyle(
                    .secondary
                )
                .lineLimit(
                    1
                )


                Text(
                    track.album
                )
                .font(
                    .caption
                )
                .foregroundStyle(
                    .secondary
                )
                .lineLimit(
                    1
                )
            }


            Spacer()


            Image(
                systemName:
                    "chevron.right"
            )
            .font(
                .caption
            )
            .foregroundStyle(
                .tertiary
            )
        }
    }
}


// MARK: - Playlist Row

struct SpotifyPlaylistRow: View {

    let playlist:
        SpotifyPlaylist


    var body: some View {

        HStack(
            spacing:
                12
        ) {

            AsyncImage(
                url:
                    playlist.artworkURL
            ) {
                image in

                image
                    .resizable()
                    .scaledToFill()

            } placeholder: {

                Image(
                    systemName:
                        "music.note.list"
                )
                .foregroundStyle(
                    .secondary
                )
            }
            .frame(
                width:
                    52,
                height:
                    52
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius:
                        8
                )
            )


            VStack(
                alignment:
                    .leading,
                spacing:
                    3
            ) {

                Text(
                    playlist.name
                )
                .font(
                    .headline
                )
                .lineLimit(
                    1
                )


                Text(
                    "\(playlist.trackCount) songs"
                )
                .font(
                    .subheadline
                )
                .foregroundStyle(
                    .secondary
                )
            }
        }
    }
}
