import SwiftUI

enum FavoritesSortOption: String, CaseIterable, Identifiable {
    case custom
    case title
    case artist
    case dateAdded
    case lastPlayed
    
    var id: String { self.rawValue }
    
    var localizedLabel: LocalizedStringKey {
        switch self {
        case .custom:
            return LocalizedStringKey("MUSIC_APP_SORT_OPTION_DEFAULT_CUSTOM_ORDER")
        case .title:
            return LocalizedStringKey("MUSIC_APP_SORT_OPTION_ALPHABETICAL_TITLE")
        case .artist:
            return LocalizedStringKey("MUSIC_APP_SORT_OPTION_ALPHABETICAL_ARTIST")
        case .dateAdded:
            return LocalizedStringKey("MUSIC_APP_SORT_OPTION_CHRONOLOGICAL_DATE_ADDED")
        case .lastPlayed:
            return LocalizedStringKey("MUSIC_APP_SORT_OPTION_CHRONOLOGICAL_LAST_PLAYED")
        }
    }
}

struct FavoritesView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var audioPlayer
    
    @State private var showSongPicker = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedSongs = Set<Song.ID>()
    @State private var showDeleteConfirmation = false
    @State private var searchText = ""
    @State private var sortOption: FavoritesSortOption = .custom
    
    var songs: [Song] {
        library.favoriteSongs
    }
    
    var processedSongs: [Song] {
        let filtered = songs.filter { song in
            searchText.isEmpty ||
            song.title.localizedCaseInsensitiveContains(searchText) ||
            song.artist.localizedCaseInsensitiveContains(searchText)
        }
        
        switch sortOption {
        case .custom:
            return filtered
        case .title:
            return filtered.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .artist:
            return filtered.sorted { $0.artist.localizedCompare($1.artist) == .orderedAscending }
        case .dateAdded:
            return filtered.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .lastPlayed:
            return filtered.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        }
    }
    
    private var removeConfirmationMessage: String {
        let format = NSLocalizedString("remove_songs_confirmation_message", comment: "")
        return String(format: format, selectedSongs.count)
    }
    
    var body: some View {
        List(selection: $selectedSongs) {
            
            // MARK: - Header / Knoppen
            if !songs.isEmpty && searchText.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        
                        Image(systemName: "heart.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.red)
                            .frame(width: 120, height: 120)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        
                        Text("songs_count_format \(songs.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            
                            Button {
                                playFavorites()
                            } label: {
                                Label("play_all_action", systemImage: "play.fill")
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button {
                                playFavorites(shuffle: true)
                            } label: {
                                Label("shuffle_action", systemImage: "shuffle")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
                .selectionDisabled(true)
            }
            
            // MARK: - Lijst van favorieten
            if songs.isEmpty {
                ContentUnavailableView {
                    Label(
                        LocalizedStringKey("favorites_empty_title"),
                        systemImage: "heart"
                    )
                } description: {
                    Text(LocalizedStringKey("favorites_empty_description"))
                }
                .selectionDisabled(true)
                
            } else if processedSongs.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .selectionDisabled(true)
            } else {
                
                ForEach(processedSongs) { song in
                    HStack(spacing: 12) {
                        
                        if let data = song.coverData,
                           let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            Image(systemName: "music.note")
                                .font(.title2)
                                .frame(width: 50, height: 50)
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.headline)
                            
                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if editMode == .inactive {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard editMode == .inactive else { return }
                        
                        if let url = library.getURL(for: song) {
                            audioPlayer.play(
                                song: song,
                                url: url,
                                queue: processedSongs
                            )
                            
                            audioPlayer.allSongs = library.songs
                            audioPlayer.fillAutoNext(from: library.songs)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            library.toggleFavorite(song)
                        } label: {
                            Label("action_remove", systemImage: "heart.slash")
                        }
                        .tint(.red)
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            prompt: Text(LocalizedStringKey("MUSIC_APP_FAVORITES_SEARCH_PLACEHOLDER_TEXT"))
        )
        .environment(\.editMode, $editMode)
        .navigationTitle(Text(LocalizedStringKey("favorites_navigation_title")))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if editMode == .active {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .disabled(selectedSongs.isEmpty)
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {

                        if !songs.isEmpty {
                        Button {
                            withAnimation {
                                if editMode == .active {
                                    editMode = .inactive
                                    selectedSongs.removeAll()
                                } else {
                                    editMode = .active
                                }
                            }
                        } label: {
                            Text(
                                editMode == .active
                                ? LocalizedStringKey("action_done")
                                : LocalizedStringKey("action_edit")
                            )
                        }
                    }
                    
                    
                    if editMode == .inactive && !songs.isEmpty {
                        Menu {
                            Picker(
                                LocalizedStringKey("MUSIC_APP_SORT_MENU_SELECTION_HEADER_TITLE"),
                                selection: $sortOption
                            ) {
                                Label(
                                    FavoritesSortOption.custom.localizedLabel,
                                    systemImage: "arrow.up.arrow.down"
                                ).tag(FavoritesSortOption.custom)
                                
                                Label(
                                    FavoritesSortOption.title.localizedLabel,
                                    systemImage: "textformat"
                                ).tag(FavoritesSortOption.title)
                                
                                Label(
                                    FavoritesSortOption.artist.localizedLabel,
                                    systemImage: "person"
                                ).tag(FavoritesSortOption.artist)
                                
                                Label(
                                    FavoritesSortOption.dateAdded.localizedLabel,
                                    systemImage: "calendar"
                                ).tag(FavoritesSortOption.dateAdded)
                                
                                Label(
                                    FavoritesSortOption.lastPlayed.localizedLabel,
                                    systemImage: "play.circle"
                                ).tag(FavoritesSortOption.lastPlayed)
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                        }
                    }
                    
                
                    if editMode == .inactive {
                        Button {
                            showSongPicker = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(LocalizedStringKey("add_songs_action"))
                    }
                }
            }
        }
        .sheet(isPresented: $showSongPicker) {
            SongPickerView(isFavorites: true)
        }
        .alert(
            LocalizedStringKey("delete_songs_title"),
            isPresented: $showDeleteConfirmation
        ) {
            Button(LocalizedStringKey("action_cancel"), role: .cancel) { }
            Button(LocalizedStringKey("action_delete"), role: .destructive) {
                removeSelectedFavorites()
            }
        } message: {
            Text(removeConfirmationMessage)
        }
    }
    
    func removeSelectedFavorites() {
        let songsToRemove = songs.filter { selectedSongs.contains($0.id) }
        for song in songsToRemove {
            library.toggleFavorite(song)
        }
        selectedSongs.removeAll()
        withAnimation { editMode = .inactive }
    }
    
    func playFavorites(shuffle: Bool = false) {
        var queue = processedSongs
        if shuffle { queue.shuffle() }
        guard let firstSong = queue.first else { return }
        
        if let url = library.getURL(for: firstSong) {
            audioPlayer.play(song: firstSong, url: url, queue: queue)
            audioPlayer.allSongs = library.songs
            audioPlayer.fillAutoNext(from: library.songs)
        }
    }
}
