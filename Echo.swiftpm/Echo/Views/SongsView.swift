import SwiftUI
import UniformTypeIdentifiers


enum SongSortOption:
    String,
    CaseIterable
{
    case name =
        "sort_name"

    case dateAdded =
        "sort_date_added"

    case lastPlayed =
        "sort_last_played"
}



struct SelectedSongsSheetItem:
    Identifiable
{
    let id = UUID()
    let songs: [Song]
}



struct SongsView: View {

    @Environment(MusicLibraryManager.self)
    private var library

    @Environment(AudioPlayerManager.self)
    private var audioPlayer

    @Environment(\.dismiss)
    private var dismiss


    @State private var showImporter = false
    @State private var searchText = ""
    @State private var sortOption:
        SongSortOption = .name

    @State private var selectedSong: Song?


    // MARK: Selection

    @State private var editMode:
        EditMode = .inactive

    @State private var selectedSongIDs =
        Set<Song.ID>()

    @State private var showDeleteConfirmation =
        false


    // MARK: Playlist Sheet

    @State private var playlistSheetItem:
        SelectedSongsSheetItem?


    // MARK: Import Progress

    @State private var isImporting =
        false

    @State private var importProgress =
        0

    @State private var importTotal =
        0



    // MARK: - Filtering

    var filteredSongs: [Song] {

        if searchText.isEmpty {

            return library.songs
        }


        return library.songs.filter {

            $0.title
                .localizedCaseInsensitiveContains(
                    searchText
                )

            ||

            $0.artist
                .localizedCaseInsensitiveContains(
                    searchText
                )
        }
    }



    // MARK: - Sorting

    var sortedSongs: [Song] {

        switch sortOption {

        case .name:

            return filteredSongs.sorted {

                $0.title
                    .localizedCaseInsensitiveCompare(
                        $1.title
                    )
                ==
                .orderedAscending
            }


        case .dateAdded:

            return filteredSongs.sorted {

                $0.dateAdded >
                $1.dateAdded
            }


        case .lastPlayed:

            return filteredSongs.sorted {

                ($0.lastPlayed ?? .distantPast)
                >
                ($1.lastPlayed ?? .distantPast)
            }
        }
    }



    // MARK: - Body

    var body: some View {

        NavigationStack {

            List(
                selection:
                    $selectedSongIDs
            ) {

                ForEach(
                    sortedSongs
                ) { song in

                    HStack(
                        spacing: 12
                    ) {


                        // MARK: Artwork

                        if
                            let data =
                                song.coverData,
                            let image =
                                UIImage(
                                    data: data
                                )
                        {

                            Image(
                                uiImage: image
                            )
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: 50,
                                height: 50
                            )
                            .clipped()
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 10
                                )
                            )

                        } else {

                            Image(
                                systemName:
                                    "music.note"
                            )
                            .font(.title2)
                            .frame(
                                width: 50,
                                height: 50
                            )
                            .background(
                                .thinMaterial
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 10
                                )
                            )
                        }



                        // MARK: Title

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {

                            Text(song.title)
                                .font(.headline)
                                .foregroundStyle(
                                    .primary
                                )
                                .lineLimit(1)


                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                                .lineLimit(1)
                        }


                        Spacer()



                        // MARK: More

                        if
                            editMode
                            ==
                            .inactive
                        {

                            Button {

                                selectedSong =
                                    song

                            } label: {

                                Image(
                                    systemName:
                                        "ellipsis"
                                )
                                .font(.title3)
                                .foregroundStyle(
                                    .secondary
                                )
                                .frame(
                                    width: 30,
                                    height: 30
                                )
                            }

                            .buttonStyle(
                                .plain
                            )
                        }
                    }

                    .contentShape(
                        Rectangle()
                    )


                    // MARK: Play Song

                    .onTapGesture {

                        guard
                            editMode
                            ==
                            .inactive
                        else {

                            return
                        }


                        if
                            let url =
                                library.getURL(
                                    for: song
                                )
                        {

                            library.markAsPlayed(
                                song
                            )


                            audioPlayer.lastPlaybackDirection =
                                .fade


                            audioPlayer.play(
                                song: song,
                                url: url,
                                queue: [song]
                            )


                            audioPlayer.allSongs =
                                library.songs


                            audioPlayer.fillAutoNext(
                                from:
                                    library.songs
                            )
                        }
                    }


                    // MARK: Favorite

