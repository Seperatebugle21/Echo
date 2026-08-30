import SwiftUI

struct SongPickerView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @Environment(\.dismiss)
    private var dismiss

    let playlist: Playlist?
    let isFavorites: Bool

    @State private var searchText = ""
    @State private var selectedSongs: Set<UUID> = []
    @State private var editMode: EditMode = .active

    init(
        playlist: Playlist? = nil,
        isFavorites: Bool = false
    ) {
        self.playlist = playlist
        self.isFavorites = isFavorites
    }

    private var existingSongIDs: Set<UUID> {

        guard
            let playlist,
            let currentPlaylist =
                library.playlists.first(
                    where: {
                        $0.id == playlist.id
                    }
                )
        else {
            return []
        }

        return Set(
            currentPlaylist.songIDs
        )
    }

    private var filteredSongs: [Song] {

        var songs = library.songs

        if !isFavorites {

            songs = songs.filter {
                !existingSongIDs.contains($0.id)
            }
        }

        if isFavorites {

            songs = songs.filter {
                !library.isFavorite($0)
            }
        }

        guard !searchText.isEmpty
        else {
            return songs
        }

        return songs.filter { song in

            song.title
                .localizedCaseInsensitiveContains(
                    searchText
                )

            ||

            song.artist
                .localizedCaseInsensitiveContains(
                    searchText
                )

            ||

            (
                song.album?
                    .localizedCaseInsensitiveContains(
                        searchText
                    )
                ?? false
            )
        }
    }

    var body: some View {

        NavigationStack {

            List(
                selection: $selectedSongs
            ) {

                if filteredSongs.isEmpty {

                    ContentUnavailableView {

                        Label(
                            searchText.isEmpty
                            ?
                            String(
                                localized:
                                    "songpickerview_no_songs_available"
                            )
                            :
                            String(
                                localized:
                                    "songpickerview_no_results"
                            ),
                            systemImage:
                                searchText.isEmpty
                                ? "music.note"
                                : "magnifyingglass"
                        )

                    } description: {

                        if searchText.isEmpty {

                            Text(
                                isFavorites
                                ?
                                "songpickerview_all_in_favorites"
                                :
                                "songpickerview_all_in_playlist"
                            )

                        } else {

                            Text(
                                String(
                                    format:
                                        String(
                                            localized:
                                                "songpickerview_no_results_for_query"
                                        ),
                                    searchText
                                )
                            )
                        }
                    }
                    .selectionDisabled(true)

                } else {

                    ForEach(
                        filteredSongs
                    ) { song in

                        HStack(
                            spacing: 12
                        ) {

                            SongArtworkView(
                                song: song,
                                cornerRadius: 10
                            )
                            .frame(
                                width: 52,
                                height: 52
                            )

                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {

                                Text(song.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 3)
                        .tag(song.id)
                    }
                }
            }

            .environment(
                \.editMode,
                $editMode
            )

            .searchable(
                text: $searchText,
                placement:
                    .navigationBarDrawer(
                        displayMode: .always
                    ),
                prompt:
                    Text(
                        "songpickerview_search_prompt"
                    )
            )

            .navigationTitle(
                isFavorites
                ?
                LocalizedStringKey(
                    "songpickerview_add_favorites_title"
                )
                :
                LocalizedStringKey(
                    "songpickerview_add_songs_title"
                )
            )

            .navigationBarTitleDisplayMode(
                .inline
            )

            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarLeading
                ) {

                    Button(
                        LocalizedStringKey(
                            "songpickerview_cancel"
                        )
                    ) {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {

                    Button {

                        addSelectedSongs()

                    } label: {

                        if selectedSongs.isEmpty {

                            Text(
                                "songpickerview_add"
                            )

                        } else {

                            Text(
                                String(
                                    format:
                                        String(
                                            localized:
                                                "songpickerview_add_selected"
                                        ),
                                    selectedSongs.count
                                )
                            )
                            .fontWeight(
                                .semibold
                            )
                        }
                    }
                    .disabled(
                        selectedSongs.isEmpty
                    )
                }
            }

            .safeAreaInset(
                edge: .bottom
            ) {

                if !selectedSongs.isEmpty {

                    HStack(
                        spacing: 12
                    ) {

                        Image(
                            systemName:
                                "checkmark.circle.fill"
                        )
                        .font(.title2)

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {

                            Text(
                                String(
                                    format:
                                        String(
                                            localized:
                                                "songpickerview_selected_count"
                                        ),
                                    selectedSongs.count
                                )
                            )
                            .font(.headline)

                            Text(
                                isFavorites
                                ?
                                "songpickerview_add_to_favorites"
                                :
                                "songpickerview_add_to_playlist"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            addSelectedSongs()
                        } label: {

                            Image(
                                systemName: "plus"
                            )
                            .font(.headline)
                            .frame(
                                width: 40,
                                height: 40
                            )
                        }
                        .buttonStyle(
                            .borderedProminent
                        )
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(
                        .regularMaterial
                    )
                }
            }
        }
    }

    private func addSelectedSongs() {

        let songs =
            library.songs.filter {
                selectedSongs.contains($0.id)
            }

        if isFavorites {

            for song in songs {

                if !library.isFavorite(song) {
                    library.toggleFavorite(song)
                }
            }

        } else if let playlist {

            for song in songs {
                library.addSong(
                    song,
                    to: playlist
                )
            }
        }

        dismiss()
    }
}
