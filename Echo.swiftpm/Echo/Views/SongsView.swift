import SwiftUI
import UniformTypeIdentifiers

enum SongSortOption:
    String,
    CaseIterable
{
    case name =
        "songsview_sort_name"

    case dateAdded =
        "songsview_sort_date_added"

    case lastPlayed =
        "songsview_sort_last_played"
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

    @State private var showImporter = false
    @State private var searchText = ""
    @State private var sortOption:
        SongSortOption = .name

    @State private var selectedSong:
        Song?

    @State private var editMode:
        EditMode = .inactive

    @State private var selectedSongIDs =
        Set<Song.ID>()

    @State private var showDeleteConfirmation =
        false

    @State private var playlistSheetItem:
        SelectedSongsSheetItem?

    @State private var isImporting = false
    @State private var importProgress = 0
    @State private var importTotal = 0

    private var filteredSongs: [Song] {

        guard !searchText.isEmpty
        else {
            return library.songs
        }

        return library.songs.filter { song in

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

    private var sortedSongs: [Song] {

        switch sortOption {

        case .name:

            return filteredSongs.sorted {
                $0.title
                    .localizedCaseInsensitiveCompare(
                        $1.title
                    )
                == .orderedAscending
            }

        case .dateAdded:

            return filteredSongs.sorted {
                $0.dateAdded > $1.dateAdded
            }

        case .lastPlayed:

            return filteredSongs.sorted {
                ($0.lastPlayed ?? .distantPast)
                >
                ($1.lastPlayed ?? .distantPast)
            }
        }
    }

    var body: some View {

        List(
            selection: $selectedSongIDs
        ) {

            ForEach(
                sortedSongs
            ) { song in

                songRow(song)
            }

            Color.clear
                .frame(height: 105)
                .listRowBackground(
                    Color.clear
                )
                .listRowSeparator(
                    .hidden
                )
        }

        .environment(
            \.editMode,
            $editMode
        )

        .navigationTitle(
            LocalizedStringKey(
                "songsview_title"
            )
        )

        .navigationBarTitleDisplayMode(
            .large
        )

        .searchable(
            text: $searchText,
            placement:
                .navigationBarDrawer(
                    displayMode: .always
                ),
            prompt:
                Text(
                    "songsview_search_prompt"
                )
        )

        .toolbar {

            ToolbarItem(
                placement: .topBarLeading
            ) {

                Button(
                    editMode == .active
                    ?
                    LocalizedStringKey(
                        "songsview_done"
                    )
                    :
                    LocalizedStringKey(
                        "songsview_edit"
                    )
                ) {

                    withAnimation {

                        if editMode == .active {

                            editMode = .inactive
                            selectedSongIDs.removeAll()

                        } else {

                            editMode = .active
                        }
                    }
                }
            }

            if editMode == .active {

                ToolbarItemGroup(
                    placement:
                        .topBarTrailing
                ) {

                    Button {

                        let songsToAdd =
                            library.songs.filter {
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
                        selectedSongIDs.isEmpty
                    )

                    Button(
                        role: .destructive
                    ) {

                        showDeleteConfirmation = true

                    } label: {

                        Image(
                            systemName: "trash"
                        )
                    }
                    .tint(.red)
                    .disabled(
                        selectedSongIDs.isEmpty
                    )
                }

            } else {

                ToolbarItemGroup(
                    placement:
                        .topBarTrailing
                ) {

                    Menu {

                        Button {

                            sortOption = .name

                        } label: {

                            Label(
                                LocalizedStringKey(
                                    "songsview_sort_name"
                                ),
                                systemImage:
                                    sortOption == .name
                                    ? "checkmark"
                                    : ""
                            )
                        }

                        Button {

                            sortOption = .dateAdded

                        } label: {

                            Label(
                                LocalizedStringKey(
                                    "songsview_sort_date_added"
                                ),
                                systemImage:
                                    sortOption == .dateAdded
                                    ? "checkmark"
                                    : ""
                            )
                        }

                        Button {

                            sortOption = .lastPlayed

                        } label: {

                            Label(
                                LocalizedStringKey(
                                    "songsview_sort_last_played"
                                ),
                                systemImage:
                                    sortOption == .lastPlayed
                                    ? "checkmark"
                                    : ""
                            )
                        }

                    } label: {

                        Image(
                            systemName:
                                "arrow.up.arrow.down.circle"
                        )
                    }

                    Button {

                        showImporter = true

                    } label: {

                        Image(
                            systemName: "plus"
                        )
                    }
                    .disabled(isImporting)
                }
            }
        }

        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [
                .audio
            ],
            allowsMultipleSelection: true
        ) { result in

            switch result {

            case .success(let files):

                Task {

                    await MainActor.run {
                        importTotal = files.count
                        importProgress = 0
                        isImporting = true
                    }

                    for file in files {

                        library.importSong(
                            from: file
                        )

                        await MainActor.run {
                            importProgress += 1
                        }

                        try?
                            await Task.sleep(
                                nanoseconds:
                                    10_000_000
                            )
                    }

                    await MainActor.run {
                        isImporting = false
                    }
                }

            case .failure(let error):

                print(
                    "Import error:",
                    error.localizedDescription
                )
            }
        }

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
                                "songsview_importing"
                            )
                            .font(.headline)

                            Text(
                                String(
                                    format:
                                        String(
                                            localized:
                                                "songsview_import_progress"
                                        ),
                                    importProgress,
                                    importTotal
                                )
                            )
                            .font(.subheadline)
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
                    .shadow(radius: 10)
                }
            }
        }

        .alert(
            LocalizedStringKey(
                "songsview_delete_title"
            ),
            isPresented:
                $showDeleteConfirmation
        ) {

            Button(
                LocalizedStringKey(
                    "songsview_delete"
                ),
                role: .destructive
            ) {

                let songsToDelete =
                    library.songs.filter {
                        selectedSongIDs
                            .contains(
                                $0.id
                            )
                    }

                for song in songsToDelete {
                    library.deleteSong(song)
                }

                selectedSongIDs.removeAll()
                editMode = .inactive
            }

            Button(
                LocalizedStringKey(
                    "songsview_cancel"
                ),
                role: .cancel
            ) {}

        } message: {

            Text(
                String(
                    format:
                        String(
                            localized:
                                "songsview_delete_message"
                        ),
                    selectedSongIDs.count
                )
            )
        }

        .alert(
            Text(
                "songsview_duplicate_title"
            ),
            isPresented:
                Bindable(library)
                    .showDuplicateAlert
        ) {

            Button(
                String(
                    localized:
                        "songsview_skip"
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
                        "songsview_replace"
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
                        "songsview_skip_all"
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
                        "songsview_replace_all"
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
                        "songsview_cancel"
                ),
                role: .cancel
            ) {}

        } message: {

            Text(
                String(
                    format:
                        String(
                            localized:
                                "songsview_duplicate_message"
                        ),
                    library.duplicateSongName
                )
            )
        }

        .sheet(
            item:
                Bindable(library)
                    .songToAddToPlaylist
        ) { song in

            PlaylistPickerView(
                songs: [song]
            )
        }

        .sheet(
            item: $playlistSheetItem,
            onDismiss: {

                withAnimation {

                    editMode = .inactive
                    selectedSongIDs.removeAll()
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
                Bindable(library)
                    .showEditSheet
        ) {

            if let song =
                library.editingSong
            {

                EditSongView(
                    song: song
                )
            }
        }
    }

    @ViewBuilder
    private func songRow(
        _ song: Song
    ) -> some View {

        HStack(
            spacing: 12
        ) {

            SongArtworkView(
                song: song,
                cornerRadius: 10
            )
            .frame(
                width: 50,
                height: 50
            )

            VStack(
                alignment: .leading,
                spacing: 2
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

            if editMode == .inactive {

                Button {
                    selectedSong = song
                } label: {

                    Image(
                        systemName: "ellipsis"
                    )
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(
                        width: 30,
                        height: 30
                    )
                }
                .buttonStyle(.plain)
            }
        }

        .contentShape(
            Rectangle()
        )

        .onTapGesture {

            guard
                editMode == .inactive
            else {
                return
            }

            guard
                let url =
                    library.getURL(
                        for: song
                    )
            else {
                return
            }

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
                from: library.songs
            )
        }

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
                    library.isFavorite(song)
                    ?
                    LocalizedStringKey(
                        "songsview_remove_favorite"
                    )
                    :
                    LocalizedStringKey(
                        "songsview_add_favorite"
                    ),
                    systemImage:
                        library.isFavorite(song)
                        ? "heart.slash"
                        : "heart.fill"
                )
            }
            .tint(.red)
        }
    }
}
s