                    .swipeActions(
                        edge: .trailing,
                        allowsFullSwipe: true
                    ) {

                        Button {

                            library.toggleFavorite(
                                song
                            )

                        } label: {

                            Label(
                                library.isFavorite(
                                    song
                                )
                                ?
                                LocalizedStringKey(
                                    "action_remove"
                                )
                                :
                                LocalizedStringKey(
                                    "action_favorite"
                                ),

                                systemImage:
                                    library.isFavorite(
                                        song
                                    )
                                    ?
                                    "heart.slash"
                                    :
                                    "heart.fill"
                            )
                        }

                        .tint(.red)
                    }
                }
            }


            .environment(
                \.editMode,
                $editMode
            )


            .navigationTitle(
                LocalizedStringKey(
                    "songs_title"
                )
            )


            .searchable(
                text: $searchText,
                prompt:
                    Text(
                        "search_prompt"
                    )
            )



            // MARK: Toolbar

            .toolbar {


                // MARK: Leading

                ToolbarItemGroup(
                    placement:
                        .topBarLeading
                ) {

                    Button {

                        dismiss()

                    } label: {

                        Image(
                            systemName:
                                "chevron.left"
                        )
                    }


                    Button(
                        editMode == .active
                        ?
                        LocalizedStringKey(
                            "action_done"
                        )
                        :
                        LocalizedStringKey(
                            "action_edit"
                        )
                    ) {

                        withAnimation {

                            if
                                editMode
                                ==
                                .active
                            {

                                editMode =
                                    .inactive

                                selectedSongIDs
                                    .removeAll()

                            } else {

                                editMode =
                                    .active
                            }
                        }
                    }
                }



                // MARK: Editing Actions

                if
                    editMode
                    ==
                    .active
                {

                    ToolbarItemGroup(
                        placement:
                            .topBarTrailing
                    ) {

                        Button {

                            let songsToAdd =
                                library.songs
                                    .filter {

                                        selectedSongIDs
                                            .contains(
                                                $0.id
                                            )
                                    }


                            playlistSheetItem =
                                SelectedSongsSheetItem(
                                    songs:
                                        songsToAdd
                                )

                        } label: {

                            Image(
                                systemName:
                                    "music.note.list"
                            )
                        }

                        .disabled(
                            selectedSongIDs
                                .isEmpty
                        )


                        Button(
                            role:
                                .destructive
                        ) {

                            showDeleteConfirmation =
                                true

                        } label: {

                            Image(
                                systemName:
                                    "trash"
                            )
                        }

                        .tint(.red)

                        .disabled(
                            selectedSongIDs
                                .isEmpty
                        )
                    }

                } else {


                    // MARK: Normal Actions

                    ToolbarItemGroup(
                        placement:
                            .topBarTrailing
                    ) {

                        Menu {

                            Button {

                                sortOption =
                                    .name

                            } label: {

                                Label(
                                    LocalizedStringKey(
                                        "sort_name"
                                    ),
                                    systemImage:
                                        sortOption
                                        ==
                                        .name
                                        ?
                                        "checkmark"
                                        :
                                        ""
                                )
                            }


                            Button {

                                sortOption =
                                    .dateAdded

                            } label: {

                                Label(
                                    LocalizedStringKey(
                                        "sort_date_added"
                                    ),
                                    systemImage:
                                        sortOption
                                        ==
                                        .dateAdded
                                        ?
                                        "checkmark"
                                        :
                                        ""
                                )
                            }


                            Button {

                                sortOption =
                                    .lastPlayed

                            } label: {

                                Label(
                                    LocalizedStringKey(
                                        "sort_last_played"
                                    ),
                                    systemImage:
                                        sortOption
                                        ==
                                        .lastPlayed
                                        ?
                                        "checkmark"
                                        :
                                        ""
                                )
                            }

                        } label: {

                            Image(
                                systemName:
                                    "arrow.up.arrow.down.circle"
                            )
                        }


                        Button {

                            showImporter =
                                true

                        } label: {

                            Image(
                                systemName:
                                    "plus"
                            )
                        }

                        .disabled(
                            isImporting
                        )
                    }
                }
            }



            // MARK: File Importer

            .fileImporter(
                isPresented:
                    $showImporter,
                allowedContentTypes: [
                    .audio
                ],
                allowsMultipleSelection:
                    true
            ) { result in

                switch result {

                case .success(
                    let files
                ):

                    Task {

                        await MainActor.run {

                            importTotal =
                                files.count

                            importProgress =
                                0

                            isImporting =
                                true
                        }


                        for file in files {

                            library.importSong(
                                from: file
                            )


                            await MainActor.run {

                                importProgress +=
                                    1
                            }


                            try?
                                await Task.sleep(
                                    nanoseconds:
                                        10_000_000
                                )
                        }


                        await MainActor.run {

                            isImporting =
                                false
                        }
                    }


                case .failure(
                    let error
                ):

                    print(
                        "Import fout:",
                        error.localizedDescription
                    )
                }
            }



            // MARK: Loading Overlay

            .overlay {

                if isImporting {

                    ZStack {

                        Color.black
                            .opacity(0.4)
                            .ignoresSafeArea()


                        VStack(
                            spacing: 16
                        ) {

                            ProgressView(
                                value:
                                    Double(
                                        importProgress
                                    ),
                                total:
                                    Double(
                                        importTotal
                                    )
                            )
                            .progressViewStyle(
                                .circular
                            )
                            .scaleEffect(1.5)


                            VStack(
                                spacing: 4
                            ) {

                                Text(
                                    "Nummers importeren..."
                                )
                                .font(.headline)


                                Text(
                                    "\(importProgress) van \(importTotal) geüpload"
                                )
                                .font(
                                    .subheadline
                                )
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                        }

                        .padding(24)

                        .background(
                            .regularMaterial
                        )

                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 16
                            )
                        )

                        .shadow(
                            radius: 10
                        )
                    }

                    .transition(
                        .opacity
                    )
                }
            }



            // MARK: Delete

            .alert(
                LocalizedStringKey(
                    "alert_delete_songs_title"
                ),
                isPresented:
                    $showDeleteConfirmation
            ) {

                Button(
                    LocalizedStringKey(
                        "action_delete"
                    ),
                    role: .destructive
                ) {

                    let songsToDelete =
                        library.songs
                            .filter {

                                selectedSongIDs
                                    .contains(
                                        $0.id
                                    )
                            }


                    for song
                        in songsToDelete
                    {

                        library.deleteSong(
                            song
                        )
                    }


                    selectedSongIDs
                        .removeAll()

                    editMode =
                        .inactive
                }


                Button(
                    LocalizedStringKey(
                        "action_cancel"
                    ),
                    role: .cancel
                ) {}

            } message: {

                Text(
                    "alert_delete_songs_message \(selectedSongIDs.count)"
                )
            }



            // MARK: Duplicate

            .alert(
                Text(
                    "alert_duplicate_title"
                ),
                isPresented:
                    Bindable(
                        library
                    )
                    .showDuplicateAlert
            ) {

                Button(
                    String(
                        localized:
                            "action_skip"
                    )
                ) {

                    library.resolveDuplicate(
                        choice: .skip,
                        applyToAll: false
                    )
                }


                Button(
                    String(
                        localized:
                            "action_replace"
                    ),
                    role: .destructive
                ) {

                    library.resolveDuplicate(
                        choice: .replace,
                        applyToAll: false
                    )
                }


                Button(
                    String(
                        localized:
                            "action_skip_all"
                    )
                ) {

                    library.resolveDuplicate(
                        choice: .skip,
                        applyToAll: true
                    )
                }


                Button(
                    String(
                        localized:
                            "action_replace_all"
                    ),
                    role: .destructive
                ) {

                    library.resolveDuplicate(
                        choice: .replace,
                        applyToAll: true
                    )
                }


                Button(
                    String(
                        localized:
                            "action_cancel"
                    ),
                    role: .cancel
                ) {}

            } message: {

                Text(
                    "alert_duplicate_message \(library.duplicateSongName)"
                )
            }



            // MARK: Sheets

            .sheet(
                item:
                    Bindable(
                        library
                    )
                    .songToAddToPlaylist
            ) { song in

                PlaylistPickerView(
                    songs: [song]
                )
            }


            .sheet(
                item:
                    $playlistSheetItem,
                onDismiss: {

                    withAnimation {

                        editMode =
                            .inactive

                        selectedSongIDs
                            .removeAll()
                    }
                }
            ) { item in

                PlaylistPickerView(
                    songs: item.songs
                )
            }


            .sheet(
                item: $selectedSong
            ) { song in

                SongOptionsView(
                    song: song
                )
            }


            .sheet(
                isPresented:
                    Bindable(
                        library
                    )
                    .showEditSheet
            ) {

                if
                    let song =
                        library.editingSong
                {

                    EditSongView(
                        song: song
                    )
                }
            }
        }
    }
}
