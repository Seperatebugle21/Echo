import SwiftUI


// MARK: - Custom Full Detent

extension PresentationDetent {
    static let full = PresentationDetent.custom(FullDetent.self)
}

private struct FullDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        context.maxDetentValue
    }
}


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


                AirPlayButton()
                .frame(width: 30, height: 30)
                
                
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

                        if value.translation.height < -50 {
                            
                            showNowPlaying = true
                            
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
            
           .fullScreenCover(isPresented: $showNowPlaying) {
    NowPlayingView()
        .interactiveDismiss(isPresented: $showNowPlaying)
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

struct InteractiveDismiss: ViewModifier {
    @Binding var isPresented: Bool
    @State private var offset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .offset(y: max(offset, 0))
            .background(.black.opacity(1 - min(offset / 400, 0.4)))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            offset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 120 {
                            dismiss()
                        } else {
                            withAnimation(.spring()) {
                                offset = 0
                            }
                        }
                    }
            )
            .animation(.interactiveSpring(), value: offset)
    }
}

extension View {
    func interactiveDismiss(isPresented: Binding<Bool>) -> some View {
        self.modifier(InteractiveDismiss(isPresented: isPresented))
    }
}
