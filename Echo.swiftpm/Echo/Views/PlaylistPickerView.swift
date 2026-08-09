import SwiftUI


struct PlaylistPickerView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    
    let song: Song
    
    
    var body: some View {
        
        NavigationStack {
            
            List {
                
                // Favorieten
                Button {
                    
                    if !library.isFavorite(song) {
                        library.toggleFavorite(song)
                    }
                    
                    dismiss()
                    
                } label: {
                    
                    playlistRow(
                        image: nil,
                        systemImage: "heart.fill",
                        title: "Favorieten",
                        subtitle: "\(library.favoriteSongs.count) nummers",
                        isSelected: library.isFavorite(song)
                    )
                }
                
                
                // Eigen playlists
                ForEach(library.playlists) { playlist in
                    
                    Button {
                        
                        library.addSong(
                            song,
                            to: playlist
                        )
                        
                        dismiss()
                        
                    } label: {
                        
                        playlistRow(
                            image: playlist.imageData,
                            systemImage: "music.note.list",
                            title: playlist.name,
                            subtitle: "\(playlist.songIDs.count) nummers",
                            isSelected: playlist.songIDs.contains(song.id)
                        )
                    }
                }
            }
            .navigationTitle("Playlist kiezen")
            .tint(.primary)
        }
    }
    
    
    
    @ViewBuilder
    func playlistRow(
        image: Data?,
        systemImage: String,
        title: String,
        subtitle: String,
        isSelected: Bool
    ) -> some View {
        
        HStack(spacing: 12) {
            
            if let image,
               let uiImage = UIImage(data: image) {
                
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: 55,
                        height: 55
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 14
                        )
                    )
                
            } else {
                
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(
                        systemImage == "heart.fill"
                        ? .red
                        : .primary
                    )
                    .frame(
                        width: 55,
                        height: 55
                    )
                    .background(.thinMaterial)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 14
                        )
                    )
            }
            
            
            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(subtitle)
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
