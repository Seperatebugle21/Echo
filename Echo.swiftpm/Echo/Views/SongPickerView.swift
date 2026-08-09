import SwiftUI

struct SongPickerView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    
    let playlist: Playlist?
    let isFavorites: Bool
    
    @State private var searchText = ""
    @State private var selectedSongs: Set<UUID> = []
    
    
    init(
        playlist: Playlist? = nil,
        isFavorites: Bool = false
    ) {
        self.playlist = playlist
        self.isFavorites = isFavorites
    }
    
    
    var filteredSongs: [Song] {
        
        if searchText.isEmpty {
            return library.songs
        }
        
        return library.songs.filter {
            
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    
    var body: some View {
        
        NavigationStack {
            
            List {
                
                ForEach(filteredSongs) { song in
                    
                    Button {
                        
                        if selectedSongs.contains(song.id) {
                            
                            selectedSongs.remove(song.id)
                            
                        } else {
                            
                            selectedSongs.insert(song.id)
                        }
                        
                    } label: {
                        
                        HStack {
                            
                            VStack(alignment: .leading) {
                                
                                Text(song.title)
                                    .foregroundStyle(.primary)
                                
                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedSongs.contains(song.id) {
                                
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                                
                            } else {
                                
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            
            .searchable(text: $searchText)
            
            .navigationTitle(
                isFavorites
                ? "Voeg favorieten toe"
                : "Voeg nummers toe"
            )
            
            .toolbar {
                
                ToolbarItem(placement: .topBarLeading) {
                    
                    Button("Annuleer") {
                        dismiss()
                    }
                }
            }
            
            .safeAreaInset(edge: .bottom) {
                
                Button {
                    
                    for song in filteredSongs
                    where selectedSongs.contains(song.id) {
                        
                        if isFavorites {
                            
                            if !library.isFavorite(song) {
                                library.toggleFavorite(song)
                            }
                            
                        } else if let playlist {
                            
                            library.addSong(
                                song,
                                to: playlist
                            )
                        }
                    }
                    
                    dismiss()
                    
                } label: {
                    
                    Text(
                        isFavorites
                        ? "Voeg \(selectedSongs.count) favorieten toe"
                        : "Voeg \(selectedSongs.count) nummers toe"
                    )
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .disabled(selectedSongs.isEmpty)
            }
        }
    }
}
