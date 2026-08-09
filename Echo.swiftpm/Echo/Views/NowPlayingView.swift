import SwiftUI

struct NowPlayingView: View {
    
    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Environment(\.dismiss) private var dismiss
    
    @State private var showQueue = false
    @State private var showPlaylistPicker = false
    
    @State private var showLyrics = false
    
    var body: some View {
        
        VStack(spacing: 25) {
            
            
            // Sluit knop
            HStack {
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title2)
                }
                
                Spacer()
            }
            .padding()
            
            
            Spacer()
            
            
            // Albumhoes
            if let song = audioPlayer.currentSong,
               let data = song.coverData,
               let image = UIImage(data: data) {
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: 260,
                        height: 260
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 20
                        )
                    )
                
            } else {
                
                Image(systemName: "music.note")
                    .font(.system(size: 100))
                    .frame(
                        width: 260,
                        height: 260
                    )
                    .background(.thinMaterial)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 20
                        )
                    )
            }
            
            
            
            // Titel + playlist
            if let song = audioPlayer.currentSong {
                
                HStack(alignment: .center) {
                    
                    VStack(alignment: .leading, spacing: 4) {
                        
                        Text(song.title)
                            .font(.title2)
                            .bold()
                            .lineLimit(1)
                        
                        Text(song.artist)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button {
                        showPlaylistPicker = true
                    } label: {
                        Image(systemName: "music.note.list")
                            .font(.title3)
                    }
                }
                .padding(.horizontal)
            }
            
            
            
            // Slider
            VStack {
                
                Slider(
                    value: Binding(
                        get: {
                            audioPlayer.currentTime
                        },
                        set: { value in
                            audioPlayer.seek(to: value)
                        }
                    ),
                    in: 0...max(audioPlayer.duration, 1),
                    onEditingChanged: { editing in
                        
                        if editing {
                            audioPlayer.pauseForSeeking()
                        } else {
                            audioPlayer.resumeAfterSeeking()
                        }
                    }
                )
                
                
                HStack {
                    
                    Text(formatTime(audioPlayer.currentTime))
                    
                    Spacer()
                    
                    Text(formatTime(audioPlayer.duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            
            
            
            
            // Bedieningsknoppen
            HStack(spacing: 35) {
                
                
                Button {
                    audioPlayer.toggleShuffle()
                } label: {
                    
                    Image(systemName: "shuffle")
                        .font(.title2)
                        .foregroundColor(
                            audioPlayer.shuffleEnabled
                            ? .red
                            : .primary
                        )
                }
                
                
                Button {
                    audioPlayer.previous()
                } label: {
                    
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                
                
                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    
                    Image(systemName:
                            audioPlayer.isPlaying
                          ? "pause.circle.fill"
                          : "play.circle.fill"
                    )
                    .font(.system(size: 70))
                }
                
                
                Button {
                    audioPlayer.next()
                } label: {
                    
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                
                
                Button {
                    audioPlayer.toggleRepeat()
                } label: {
                    
                    Image(
                        systemName:
                            audioPlayer.repeatMode == .one
                        ? "repeat.1"
                        : "repeat"
                    )
                    .font(.title2)
                    .foregroundColor(
                        audioPlayer.repeatMode == .off
                        ? .primary
                        : .red
                    )
                }
            }
            
            
            
            
          
            // Onderste rij
            HStack {
                
                AirPlayButton()
                    .frame(width: 30, height: 30)
                
                
                Spacer()
                
                
                Button {
                    showLyrics = true
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.title3)
                }
                .offset(x: -8)
                
                Button {
                    showQueue = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                }
                .sheet(isPresented: $showQueue) {
                    QueueView()
                }
                
                
                .sheet(isPresented: $showPlaylistPicker) {
                    
                    if let song = audioPlayer.currentSong {
                        PlaylistPickerView(song: song)
                    }
                }
                
                .sheet(isPresented: $showLyrics) {
                    NavigationStack {
                        LyricsView()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.horizontal)
            
            
            Spacer()
        }
    }
    
    
    
    func formatTime(_ time: Double) -> String {
        
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        
        return String(
            format: "%d:%02d",
            minutes,
            seconds
        )
    }
}
