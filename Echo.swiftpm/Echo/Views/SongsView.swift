import SwiftUI
import UniformTypeIdentifiers

enum SongSortOption: String, CaseIterable {
    case custom = "Aangepast"
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
            
        case .custom:
            return filteredSongs
            
        case .name:
            return filteredSongs.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title)
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
        
        NavigationStack {
            
            List {
                
                ForEach(sortedSongs) { song in
                    
                    HStack(spacing: 12) {
                        
                        // Albumhoes
                        if let data = song.coverData,
                           let image = UIImage(data: data) {
                            
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: 50,
                                    height: 50
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 10
                                    )
                                )
                            
                        } else {
                            
                            Image(systemName: "music.note")
                                .font(.title2)
                                .frame(
                                    width: 50,
                                    height: 50
                                )
                                .background(.thinMaterial)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 10
                                    )
                                )
                        }
                        
                        
                        // Titel + artiest
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            
                            Text(song.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        
                        Spacer()
                        
                        
                        // Drie puntjes
                        Button {
                            
                            selectedSong = song
                            
                        } label: {
                            
                            Image(systemName: "ellipsis")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(
                                    width: 30,
                                    height: 30
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    
                    // Nummer afspelen
                    .onTapGesture {
                        
                        if let url = library.getURL(
                            for: song
                        ) {
                            
                            library.markAsPlayed(
                                song
                            )
                            
                            audioPlayer.lastPlaybackDirection = .fade
                            
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
                    }
                    
                    // Swipe naar links = favoriet
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
                                ? "Verwijder"
                                : "Favoriet",
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
            
            
            .navigationTitle("Nummers")
            
            
            // Zoeken
            .searchable(
                text: $searchText
            )
            
            
            // Toolbar
            .toolbar {
                
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    
                    Menu {
                        
                        Button {
                            sortOption = .name
                        } label: {
                            
                            Label(
                                "Naam",
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
                                "Laatst toegevoegd",
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
                                "Laatst afgespeeld",
                                systemImage:
                                    sortOption == .lastPlayed
                                ? "checkmark"
                                : ""
                            )
                        }
                        
                        
                        Button {
                            sortOption = .custom
                        } label: {
                            
                            Label(
                                "Aangepast",
                                systemImage:
                                    sortOption == .custom
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
                }
                
                
                // Muziek importeren
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    
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
                        
                        library.importSong(
                            from: file
                        )
                    }
                    
                case .failure(let error):
                    
                    print(
                        "Import fout:",
                        error.localizedDescription
                    )
                }
            }
            
            
            // Dubbel nummer alert
            .alert(
                "Nummer bestaat al",
                isPresented:
                    Bindable(library)
                    .showDuplicateAlert
                
            ) {
                
                Button(
                    "OK",
                    role: .cancel
                ) { }
                
            } message: {
                
                Text(
                    "\"\(library.duplicateSongName)\" staat al in je bibliotheek."
                )
            }
            
            
            // Playlist kiezen
            .sheet(
                item:
                    Bindable(library)
                    .songToAddToPlaylist
                
            ) { song in
                
                PlaylistPickerView(
                    song: song
                )
            }
            
            
            // Song opties
            .sheet(
                item: $selectedSong
                
            ) { song in
                
                SongOptionsView(
                    song: song
                )
            }
            
            
            // Info wijzigen
            .sheet(
                isPresented:
                    Bindable(library)
                    .showEditSheet
                
            ) {
                
                if let song = library.editingSong {
                    
                    EditSongView(
                        song: song
                    )
                }
            }
        }
    }
}


#Preview {
    
    SongsView()
        .environment(
            MusicLibraryManager()
        )
        .environment(
            AudioPlayerManager()
        )
}
