import SwiftUI

struct NowPlayingView: View {
    
    @Environment(AudioPlayerManager.self)
    private var audioPlayer
    
    @Environment(\.dismiss)
    private var dismiss
    
    @State private var showQueue = false
    @State private var showPlaylistPicker = false
    @State private var showLyrics = false
    
    var body: some View {
        
        ZStack {
            
            // MARK: - Background
            
            nowPlayingBackground
            
            
            // MARK: - Content
            
            VStack(spacing: 25) {
                
                // MARK: Close Button
                
                HStack {
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        
                        Image(
                            systemName: "chevron.down"
                        )
                        .font(
                            .system(
                                size: 24,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "dismiss_action"
                        )
                    )
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                
                Spacer(minLength: 0)
                
                
                // MARK: - Artwork
                
                artwork
                
                
                // MARK: - Song Info
                
                if let song = audioPlayer.currentSong {
                    
                    HStack(alignment: .center) {
                        
                        VStack(
                            alignment: .leading,
                            spacing: 5
                        ) {
                            
                            Text(song.title)
                                .font(
                                    .title2
                                        .weight(.bold)
                                )
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            
                            Text(song.artist)
                                .font(.body)
                                .foregroundStyle(
                                    .white.opacity(0.68)
                                )
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Button {
                            showPlaylistPicker = true
                        } label: {
                            
                            Image(
                                systemName:
                                    "music.note.list"
                            )
                            .font(
                                .title3
                                    .weight(.medium)
                            )
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            LocalizedStringKey(
                                "add_to_playlist_action"
                            )
                        )
                    }
                    .padding(.horizontal, 28)
                }
                
                
                // MARK: - Progress
                
                VStack(spacing: 5) {
                    
                    Slider(
                        value: Binding(
                            get: {
                                audioPlayer.currentTime
                            },
                            set: { value in
                                audioPlayer.seek(
                                    to: value
                                )
                            }
                        ),
                        in: 0...max(
                            audioPlayer.duration,
                            1
                        ),
                        onEditingChanged: { editing in
                            
                            if editing {
                                
                                audioPlayer
                                    .pauseForSeeking()
                                
                            } else {
                                
                                audioPlayer
                                    .resumeAfterSeeking()
                            }
                        }
                    )
                    .tint(.white)
                    
                    HStack {
                        
                        Text(
                            formatTime(
                                audioPlayer.currentTime
                            )
                        )
                        
                        Spacer()
                        
                        Text(
                            formatTime(
                                audioPlayer.duration
                            )
                        )
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(
                        .white.opacity(0.65)
                    )
                }
                .padding(.horizontal, 28)
                
                
                // MARK: - Playback Controls
                
                HStack(spacing: 35) {
                    
                    // Shuffle
                    
                    Button {
                        audioPlayer.toggleShuffle()
                    } label: {
                        
                        Image(
                            systemName: "shuffle"
                        )
                        .font(.title2)
                        .foregroundStyle(
                            audioPlayer.shuffleEnabled
                            ? Color.red
                            : Color.white
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "shuffle_action"
                        )
                    )
                    
                    
                    // Previous
                    
                    Button {
                        audioPlayer.previous()
                    } label: {
                        
                        Image(
                            systemName:
                                "backward.fill"
                        )
                        .font(.title2)
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "previous_track_action"
                        )
                    )
                    
                    
                    // Play / Pause
                    
                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {
                        
                        Image(
                            systemName:
                                audioPlayer.isPlaying
                                ? "pause.circle.fill"
                                : "play.circle.fill"
                        )
                        .font(
                            .system(size: 70)
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        audioPlayer.isPlaying
                        ? LocalizedStringKey(
                            "pause_action"
                        )
                        : LocalizedStringKey(
                            "play_action"
                        )
                    )
                    
                    
                    // Next
                    
                    Button {
                        audioPlayer.next()
                    } label: {
                        
                        Image(
                            systemName:
                                "forward.fill"
                        )
                        .font(.title2)
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "next_track_action"
                        )
                    )
                    
                    
                    // Repeat
                    
                    Button {
                        audioPlayer.toggleRepeat()
                    } label: {
                        
                        Image(
                            systemName:
                                audioPlayer.repeatMode
                                == .one
                                ? "repeat.1"
                                : "repeat"
                        )
                        .font(.title2)
                        .foregroundStyle(
                            audioPlayer.repeatMode
                            == .off
                            ? Color.white
                            : Color.red
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "repeat_action"
                        )
                    )
                }
                
                
                // MARK: - Bottom Actions
                
                HStack {
                    
                    // AirPlay
                    
                    AirPlayButton(
                        tintColor: .white,
                        activeTintColor: .blue
                    )
                    .frame(
                        width: 30,
                        height: 30
                    )
                    
                    
                    Spacer()
                    
                    
                    // Add to Playlist
                    
                    Button {
                        showPlaylistPicker = true
                    } label: {
                        
                        Image(
                            systemName:
                                "music.note.list"
                        )
                        .font(.title3)
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "add_to_playlist_action"
                        )
                    )
                    
                    
                    // Lyrics
                    
                    Button {
                        showLyrics = true
                    } label: {
                        
                        Image(
                            systemName:
                                "quote.bubble"
                        )
                        .font(.title3)
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "lyrics_action"
                        )
                    )
                    
                    
                    // Queue
                    
                    Button {
                        showQueue = true
                    } label: {
                        
                        Image(
                            systemName:
                                "list.bullet"
                        )
                        .font(.title3)
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "queue_action"
                        )
                    )
                }
                .padding(.horizontal, 30)
                
                
                Spacer(minLength: 12)
            }
        }
        
