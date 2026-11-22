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
    @State private var heroImage: UIImage?
    @State private var searching = false
    
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
    
    // MARK: - Page (Joi Tunes style); editing keeps the list below

    var body: some View {
        Group {
            if editMode == .active {
                editingList
            } else {
                playlistPage
            }
        }
    }

    private var hasOwnCover: Bool { currentPlaylist.imageData != nil || currentPlaylist.builtinCoverID != nil }

    /// Up to four different covers from the playlist, for the collage.
    private var collageData: [Data] {
        var seen = Set<Int>()
        var covers: [Data] = []
        for song in songs {
            guard let data = song.coverData ?? song.imageData else { continue }
            let key = data.count &+ data.hashValue
            if seen.insert(key).inserted { covers.append(data) }
            if covers.count == 4 { break }
        }
        return covers
    }

    private var playlistPage: some View {
        let collage = collageData
        return EchoCollectionPage(artworkData: currentPlaylist.imageData ?? collage.first,
                                  heroImage: hasOwnCover ? heroImage : nil,
                                  collage: hasOwnCover ? [] : collage,
                                  cardStyle: true,
                                  searchText: $searchText,
                                  searchActive: $searching) { colors in
            VStack(alignment: .leading, spacing: 12) {
                EchoCollectionPill(text: Text(LocalizedStringKey(isSmart ? "smart_editor_title" : "collection_kind_playlist")), tint: colors.tint)

                Text(currentPlaylist.displayName())
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(colors.tint)
                    .fixedSize(horizontal: false, vertical: true)

                Text("songs_count_format \(songs.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    EchoCollectionIconButton(symbol: isSmart ? "slider.horizontal.3" : "pencil",
                                             tint: colors.tint,
                                             label: LocalizedStringKey(isSmart ? "smart_edit_rules" : "action_edit")) {
                        if isSmart { showSmartEditor = true } else { withAnimation { editMode = .active } }
                    }
                    if !isSmart {
                        EchoCollectionIconButton(symbol: "plus", tint: colors.tint, label: "add_music_action") {
                            showSongPicker = true
                        }
                    }
                    EchoCollectionIconButton(symbol: "photo", tint: colors.tint, label: "select_cover_image_accessibility") {
                        coverData = currentPlaylist.imageData
                        builtinCover = currentPlaylist.builtinCoverID
                        showCoverGallery = true
                    }
                    Spacer(minLength: 0)
                    if !songs.isEmpty {
                        EchoCollectionPlayButtons(tint: colors.tint,
                                                  shuffle: { playPlaylist(shuffle: true) },
                                                  play: { playPlaylist() })
                    }
                }
                .padding(.top, 4)

                EchoCollectionDivider(tint: colors.tint)
                    .padding(.top, 6)
            }
        } rows: { colors in
            LazyVStack(spacing: 0) {
                if songs.isEmpty {
                    ContentUnavailableView {
                        Label(LocalizedStringKey("no_songs_title"), systemImage: "music.note.list")
                    } description: {
                        Text(LocalizedStringKey(isSmart ? "smart_empty" : "add_songs_to_playlist_description"))
                    }
                    .padding(.top, 20)
                } else if processedSongs.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.top, 20)
                } else {
                    ForEach(processedSongs) { song in
                        playlistRow(song, tint: colors.tint)
                    }
                    if isSmart {
                        Text("smart_remove_detail")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                }
            }
        }
        .navigationTitle(currentPlaylist.displayName())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !songs.isEmpty && !searching {
                    Menu {
                        Picker(LocalizedStringKey("MUSIC_APP_SORT_MENU_SELECTION_HEADER_TITLE"), selection: $sortOption) {
                            ForEach(FavoritesSortOption.allCases) { option in Text(option.localizedLabel).tag(option) }
                        }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                    .accessibilityLabel(LocalizedStringKey("MUSIC_APP_SORT_MENU_SELECTION_HEADER_TITLE"))
                    .tint(.primary)
                }
            }
        }
        .task(id: "\(currentPlaylist.builtinCoverID ?? "")|\(currentPlaylist.imageData?.count ?? 0)") {
            let image = await CoverThumbnailCache.shared.image(
                data: currentPlaylist.imageData, builtin: currentPlaylist.builtinCoverID, pixels: 900)
            guard !Task.isCancelled else { return }
            heroImage = image
        }
        .onReceive(clock) { clockDate = $0 }
        .sheet(isPresented: $showSmartEditor) { SmartPlaylistEditor(playlist: currentPlaylist) }
        .sheet(isPresented: $showCoverGallery, onDismiss: saveCover) {
            PlaylistCoverGallery(imageData: $coverData, builtinCoverID: $builtinCover)
        }
        .sheet(isPresented: $showSongPicker) {
            SongPickerView(playlist: playlist)
        }
    }

    private func playlistRow(_ song: Song, tint: Color) -> some View {
        let isCurrent = audioPlayer.currentSong?.id == song.id
        return Button {
            if let url = library.getURL(for: song) {
                audioPlayer.lastPlaybackDirection = .fade
                audioPlayer.play(song: song, url: url, queue: processedSongs)
                audioPlayer.allSongs = library.songs
                audioPlayer.fillAutoNext(from: library.songs)
            }
        } label: {
            HStack(spacing: 14) {
                CachedSongArtwork(data: song.coverData ?? song.imageData)
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                        .symbolEffect(.variableColor.iterative, isActive: audioPlayer.isPlaying)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint.opacity(isCurrent ? 0.14 : 0))
                    .padding(.horizontal, 8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(HomePressStyle())
        .animation(.easeInOut(duration: 0.25), value: isCurrent)
        .contextMenu {
            if isSmart {
                Button("smart_remove_five_days", systemImage: "minus.circle", role: .destructive) {
                    library.removeSong(song, from: currentPlaylist)
                }
            }
        }
    }

    // MARK: - Editing list

    private var editingList: some View {
        List(selection: $selectedSongs) {
            // MARK: Header Sectie
            if searchText.isEmpty {
                Section {
                    VStack(spacing: 14) {
                        // The playlist cover, large and slowly moving, fading into the page.
                        Button {
                            coverData = currentPlaylist.imageData
                            builtinCover = currentPlaylist.builtinCoverID
                            showCoverGallery = true
                        } label: {
                            EchoHeroArtwork(image: heroImage) {
                                PlaylistCoverArtwork(data: currentPlaylist.imageData, builtin: currentPlaylist.builtinCoverID)
                            }
                        }
                        .buttonStyle(HomePressStyle())
                        .accessibilityLabel("select_cover_image_accessibility")

                        VStack(spacing: 6) {
                            Text(currentPlaylist.displayName())
                                .font(.largeTitle)
                                .bold()
                                .multilineTextAlignment(.center)

                            Text("songs_count_format \(songs.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, -64)
                        .padding(.horizontal, 16)
                        .echoReveal(0)
                        
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
                    .padding(.bottom, 16)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
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
                        // Decoded off the main thread and cached; never per row in the body.
                        CachedSongArtwork(data: song.coverData ?? song.imageData)
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        
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
        .scrollContentBackground(.hidden)
        .background {
            EchoArtworkWash(data: currentPlaylist.imageData ?? songs.first.flatMap { $0.coverData ?? $0.imageData })
        }
        .echoBackground()
        .navigationTitle(currentPlaylist.displayName())
        .task(id: "\(currentPlaylist.builtinCoverID ?? "")|\(currentPlaylist.imageData?.count ?? 0)") {
            let image = await CoverThumbnailCache.shared.image(
                data: currentPlaylist.imageData, builtin: currentPlaylist.builtinCoverID, pixels: 900)
            guard !Task.isCancelled else { return }
            heroImage = image
        }
        .onReceive(clock) { clockDate = $0 }
        .sheet(isPresented: $showSmartEditor) { SmartPlaylistEditor(playlist: currentPlaylist) }
        .sheet(isPresented: $showCoverGallery, onDismiss: saveCover) {
            PlaylistCoverGallery(imageData: $coverData, builtinCoverID: $builtinCover)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Group {
                if editMode == .active {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .disabled(selectedSongs.isEmpty)
                }
                }.tint(.primary)
            }

            
            
            ToolbarItem(placement: .topBarTrailing) {
                Group {
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
                }.tint(.primary)
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
