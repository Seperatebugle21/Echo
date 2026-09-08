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
                        "spotifylibraryview_search_spotify",
                        systemImage:
                            "magnifyingglass"
                    )
                }
            }

            Section(
                "spotifylibraryview_playlists"
            ) {

                if playlists.isEmpty &&
                    !isLoading
                {

                    Text(
                        "spotifylibraryview_no_playlists"
                    )
                    .foregroundStyle(
                        .secondary
                    )

                } else {

                    ForEach(
                        playlists
                    ) { playlist in

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

            Section(
                "spotifylibraryview_liked_songs"
            ) {

                if likedSongs.isEmpty &&
                    !isLoading
                {

                    Text(
                        "spotifylibraryview_no_liked_songs"
                    )
                    .foregroundStyle(
                        .secondary
                    )

                } else {

                    ForEach(
                        likedSongs
                    ) { track in

                        Button {

                            selectedTrack =
                                track

                        } label: {

                            SpotifyTrackRow(
                                track:
                                    track
                            )
                            .frame(
                                maxWidth:
                                    .infinity,
                                alignment:
                                    .leading
                            )
                            .contentShape(
                                Rectangle()
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
            "spotifylibraryview_title"
        )

        .overlay {

            if isLoading {

                ProgressView(
                    "spotifylibraryview_loading"
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
        ) { track in

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
        async
    {

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
                String(
                    format:
                        String(
                            localized:
                                "spotifylibraryview_error"
                        ),
                    error.localizedDescription
                )
        }

        isLoading =
            false
    }
}

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
            ) { image in

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
            ) { image in

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
                    String(
                        format:
                            String(
                                localized:
                                    "spotifylibraryview_songs_count"
                            ),
                        playlist.trackCount
                    )
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