        // MARK: - Queue Sheet
        
        .sheet(
            isPresented: $showQueue
        ) {
            QueueView()
        }
        
        
        // MARK: - Playlist Sheet
        
        .sheet(
            isPresented:
                $showPlaylistPicker
        ) {
            
            if let song =
                audioPlayer.currentSong
            {
                
                PlaylistPickerView(
                    song: song
                )
            }
        }
        
        
        // MARK: - Lyrics Sheet
        
        .sheet(
            isPresented: $showLyrics
        ) {
            
            NavigationStack {
                LyricsView()
            }
        }
    }
    
    
    // MARK: - Background
    
    @ViewBuilder
    private var nowPlayingBackground: some View {
        
        if
            let song = audioPlayer.currentSong,
            let data =
                song.coverData
                ?? song.imageData,
            let image =
                UIImage(data: data)
        {
            
            GeometryReader { geometry in
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width:
                            geometry.size.width,
                        height:
                            geometry.size.height
                    )
                    .scaleEffect(1.35)
                    .blur(radius: 65)
                    .saturation(1.25)
                    .overlay {
                        
                        Color.black
                            .opacity(0.42)
                    }
                    .overlay {
                        
                        LinearGradient(
                            colors: [
                                Color.black
                                    .opacity(0.08),
                                Color.black
                                    .opacity(0.18),
                                Color.black
                                    .opacity(0.58)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .clipped()
            }
            .ignoresSafeArea()
            
        } else {
            
            ZStack {
                
                Color.black
                
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
            .ignoresSafeArea()
        }
    }
    
    
    // MARK: - Artwork
    
    @ViewBuilder
    private var artwork: some View {
        
        if
            let song = audioPlayer.currentSong,
            let data =
                song.coverData
                ?? song.imageData,
            let image =
                UIImage(data: data)
        {
            
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(
                    width: 280,
                    height: 280
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
                .shadow(
                    color:
                        .black.opacity(0.30),
                    radius: 22,
                    y: 12
                )
            
        } else {
            
            ZStack {
                
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .fill(
                    .white.opacity(0.12)
                )
                
                Image(
                    systemName:
                        "music.note"
                )
                .font(
                    .system(size: 100)
                )
                .foregroundStyle(
                    .white.opacity(0.8)
                )
            }
            .frame(
                width: 280,
                height: 280
            )
        }
    }
    
    
    // MARK: - Time
    
    private func formatTime(
        _ time: Double
    ) -> String {
        
        guard
            time.isFinite,
            time >= 0
        else {
            return "0:00"
        }
        
        let minutes =
            Int(time) / 60
        
        let seconds =
            Int(time) % 60
        
        return String(
            format: "%d:%02d",
            minutes,
            seconds
        )
    }
}
