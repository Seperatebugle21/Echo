import SwiftUI
import UniformTypeIdentifiers

enum SongSortOption: String, CaseIterable {
    case name = "sort_name"
    case dateAdded = "sort_date_added"
    case lastPlayed = "sort_last_played"
}

struct SelectedSongsSheetItem: Identifiable {
    let id = UUID()
    let songs: [Song]
}

struct SongsView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var audioPlayer
    
    @State private var showImporter = false
    @State private var searchText = ""
    @State private var sortOption: SongSortOption = .name
    
    @State private var selectedSong: Song?
    
    // Bewerken & Selectie
    @State private var editMode: EditMode = .inactive
    @State private var selectedSongIDs = Set<Song.ID>()
    @State private var showDeleteConfirmation = false
    
    // Sheet voor meerdere nummers
    @State private var playlistSheetItem: SelectedSongsSheetItem? = nil
    
    // --- VOORTGANG IMPORT (NIEUW) ---
    @State private var isImporting = false
    @State private var importProgress = 0
    @State private var importTotal = 0
    
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
                        
                        // Drie puntjes
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
                    
                    // Nummer afspelen
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
                                library.isFavorite(song) ? LocalizedStringKey("action_remove") : LocalizedStringKey("action_favorite"),
                                systemImage: library.isFavorite(song) ? "heart.slash" : "heart.fill"
                            )
                        }
                        .tint(.red)
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(LocalizedStringKey("songs_title"))
            .searchable(text: $searchText, prompt: Text("search_prompt"))
            
            // Toolbar
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode == .active ? LocalizedStringKey("action_done") : LocalizedStringKey("action_edit")) {
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
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            let songsToAdd = library.songs.filter { selectedSongIDs.contains($0.id) }
                            playlistSheetItem = SelectedSongsSheetItem(songs: songsToAdd)
                        } label: {
                            Image(systemName: "music.note.list")
                        }
                        .disabled(selectedSongIDs.isEmpty)
                        
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                        .disabled(selectedSongIDs.isEmpty)
                    }
                } else {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                sortOption = .name
                            } label: {
                                Label(
                                    LocalizedStringKey("sort_name"),
                                    systemImage: sortOption == .name ? "checkmark" : ""
                                )
                            }
                            
                            Button {
                                sortOption = .dateAdded
                            } label: {
                                Label(
                                    LocalizedStringKey("sort_date_added"),
                                    systemImage: sortOption == .dateAdded ? "checkmark" : ""
                                )
                            }
                            
                            Button {
                                sortOption = .lastPlayed
                            } label: {
                                Label(
                                    LocalizedStringKey("sort_last_played"),
                                    systemImage: sortOption == .lastPlayed ? "checkmark" : ""
                                )
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                        }
                        
                        Button {
                            showImporter = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(isImporting) // Schakel uit tijdens importeren
                    }
                }
            }
            
            // File importer MET ASYNCHRONE VERWERKING
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let files):
                    // Start achtergrondtaak om vastlopen van UI te voorkomen
                    Task {
                        await MainActor.run {
                            importTotal = files.count
                            importProgress = 0
                            isImporting = true
                        }
                        
                        for file in files {
                            // Voeg het nummer toe via de library
                            library.importSong(from: file)
                            
                            // Update de voortgang
                            await MainActor.run {
                                importProgress += 1
                            }
                            
                            // Geef de UI even tijd om te hertekenen bij grote lijsten
                            try? await Task.sleep(nanoseconds: 10_000_000) 
                        }
                        
                        await MainActor.run {
                            isImporting = false
                        }
                    }
                    
                case .failure(let error):
                    print("Import fout:", error.localizedDescription)
                }
            }
            
            // --- LAAD-OVERLAY (NIEUW) ---
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView(value: Double(importProgress), total: Double(importTotal))
                                .progressViewStyle(.circular)
                                .scaleEffect(1.5)
                            
                            VStack(spacing: 4) {
                                Text("Nummers importeren...")
                                    .font(.headline)
                                
                                Text("\(importProgress) van \(importTotal) geüpload")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(24)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 10)
                    }
                    .transition(.opacity)
                }
            }
            
            // Alerts & Sheets
            .alert(
                LocalizedStringKey("alert_delete_songs_title"),
                isPresented: $showDeleteConfirmation
            ) {
                Button(LocalizedStringKey("action_delete"), role: .destructive) {
                    let songsToDelete = library.songs.filter { selectedSongIDs.contains($0.id) }
                    for song in songsToDelete {
                        library.deleteSong(song)
                    }
                    selectedSongIDs.removeAll()
                    editMode = .inactive
                }
                Button(LocalizedStringKey("action_cancel"), role: .cancel) { }
            } message: {
                Text("alert_delete_songs_message \(selectedSongIDs.count)")
            }
            
            .alert(
                LocalizedStringKey("alert_duplicate_title"),
                isPresented: Bindable(library).showDuplicateAlert
            ) {
                Button(LocalizedStringKey("action_ok"), role: .cancel) { }
            } message: {
                Text("alert_duplicate_message \(library.duplicateSongName)")
            }
            
            .sheet(item: Bindable(library).songToAddToPlaylist) { song in
                PlaylistPickerView(songs: [song])
            }
            
            .sheet(item: $playlistSheetItem, onDismiss: {
                withAnimation {
                    editMode = .inactive
                    selectedSongIDs.removeAll()
                }
            }) { item in
                PlaylistPickerView(songs: item.songs)
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
}
