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

            if isLoading {

                HStack {

                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            if isFetchingPlaylist {

                Section {

                    HStack(
                        spacing: 12
                    ) {

                        ProgressView()

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {

                            Text(
                                "spotifyplaylistdetailview_adding_playlist"
                            )
                            .font(.headline)

                            Text(
                                String(
                                    format:
                                        String(
                                            localized:
                                                "spotifyplaylistdetailview_songs_count"
                                        ),
                                    tracks.count
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let errorMessage {

                Section {

                    Text(
                        errorMessage
                    )
                    .foregroundStyle(.red)
                }
            }

            if !isLoading &&
                errorMessage == nil &&
                tracks.isEmpty
            {

                ContentUnavailableView(
                    "spotifyplaylistdetailview_no_songs",
                    systemImage:
                        "music.note.list",
                    description:
                        Text(
                            "spotifyplaylistdetailview_no_songs_description"
                        )
                )
            }

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
                .buttonStyle(.plain)
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
                    "spotifyplaylistdetailview_fetch_entire_playlist"
                )
            }
        }

        .searchable(
            text:
                $searchText,
            prompt:
                "spotifyplaylistdetailview_search_in_playlist"
        )

        .task {

            await loadTracks()
        }

        .refreshable {

            await loadTracks()
        }

        .confirmationDialog(
            "spotifyplaylistdetailview_fetch_entire_playlist_confirmation",
            isPresented:
                $showFetchConfirmation,
            titleVisibility:
                .visible
        ) {

            Button(
                String(
                    format:
                        String(
                            localized:
                                "spotifyplaylistdetailview_fetch_songs"
                        ),
                    tracks.count
                )
            ) {

                fetchEntirePlaylist()
            }

            Button(
                "spotifyplaylistdetailview_cancel",
                role:
                    .cancel
            ) {}

        } message: {

            Text(
                "spotifyplaylistdetailview_fetch_entire_playlist_message"
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

    @MainActor
    private func loadTracks()
        async
    {

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

struct SpotifyPlaylistTrackRow: View {

    let track:
        SpotifyTrack

    var body: some View {

        HStack(
            spacing: 12
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
                    cornerRadius: 7
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
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(track.album)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }
}
