import SwiftUI


struct SongPickerView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @Environment(\.dismiss)
    private var dismiss


    let playlist: Playlist?
    let isFavorites: Bool


    @State private var searchText = ""

    @State private var selectedSongs:
        Set<UUID> = []

    @State private var editMode:
        EditMode = .active



    init(
        playlist: Playlist? = nil,
        isFavorites: Bool = false
    ) {

        self.playlist = playlist
        self.isFavorites = isFavorites
    }



    // MARK: - Current Playlist IDs

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



    // MARK: - Songs

    private var filteredSongs: [Song] {

        var songs = library.songs


        // Voor playlists tonen we alleen nummers
        // die nog niet in de playlist zitten.

        if !isFavorites {

            songs = songs.filter {

                !existingSongIDs
                    .contains($0.id)
            }
        }


        // Voor favorieten idem:
        // reeds favoriete nummers hoeven
        // niet opnieuw toegevoegd te worden.

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



    // MARK: - Body

    var body: some View {

        NavigationStack {

            List(
                selection:
                    $selectedSongs
            ) {


                // MARK: - Empty

                if filteredSongs.isEmpty {

                    ContentUnavailableView {

                        Label(
                            searchText.isEmpty
                            ?
                            "Geen nummers beschikbaar"
                            :
                            "Geen resultaten",
                            systemImage:
                                searchText.isEmpty
                                ?
                                "music.note"
                                :
                                "magnifyingglass"
                        )

                    } description: {

                        if searchText.isEmpty {

                            Text(
                                isFavorites
                                ?
                                "Alle beschikbare nummers staan al in je favorieten."
                                :
                                "Alle beschikbare nummers staan al in deze playlist."
                            )

                        } else {

                            Text(
                                "Geen nummers gevonden voor “\(searchText)”."
                            )
                        }
                    }

                    .selectionDisabled(
                        true
                    )

                } else {


                    // MARK: - Songs

                    ForEach(
                        filteredSongs
                    ) { song in

                        HStack(
                            spacing: 12
                        ) {


                            // MARK: Cover

                            SongArtworkView(
                                song: song,
                                cornerRadius: 10
                            )

                            .frame(
                                width: 52,
                                height: 52
                            )



                            // MARK: Info

                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {

                                Text(
                                    song.title
                                )
                                .font(.headline)
                                .foregroundStyle(
                                    .primary
                                )
                                .lineLimit(1)


                                Text(
                                    song.artist
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                                .lineLimit(1)
                            }


                            Spacer()
                        }

                        .padding(
                            .vertical,
                            3
                        )

                        .tag(
                            song.id
                        )
                    }
                }
            }


            // Hierdoor gebruikt List de native
            // multi-selection UI van iOS.

            .environment(
                \.editMode,
                $editMode
            )


            // MARK: Search

            .searchable(
                text: $searchText,
                placement:
                    .navigationBarDrawer(
                        displayMode:
                            .always
                    ),
                prompt:
                    Text(
                        "search_prompt"
                    )
            )


            // MARK: Title

            .navigationTitle(
                isFavorites
                ?
                LocalizedStringKey(
                    "picker_add_favorites_title"
                )
                :
                LocalizedStringKey(
                    "picker_add_songs_title"
                )
            )

            .navigationBarTitleDisplayMode(
                .inline
            )



            // MARK: Toolbar

            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarLeading
                ) {

                    Button(
                        LocalizedStringKey(
                            "action_cancel"
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
                                LocalizedStringKey(
                                    "action_add"
                                )
                            )

                        } else {

                            Text(
                                "Voeg toe (\(selectedSongs.count))"
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



            // MARK: Selection Bar

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
                                "\(selectedSongs.count) geselecteerd"
                            )
                            .font(
                                .headline
                            )


                            Text(
                                isFavorites
                                ?
                                "Worden toegevoegd aan Favorieten"
                                :
                                "Worden toegevoegd aan de playlist"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                        }


                        Spacer()


                        Button {

                            addSelectedSongs()

                        } label: {

                            Image(
                                systemName:
                                    "plus"
                            )
                            .font(
                                .headline
                            )

                            .frame(
                                width: 40,
                                height: 40
                            )
                        }

                        .buttonStyle(
                            .borderedProminent
                        )
                    }

                    .padding(
                        .horizontal
                    )

                    .padding(
                        .vertical,
                        10
                    )

                    .background(
                        .regularMaterial
                    )
                }
            }
        }
    }



    // MARK: - Add

    private func addSelectedSongs() {

        let songs =
            library.songs.filter {

                selectedSongs
                    .contains(
                        $0.id
                    )
            }


        if isFavorites {

            for song in songs {

                if
                    !library.isFavorite(
                        song
                    )
                {

                    library.toggleFavorite(
                        song
                    )
                }
            }

        } else if
            let playlist
        {

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
