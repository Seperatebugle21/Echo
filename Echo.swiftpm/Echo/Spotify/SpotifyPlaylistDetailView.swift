import SwiftUI


struct SpotifyPlaylistDetailView: View {

    let playlist:
        SpotifyPlaylist


    @State private var tracks:
        [SpotifyTrack] = []

    @State private var isLoading =
        false

    @State private var errorMessage:
        String?

    @State private var searchText =
        ""

    @State private var selectedTrack:
        SpotifyTrack?

    @State private var isFetchingPlaylist =
        false

    @State private var showFetchConfirmation =
        false


    var filteredTracks:
        [SpotifyTrack] {

        guard !searchText.isEmpty else {

            return tracks
        }


        return tracks.filter { track in

            track.name
                .localizedCaseInsensitiveContains(
                    searchText
                )

            ||

            track.artist
                .localizedCaseInsensitiveContains(
                    searchText
                )

            ||

            track.album
                .localizedCaseInsensitiveContains(
                    searchText
                )
        }
    }


    var body: some View {

        List {

            // MARK: - Loading

            if isLoading {

                HStack {

                    Spacer()

                    ProgressView()

                    Spacer()
                }
            }


            // MARK: - Preparing Playlist

            if isFetchingPlaylist {

                Section {

                    HStack(
                        spacing:
                            12
                    ) {

                        ProgressView()


                        VStack(
                            alignment:
                                .leading,
                            spacing:
                                3
                        ) {

                            Text(
                                "Adding playlist to Fetch"
                            )
                            .font(
                                .headline
                            )


                            Text(
                                "\(tracks.count) songs"
                            )
                            .font(
                                .caption
                            )
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }
                }
            }


            // MARK: - Error

            if let errorMessage {

                Section {

                    Text(
                        errorMessage
                    )
                    .foregroundStyle(
                        .red
                    )
                }
            }


            // MARK: - Empty

            if !isLoading &&
                errorMessage == nil &&
                tracks.isEmpty {

                ContentUnavailableView(
                    "No Songs",
                    systemImage:
                        "music.note.list",
                    description:
                        Text(
                            "No songs were found in this playlist."
                        )
                )
            }


            // MARK: - Tracks

            ForEach(
                filteredTracks
            ) { track in

                Button {

                    selectedTrack =
                        track

                } label: {

                    SpotifyPlaylistTrackRow(
                        track:
                            track
                    )
                }
                .buttonStyle(
                    .plain
                )
            }
        }

        .navigationTitle(
            playlist.name
        )

        .navigationBarTitleDisplayMode(
            .inline
        )

        .toolbar {

            ToolbarItem(
                placement:
                    .topBarTrailing
            ) {

                Button {

                    showFetchConfirmation =
                        true

                } label: {

                    if isFetchingPlaylist {

                        ProgressView()
                            .controlSize(
                                .small
                            )

                    } else {

                        Image(
                            systemName:
                                "arrow.down.circle"
                        )
                    }
                }
                .disabled(
                    isLoading
                    ||
                    isFetchingPlaylist
                    ||
                    tracks.isEmpty
                )
                .accessibilityLabel(
                    "Fetch Entire Playlist"
                )
            }
        }

        .searchable(
            text:
                $searchText,
            prompt:
                "Search in playlist"
        )

        .task {

            await loadTracks()
        }

        .refreshable {

            await loadTracks()
        }

        .confirmationDialog(
            "Fetch Entire Playlist?",
            isPresented:
                $showFetchConfirmation,
            titleVisibility:
                .visible
        ) {

            Button(
                "Fetch \(tracks.count) Songs"
            ) {

                fetchEntirePlaylist()
            }


            Button(
                "Cancel",
                role:
                    .cancel
            ) {}

        } message: {

            Text(
                "Every song will be added to Fetch and processed one after another."
            )
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


    // MARK: - Fetch Entire Playlist

    @MainActor
    private func fetchEntirePlaylist() {

        guard !isFetchingPlaylist else {

            return
        }


        guard !tracks.isEmpty else {

            return
        }


        isFetchingPlaylist =
            true

        errorMessage =
            nil


        let playlistTracks =
            tracks


        Task {

            await FetchManager.shared
                .preparePlaylistTracks(
                    playlistTracks
                )


            isFetchingPlaylist =
                false


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


    // MARK: - Load Tracks

    @MainActor
    private func loadTracks()
        async {

        guard !isLoading else {

            return
        }


        isLoading =
            true

        errorMessage =
            nil


        do {

            tracks =
                try await
                SpotifyAPI.shared
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


        isLoading =
            false
    }
}


// MARK: - Track Row

struct SpotifyPlaylistTrackRow: View {

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

                RoundedRectangle(
                    cornerRadius:
                        7
                )
                .fill(
                    .secondary.opacity(
                        0.15
                    )
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
                width:
                    50,
                height:
                    50
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius:
                        7
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
