import SwiftUI

struct FavoritesView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    @Environment(AudioPlayerManager.self) private var audioPlayer
    
    @State private var showSongPicker = false
    
    var songs: [Song] {
        library.favoriteSongs
    }
    
    var body: some View {
        
        List {
            
            // MARK: - Header / Knoppen
            if !songs.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        
                        Image(systemName: "heart.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.red)
                            .frame(width: 120, height: 120)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        
                        Text("favorites_song_count \(favoriteSongs.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            
                            Button {
                                playFavorites()
                            } label: {
                                Label("play_all_action", systemImage: "play.fill")
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button {
                                playFavorites(shuffle: true)
                            } label: {
                                Label("shuffle_action", systemImage: "shuffle")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
            }
            
            // MARK: - Lijst van favorieten
            if songs.isEmpty {
                
                ContentUnavailableView {
                    Label(
                        LocalizedStringKey("favorites_empty_title"),
                        systemImage: "heart"
                    )
                } description: {
                    Text(LocalizedStringKey("favorites_empty_description"))
                }
                
            } else {
                
                ForEach(songs) { song in
                    
                    HStack(spacing: 12) {
                        
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
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.headline)
                            
                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let url = library.getURL(for: song) {
                            audioPlayer.play(
                                song: song,
                                url: url,
                                queue: songs
                            )
                            
                            audioPlayer.allSongs = library.songs
                            audioPlayer.fillAutoNext(from: library.songs)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            library.toggleFavorite(song)
                        } label: {
                            Label("remove_action", systemImage: "heart.slash")
                        }
                        .tint(.red)
                    }
                }
            }
        }
        .navigationTitle(Text(LocalizedStringKey("favorites_navigation_title")))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSongPicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(LocalizedStringKey("add_songs_action"))
            }
        }
        .sheet(isPresented: $showSongPicker) {
            SongPickerView(isFavorites: true)
        }
    }
    
    // MARK: - Playback Helper
    func playFavorites(shuffle: Bool = false) {
        var queue = songs
        
        if shuffle {
            queue.shuffle()
        }
        
        guard let firstSong = queue.first else { return }
        
        if let url = library.getURL(for: firstSong) {
            audioPlayer.play(
                song: firstSong,
                url: url,
                queue: queue
            )
            
            audioPlayer.allSongs = library.songs
            audioPlayer.fillAutoNext(from: library.songs)
        }
    }
}
