import SwiftUI
import PhotosUI

struct PlaylistDetailView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var audioPlayer
    
    let playlist: Playlist
    
    @State private var showSongPicker = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedSongs: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    
    @State private var selectedImage: PhotosPickerItem?
    @State private var playlistImage: UIImage?
    
    // MARK: - Computed Properties
    var songs: [Song] {
        guard let currentPlaylist = library.playlists.first(where: {
            $0.id == playlist.id
        }) else {
            return []
        }
        
        return currentPlaylist.songIDs.compactMap { id in
            library.songs.first {
                $0.id == id
            }
        }
    }
    
    private var removeConfirmationMessage: String {
        let format = NSLocalizedString("remove_songs_confirmation_message", comment: "")
        return String(format: format, selectedSongs.count)
    }
    
    var body: some View {
        List(selection: $selectedSongs) {
            // MARK: Header Sectie
            Section {
                VStack(spacing: 16) {
                    PhotosPicker(
                        selection: $selectedImage,
                        matching: .images
                    ) {
                        if let playlistImage {
                            Image(uiImage: playlistImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 150, height: 150)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 20)
                                )
                        } else {
                            Image(systemName: "music.note")
                                .font(.system(size: 70))
                                .frame(width: 150, height: 150)
                                .background(.thinMaterial)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 20)
                                )
                        }
                    }
                    
                    Text(playlist.name)
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
                                Label(
                                    LocalizedStringKey("play_all_action"),
                                    systemImage: "play.fill"
                                )
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button {
                                playPlaylist(shuffle: true)
                            } label: {
                                Label(
                                    LocalizedStringKey("shuffle_action"),
                                    systemImage: "shuffle"
                                )
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
            .selectionDisabled(true) // Zorgt ervoor dat de header niet geselecteerd kan worden
            
            // MARK: Nummers Sectie
            if songs.isEmpty {
                ContentUnavailableView {
                    Label(
                        LocalizedStringKey("no_songs_title"),
                        systemImage: "music.note.list"
                    )
                } description: {
                    Text(LocalizedStringKey("add_songs_to_playlist_description"))
                } actions: {
                    Button {
                        showSongPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text(LocalizedStringKey("add_music_action"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .selectionDisabled(true)
            } else {
                ForEach(songs) { song in
                    HStack(spacing: 12) {
                        if let data = song.coverData,
                           let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 10)
                                )
                        } else {
                            Image(systemName: "music.note")
                                .font(.title2)
                                .frame(width: 50, height: 50)
                                .background(.thinMaterial)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 10)
                                )
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
                        // Tikken op nummer werkt alleen als we NIET aan het bewerken zijn
                        guard editMode == .inactive else { return }
                        
                        if let url = library.getURL(for: song) {
                            audioPlayer.play(
                                song: song,
                                url: url,
                                queue: songs
                            )
                            
                            audioPlayer.allSongs = library.songs
                            audioPlayer.fillAutoNext(
                                from: library.songs
                            )
                        }
                    }
                }
                .onMove { indices, newOffset in
                    moveSongs(
                        from: indices,
                        to: newOffset
                    )
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle(playlist.name)
        .onAppear {
            loadPlaylistImage()
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
                HStack {
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
                    
                    if editMode == .inactive {
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
        .onChange(of: selectedImage) {
            Task {
                if let data = try? await selectedImage?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    playlistImage = uiImage
                    savePlaylistImage(data)
                }
            }
        }
        .alert(
            LocalizedStringKey("delete_songs_title"),
            isPresented: $showDeleteConfirmation
        ) {
            Button(
                LocalizedStringKey("action_cancel"),
                role: .cancel
            ) { }
            
            Button(
                LocalizedStringKey("action_delete"),
                role: .destructive
            ) {
                deleteSelectedSongs()
            }
        } message: {
            Text(removeConfirmationMessage)
        }
    }
    
    // MARK: - Helper Methods
    func loadPlaylistImage() {
        guard let data = playlist.imageData,
              let image = UIImage(data: data)
        else {
            return
        }
        playlistImage = image
    }
    
    func savePlaylistImage(_ data: Data) {
        guard let index = library.playlists.firstIndex(
            where: { $0.id == playlist.id }
        ) else {
            return
        }
        library.playlists[index].imageData = data
    }
    
    func deleteSelectedSongs() {
        guard let index = library.playlists.firstIndex(
            where: { $0.id == playlist.id }
        ) else {
            return
        }
        
        library.playlists[index].songIDs.removeAll {
            selectedSongs.contains($0)
        }
        
        selectedSongs.removeAll()
        
        withAnimation {
            editMode = .inactive
        }
    }
    
    func playPlaylist(shuffle: Bool = false) {
        var queue = songs
        
        if shuffle {
            queue.shuffle()
        }
        
        guard let firstSong = queue.first else {
            return
        }
        
        if let url = library.getURL(for: firstSong) {
            audioPlayer.play(
                song: firstSong,
                url: url,
                queue: queue
            )
            
            audioPlayer.allSongs = library.songs
            audioPlayer.fillAutoNext(
                from: library.songs
            )
        }
    }
    
    func moveSongs(
        from source: IndexSet,
        to destination: Int
    ) {
        guard let index = library.playlists.firstIndex(
            where: { $0.id == playlist.id }
        ) else {
            return
        }
        
        library.playlists[index].songIDs.move(
            fromOffsets: source,
            toOffset: destination
        )
    }
}
