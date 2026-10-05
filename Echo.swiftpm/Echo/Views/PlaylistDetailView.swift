import SwiftUI
import PhotosUI

struct PlaylistDetailView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var audioPlayer
    
    let playlist: Playlist
    
    @State private var showSongPicker = false
    @State private var showSmartEditor = false
    @State private var clockDate = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private var currentPlaylist: Playlist { library.playlists.first { $0.id == playlist.id } ?? playlist }
    private var isSmart: Bool { currentPlaylist.smartDefinition != nil }
    @State private var editMode: EditMode = .inactive
    @State private var selectedSongs: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    
    @State private var showCoverGallery = false
    @State private var coverData: Data?
    @State private var builtinCover: String?
    @State private var searchText = ""
    @State private var sortOption: FavoritesSortOption = .custom
    
    var songs: [Song] {
        _ = clockDate
        guard let currentPlaylist = library.playlists.first(where: {
            $0.id == playlist.id
        }) else {
            return []
        }

        return library.songs(in: currentPlaylist)
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
            // MARK: Header Sectie
            if searchText.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Button {
                            coverData = currentPlaylist.imageData
                            builtinCover = currentPlaylist.builtinCoverID
                            showCoverGallery = true
                        } label: {
                            PlaylistCoverArtwork(data: currentPlaylist.imageData, builtin: currentPlaylist.builtinCoverID)
                                .frame(width: 150, height: 150).clipShape(.rect(cornerRadius: 20))
                        }.buttonStyle(.plain).accessibilityLabel("select_cover_image_accessibility")

                        Text(currentPlaylist.displayName())
                            .font(.largeTitle)
                            .bold()
                        
                        Text("songs_count_format \(songs.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if !songs.isEmpty {
                            HStack(spacing: 12) {
                                Button {
                                    playPlaylist()
                                } label: {
                                    Label(LocalizedStringKey("play_all_action"), systemImage: "play.fill")
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.borderedProminent)
                                
                                Button {
                                    playPlaylist(shuffle: true)
                                } label: {
                                    Label(LocalizedStringKey("shuffle_action"), systemImage: "shuffle")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
                .selectionDisabled(true)
            }
            
            // MARK: Nummers Sectie
            if songs.isEmpty {
                ContentUnavailableView {
                    Label(LocalizedStringKey("no_songs_title"), systemImage: "music.note.list")
                } description: {
                    Text(LocalizedStringKey(isSmart ? "smart_empty" : "add_songs_to_playlist_description"))
                } actions: {
                    Button {
                        if isSmart { showSmartEditor = true } else { showSongPicker = true }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text(LocalizedStringKey(isSmart ? "smart_edit_rules" : "add_music_action"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .selectionDisabled(true)
            } else if processedSongs.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .selectionDisabled(true)
            } else {
                Section {
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
                                .foregroundStyle(.primary)
                            
                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if isSmart {
                            Button("smart_remove_five_days", systemImage: "minus.circle", role: .destructive) {
                                library.removeSong(song, from: currentPlaylist)
                            }
                        }
                    }
                    .contextMenu {
                        if isSmart {
                            Button("smart_remove_five_days", systemImage: "minus.circle", role: .destructive) {
                                library.removeSong(song, from: currentPlaylist)
                            }
                        }
                    }
                }
                .onMove(perform: (!isSmart && searchText.isEmpty && sortOption == .custom) ? moveSongs : nil)
                } footer: {
                    if isSmart { Text("smart_remove_detail") }
                }
            }
        }
        .searchable(
            text: $searchText,
            prompt: Text(LocalizedStringKey("MUSIC_APP_PLAYLIST_SEARCH_PLACEHOLDER_TEXT"))
        )
        .environment(\.editMode, $editMode)
        .echoBackground()
        .navigationTitle(currentPlaylist.displayName())
        .onReceive(clock) { clockDate = $0 }
        .sheet(isPresented: $showSmartEditor) { SmartPlaylistEditor(playlist: currentPlaylist) }
        .sheet(isPresented: $showCoverGallery, onDismiss: saveCover) {
            PlaylistCoverGallery(imageData: $coverData, builtinCoverID: $builtinCover)
        }
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

     
                    Button {
                        if isSmart { showSmartEditor = true; return }
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

                    
                    if editMode == .inactive && !songs.isEmpty {
                        Menu {
                            Picker(
                                LocalizedStringKey("MUSIC_APP_SORT_MENU_SELECTION_HEADER_TITLE"),
                                selection: $sortOption
                            ) {
                                Label(
                                    FavoritesSortOption.custom.localizedLabel,
                                    systemImage: "line.3.horizontal.decrease"
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
                    
                    
                    
                    if editMode == .inactive && !isSmart {
                        Button {
                            showSongPicker = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSongPicker) {
            SongPickerView(playlist: playlist)
        }
        .alert(LocalizedStringKey("delete_songs_title"), isPresented: $showDeleteConfirmation) {
            Button(LocalizedStringKey("action_cancel"), role: .cancel) { }
            Button(LocalizedStringKey("action_delete"), role: .destructive) {
                deleteSelectedSongs()
            }
        } message: {
            Text(removeConfirmationMessage)
        }
    }
    
    private func saveCover() {
        guard let index = library.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        var updated = library.playlists[index]
        guard updated.imageData != coverData || updated.builtinCoverID != builtinCover else { return }
        updated.imageData = coverData; updated.builtinCoverID = builtinCover
        library.playlists[index] = updated
    }

    func deleteSelectedSongs() {
        guard let index = library.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        library.playlists[index].songIDs.removeAll { selectedSongs.contains($0) }
        selectedSongs.removeAll()
        withAnimation { editMode = .inactive }
    }
    
    func playPlaylist(shuffle: Bool = false) {
        var queue = processedSongs
        if shuffle { queue.shuffle() }
        guard let firstSong = queue.first else { return }
        
        if let url = library.getURL(for: firstSong) {
            audioPlayer.play(song: firstSong, url: url, queue: queue)
            audioPlayer.allSongs = library.songs
            audioPlayer.fillAutoNext(from: library.songs)
        }
    }
    
    func moveSongs(from source: IndexSet, to destination: Int) {
        guard let index = library.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        library.playlists[index].songIDs.move(fromOffsets: source, toOffset: destination)
    }
}
