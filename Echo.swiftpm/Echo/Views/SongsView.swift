import SwiftUI
import UniformTypeIdentifiers

enum SongSortOption: String, CaseIterable {
    case name = "Naam"
    case dateAdded = "Laatst toegevoegd"
    case lastPlayed = "Laatst afgespeeld"
}

struct SongsView: View {
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var audioPlayer
    
    @State private var showImporter = false
    @State private var searchText = ""
    @State private var sortOption: SongSortOption = .name
    
    @State private var selectedSong: Song?
    
    // MARK: - Meervoudige Selectie State
    @State private var isEditing = false
    @State private var selectedSongIDs = Set<Song.ID>()
    @State private var showDeleteConfirmation = false
    @State private var showBulkPlaylistPicker = false
    
    var filteredSongs: [Song] {
        if searchText.isEmpty {
            return library.songs
        }
        return library.songs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var sortedSongs: [Song] {
        switch sortOption {
        case .name:
            return filteredSongs.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .dateAdded:
            return filteredSongs.sorted {
                $0.dateAdded > $1.dateAdded
            }
        case .lastPlayed:
            return filteredSongs.sorted {
                ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            // Gebruik selection op List voor meervoudige selectie
            List(selection: $selectedSongIDs) {
                ForEach(sortedSongs) { song in
                    HStack(spacing: 12) {
                        // Albumhoes
                        if let data = song.coverData, let image = UIImage(data: data) {
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
                        
                        // Titel + artiest
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        // Drie puntjes (alleen tonen als we NIET in bewerkmodus zitten)
                        if !isEditing {
                            Button {
                                selectedSong = song
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isEditing else { return }
                        
                        if let url = library.getURL(for: song) {
                            library.markAsPlayed(song)
                            audioPlayer.lastPlaybackDirection = .fade
                            audioPlayer.play(song: song, url: url, queue: [song])
                            audioPlayer.allSongs = library.songs
                            audioPlayer.fillAutoNext(from: library.songs)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isEditing {
                            Button {
                                library.toggleFavorite(song)
                            } label: {
                                Label(
                                    library.isFavorite(song) ? "Verwijder" : "Favoriet",
                                    systemImage: library.isFavorite(song) ? "heart.slash" : "heart.fill"
                                )
                            }
                            .tint(.red)
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(isEditing ? .active : .inactive))
            .navigationTitle("Nummers")
            .searchable(text: $searchText)
            
            // MARK: - Toolbars
            .toolbar {
                // Links boven: Wijzig knop & Verwijder knop
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        Button(isEditing ? "Gereed" : "Wijzig") {
                            withAnimation {
                                isEditing.toggle()
                                if !isEditing {
                                    selectedSongIDs.removeAll()
                                }
                            }
                        }
                        
                        if isEditing && !selectedSongIDs.isEmpty {
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                
                // Rechts boven: Sorteermenu, Playlist toevoegen & Plus-knop
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if isEditing {
                            // Knop om de geselecteerde nummers aan een playlist toe te voegen
                            if !selectedSongIDs.isEmpty {
                                Button {
                                    showBulkPlaylistPicker = true
                                } label: {
                                    Image(systemName: "music.note.list")
                                }
                            }
                        } else {
                            // Sorteer menu (zonder 'Aangepast')
                            Menu {
                                Button {
                                    sortOption = .name
                                } label: {
                                    Label("Naam", systemImage: sortOption == .name ? "checkmark" : "")
                                }
                                
                                Button {
                                    sortOption = .dateAdded
                                } label: {
                                    Label("Laatst toegevoegd", systemImage: sortOption == .dateAdded ? "checkmark" : "")
                                }
                                
                                Button {
                                    sortOption = .lastPlayed
                                } label: {
                                    Label("Laatst afgespeeld", systemImage: sortOption == .lastPlayed ? "checkmark" : "")
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down.circle")
                            }
                            
                            // Importeer knop
                            Button {
                                showImporter = true
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                }
            }
            
            // MARK: - Alerts & Sheets
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let files):
                    for file in files {
                        library.importSong(from: file)
                    }
                case .failure(let error):
                    print("Import fout:", error.localizedDescription)
                }
            }
            
            // Bevestigingsalert voor verwijderen
            .alert("Nummers verwijderen", isPresented: $showDeleteConfirmation) {
                Button("Verwijder (\(selectedSongIDs.count))", role: .destructive) {
                    deleteSelectedSongs()
                }
                Button("Annuleer", role: .cancel) { }
            } message: {
                Text("Weet je zeker dat je \(selectedSongIDs.count) nummer(s) wilt verwijderen uit je bibliotheek?")
            }
            
            .alert("Nummer bestaat al", isPresented: Bindable(library).showDuplicateAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("\"\(library.duplicateSongName)\" staat al in je bibliotheek.")
            }
            
            // Sheet voor toevoegen van meerdere nummers aan een playlist
            .sheet(isPresented: $showBulkPlaylistPicker) {
                // Hier geef je de geselecteerde nummers door aan de picker
                let selectedSongs = library.songs.filter { selectedSongIDs.contains($0.id) }
                BulkPlaylistPickerView(songs: selectedSongs, isPresented: $showBulkPlaylistPicker) {
                    isEditing = false
                    selectedSongIDs.removeAll()
                }
            }
            
            .sheet(item: Bindable(library).songToAddToPlaylist) { song in
                PlaylistPickerView(song: song)
            }
            
            .sheet(item: $selectedSong) { song in
                SongOptionsView(song: song)
            }
            
            .sheet(isPresented: Bindable(library).showEditSheet) {
                if let song = library.editingSong {
                    EditSongView(song: song)
                }
            }
        }
    }
    
    // MARK: - Helper functies
    private func deleteSelectedSongs() {
        let songsToDelete = library.songs.filter { selectedSongIDs.contains($0.id) }
        for song in songsToDelete {
            library.deleteSong(song) // Zorg dat deze methode in je MusicLibraryManager staat
        }
        selectedSongIDs.removeAll()
        isEditing = false
    }
}
