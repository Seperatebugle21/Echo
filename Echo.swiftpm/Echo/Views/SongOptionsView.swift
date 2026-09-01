import SwiftUI

struct SongOptionsView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Environment(\.dismiss) private var dismiss
    
    @State private var showDeleteConfirmation = false
    
    let song: Song
    
    
    var body: some View {
        
        VStack(spacing: 20) {
            
            // Sleep-indicator
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
            
            
            // Song informatie — blijft vast staan
            HStack(spacing: 15) {
                
                if let data = song.coverData,
                   let image = UIImage(data: data) {
                    
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: 65,
                            height: 65
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 12
                            )
                        )
                    
                } else {
                    
                    Image(systemName: "music.note")
                        .font(.title)
                        .frame(
                            width: 65,
                            height: 65
                        )
                        .background(.thinMaterial)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 12
                            )
                        )
                }
                
                
                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    
                    Text(song.title)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Text(song.artist)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            
            Divider()
                .padding(.horizontal)
            
            
            // Alleen de acties scrollen
            ScrollView {
                
                VStack(spacing: 20) {
                    
                    // Speel nu
                    Button {
                        
                        if let url = library.getURL(for: song) {
                            
                            library.markAsPlayed(song)
                            
                            audioPlayer.play(
                                song: song,
                                url: url,
                                queue: library.songs
                            )
                        }
                        
                        dismiss()
                        
                    } label: {
                        
                        Label(
                            LocalizedStringKey("action_play_now"),
                            systemImage: "play.fill"
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    }
                    
                    
                    // Speel als volgende
                    Button {
                        
                        audioPlayer.playNext(song)
                        dismiss()
                        
                    } label: {
                        
                        Label(
                            LocalizedStringKey("action_play_next"),
                            systemImage: "text.insert"
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    }
                    
                    
                    // Voeg toe aan wachtrij
                    Button {
                        
                        audioPlayer.addToQueue(song)
                        dismiss()
                        
                    } label: {
                        
                        Label(
                            LocalizedStringKey("action_add_to_queue"),
                            systemImage: "text.append"
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    }
                    
                    
                    // Voeg toe aan playlist
                    Button {
                        
                        library.songToAddToPlaylist = song
                        dismiss()
                        
                    } label: {
                        
                        Label(
                            LocalizedStringKey("action_add_to_playlist"),
                            systemImage: "music.note.list"
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    }
                    
                    
                    // Favorieten
                    Button {
                        
                        library.toggleFavorite(song)
                        dismiss()
                        
                    } label: {
                        
                        Label(
                            library.isFavorite(song)
                            ? LocalizedStringKey("action_remove_from_favorites")
                            : LocalizedStringKey("action_add_to_favorites"),
                            systemImage:
                                library.isFavorite(song)
                            ? "heart.slash"
                            : "heart"
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    }
                    
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    
                    // Wijzig info
                    Button {
                        
                        library.editingSong = song
                        library.showEditSheet = true
                        dismiss()
                        
                    } label: {
                        
                        Label(
                            LocalizedStringKey("action_edit_info"),
                            systemImage: "pencil"
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    }
                    
                    
                    // Verwijder
                    Button(role: .destructive) {
                        
                        showDeleteConfirmation = true
                        
                    } label: {
                        
                        Label(
                            LocalizedStringKey("action_delete"),
                            systemImage: "trash"
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    }
                    .confirmationDialog(
                        LocalizedStringKey("alert_delete_single_song_title"),
                        isPresented: $showDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        
                        Button(
                            LocalizedStringKey("action_delete"),
                            role: .destructive
                        ) {
                            
                            library.deleteSong(song)
                            dismiss()
                        }
                        
                        Button(
                            LocalizedStringKey("action_cancel"),
                            role: .cancel
                        ) {
                            
                        }
                        
                    } message: {
                        
                        Text("alert_delete_single_song_message \(song.title)")
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .tint(.primary)
        .presentationDetents([
            .height(450)
        ])
        .presentationCornerRadius(30)
        .presentationBackground(.thinMaterial)
    }
}