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
    
    @State private var selectedSong: Song? // Voor de 3-puntjes menu sheet
    
    // Bewerken & Selectie
    @State private var editMode: EditMode = .inactive
    @State private var selectedSongIDs = Set<Song.ID>()
    @State private var showDeleteConfirmation = false
    
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
            VStack(spacing: 0) {
                List(selection: $selectedSongIDs) {
                    ForEach(sortedSongs) { song in
                        HStack(spacing: 12) {
                            
                            // Albumhoes
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
                            
                            // Drie puntjes (alleen tonen als we niet in bewerkmodus zijn)
                            if editMode == .inactive {
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
                        
                        // Nummer afspelen (alleen als we niet bewerken)
                        .onTapGesture {
                            guard editMode == .inactive else { return }
                            
                            if let url = library.getURL(for: song) {
                                library.markAsPlayed(song)
                                audioPlayer.lastPlaybackDirection = .fade
                                audioPlayer.play(
                                    song: song,
                                    url: url,
                                    queue: [song]
                                )
                                audioPlayer.allSongs = library.songs
                                audioPlayer.fillAutoNext(from: library.songs)
                            }
                        }
                        
                        // Swipe naar links = favoriet
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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
                .environment(\.editMode, $editMode)
                
                // Onderste balk bij actieve bewerkmodus
                if editMode == .active {
                    HStack {
                        // Aan playlist toevoegen
                        Button {
                            let songsToAdd = library.songs.filter { selectedSongIDs.contains($0.id) }
                            for song in songsToAdd {
                                library.songToAddToPlaylist = song
                            }
                        } label: {
                            Label("Aan playlist", systemImage: "music.note.list")
                        }
                        .disabled(selectedSongIDs.isEmpty)
                        
                        Spacer()
                        
                        // Verwijderen met bevestiging
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Verwijder (\(selectedSongIDs.count))", systemImage: "trash")
                        }
                        .disabled(selectedSongIDs.isEmpty)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Nummers")
            .searchable(text: $searchText)
            
            // Toolbar
            .toolbar {
                // Wijzig knop
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode == .active ? "Gereed" : "Wijzig") {
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
                
                // Sorteermenu
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            sortOption = .name
                        } label: {
                            Label(
                                "Naam",
                                systemImage: sortOption == .name ? "checkmark" : ""
                            )
                        }
                        
                        Button {
                            sortOption = .dateAdded
                        } label: {
                            Label(
                                "Laatst toegevoegd",
                                systemImage: sortOption == .dateAdded ? "checkmark" : ""
                            )
                        }
                        
                        Button {
                            sortOption = .lastPlayed
                        } label: {
                            Label(
                                "Laatst afgespeeld",
                                systemImage: sortOption == .lastPlayed ? "checkmark" : ""
                            )
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
                
                // Muziek importeren
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            
            // File importer
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
            
            // Alert voor bevestiging verwijderen
            .alert(
                "Nummers verwijderen",
                isPresented: $showDeleteConfirmation
            ) {
                Button("Verwijder", role: .destructive) {
                    let songsToDelete = library.songs.filter { selectedSongIDs.contains($0.id) }
                    for song in songsToDelete {
                        library.deleteSong(song) // Zorg dat deze methode bestaat op MusicLibraryManager
                    }
                    selectedSongIDs.removeAll()
                    editMode = .inactive
                }
                Button("Annuleer", role: .cancel) { }
            } message: {
                Text("Weet je zeker dat je \(selectedSongIDs.count) nummer(s) wilt verwijderen uit je bibliotheek?")
            }
            
            // Dubbel nummer alert
            .alert(
                "Nummer bestaat al",
                isPresented: Bindable(library).showDuplicateAlert
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("\"\(library.duplicateSongName)\" staat al in je bibliotheek.")
            }
            
            // Playlist kiezen
            .sheet(item: Bindable(library).songToAddToPlaylist) { song in
                PlaylistPickerView(song: song)
            }
            
            // Song opties
            .sheet(item: $selectedSong) { song in
                SongOptionsView(song: song)
            }
            
            // Info wijzigen
            .sheet(isPresented: Bindable(library).showEditSheet) {
                if let song = library.editingSong {
                    EditSongView(song: song)
                }
            }
        }
    }
}

#Preview {
    SongsView()
        .environment(MusicLibraryManager())
        .environment(AudioPlayerManager())
}
