import SwiftUI

struct PlaylistPickerView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    
    let songs: [Song]
    
    // Convenience initializer voor wanneer je slechts 1 nummer meegeeft
    init(song: Song) {
        self.songs = [song]
    }
    
    // Initializer voor meerdere nummers
    init(songs: [Song]) {
        self.songs = songs
    }
    
    // Controleert of alle geselecteerde nummers al favoriet zijn
    private var areAllFavorites: Bool {
        guard !songs.isEmpty else { return false }
        return songs.allSatisfy { library.isFavorite($0) }
    }
    
    // Controleert of alle geselecteerde nummers in een specifieke playlist staan
    private func areAllInPlaylist(_ playlist: Playlist) -> Bool {
        guard !songs.isEmpty else { return false }
        return songs.allSatisfy { playlist.songIDs.contains($0.id) }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Favorieten
                Button {
                    for song in songs {
                        if !library.isFavorite(song) {
                            library.toggleFavorite(song)
                        }
                    }
                    dismiss()
                } label: {
                    playlistRow(
                        image: nil,
                        systemImage: "heart.fill",
                        title: Text(LocalizedStringKey("favorites_title")),
                        count: library.favoriteSongs.count,
                        isSelected: areAllFavorites
                    )
                }
                
                // Eigen playlists
                ForEach(library.playlists) { playlist in
                    Button {
                        for song in songs {
                            library.addSong(song, to: playlist)
                        }
                        dismiss()
                    } label: {
                        playlistRow(
                            image: playlist.imageData,
                            systemImage: "music.note.list",
                            title: Text(playlist.name),
                            count: library.songCount(in: playlist),
                            isSelected: areAllInPlaylist(playlist)
                        )
                    }
                }
            }
            .navigationTitle(LocalizedStringKey("choose_playlist_title"))
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LocalizedStringKey("action_cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    func playlistRow(
        image: Data?,
        systemImage: String,
        title: Text,
        count: Int,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            if let image,
               let uiImage = UIImage(data: image) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 55, height: 55)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(
                        systemImage == "heart.fill"
                        ? .red
                        : .primary
                    )
                    .frame(width: 55, height: 55)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                title
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text("songs_count_format \(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}
