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
            
            if songs.isEmpty {
                
                ContentUnavailableView {
                    Label(
                        "Nog geen favorieten",
                        systemImage: "heart"
                    )
                } description: {
                    Text(
                        "Voeg nummers toe met de plusknop."
                    )
                }
                
            } else {
                
                ForEach(songs) { song in
                    
                    HStack(spacing: 12) {
                        
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
                        
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            
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
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        
                        Button {
                            library.toggleFavorite(song)
                        } label: {
                            Label(
                                "Verwijder",
                                systemImage: "heart.slash"
                            )
                        }
                        .tint(.red)
                    }
                }
            }
        }
        .navigationTitle("Favorieten")
        .toolbar {
            
            ToolbarItem(placement: .topBarTrailing) {
                
                Button {
                    showSongPicker = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showSongPicker) {
            
            SongPickerView(isFavorites: true)
        }
    }
}
