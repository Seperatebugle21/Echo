import SwiftUI


struct MiniPlayer: View {
    let onMinimize: () -> Void
    
    @Environment(AudioPlayerManager.self) private var audioPlayer
    
    @State private var showNowPlaying = false
    @State private var transitionDirection: AudioPlayerManager.PlaybackDirection = .next
    @State private var displayedSong: Song?
    
    @AppStorage("showCovers") private var showCovers = true
    
    
    
    
    
    var body: some View {
        
        if let song = audioPlayer.currentSong {
            
            HStack(spacing: 10) {
                
                // MARK: - Animated song
                
                ZStack {
                    
                    if let displayedSong {
                        
                        songContent(displayedSong)
                            .id(displayedSong.id)
                            .transition(
                                songTransition
                            )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .clipped()
                
                
                // MARK: - Play / Pause
                
                Button {
                    audioPlayer.togglePlayPause()
                    
                } label: {
                    
                    Image(
                        systemName:
                            audioPlayer.isPlaying
                        ? "pause.fill"
                        : "play.fill"
                    )
                    .font(.title2)
                    .frame(
                        width: 40,
                        height: 40
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            
            
            // MARK: - Liquid Glass
            
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            
            .overlay {
                
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .stroke(
                    .white.opacity(0.12),
                    lineWidth: 0.7
                )
            }
            
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            
            .shadow(
                radius: 12,
                y: 5
            )
            
            .padding(.horizontal)
            
            
            // MARK: - Song changed
            
            .onChange(of: song.id) {
                
                transitionDirection =
                audioPlayer.lastPlaybackDirection
                
                withAnimation(
                    .spring(
                        response: 0.36,
                        dampingFraction: 0.88
                    )
                ) {
                    displayedSong = song
                }
            }
            
        
            
            // MARK: - Initial song
            
            .onAppear {
                
                if displayedSong == nil {
                    displayedSong = song
                }
            }
            
            
            // MARK: - Open Now Playing
            
            .onTapGesture {
                showNowPlaying = true
            }
            
            
            // MARK: - Swipe
            
            .gesture(
                DragGesture()
                    .onEnded { value in
                        
                        // Naar beneden → MiniPlayer minimaliseren
                        if value.translation.height > 50 {
                            
                            onMinimize()
                            
                            return
                        }
                        
                        
                        // Naar links → volgend nummer
                        if value.translation.width < -50 {
                            
                            audioPlayer.next()
                            
                            return
                        }
                        
                        
                        // Naar rechts → vorig nummer
                        if value.translation.width > 50 {
                            
                            audioPlayer.previous()
                        }
                    }
            )
            
            
            // MARK: - Now Playing
            
            .sheet(
                isPresented: $showNowPlaying
            ) {
                NowPlayingView()
            }
        }
    }
    
    
    // MARK: - Transition
    
    private var songTransition: AnyTransition {
        
        switch transitionDirection {
            
        case .next:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
            
        case .previous:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
            
        case .fade:
            return .opacity
        }
    }
    
    
    // MARK: - Song Content
    
    @ViewBuilder
    private func songContent(
        _ song: Song
    ) -> some View {
        
        HStack(spacing: 10) {
            
            // MARK: Cover
            
            Group {
                
                if showCovers,
                   let data = song.coverData,
                   let image = UIImage(data: data) {
                    
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                    
                } else {
                    
                    Image(
                        systemName: "music.note"
                    )
                    .font(.title2)
                    .frame(
                        width: 45,
                        height: 45
                    )
                    .background(
                        .thinMaterial
                    )
                }
            }
            .frame(
                width: 45,
                height: 45
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )
            
            
            // MARK: Titel + artiest
            
            VStack(
                alignment: .leading,
                spacing: 1
            ) {
                
                ScrollingText(
                    text: song.title
                )
                .frame(
                    height: 22
                )
                
                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
    }
}
