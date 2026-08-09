import SwiftUI
import UIKit

struct ContentView: View {
    
    @State private var miniPlayerHidden = false
    
    
    var body: some View {
        
        TabView {
            
            SongsView()
                .tabItem {
                    Label(
                        "Nummers",
                        systemImage: "music.note.list"
                    )
                }
            
            PlaylistsView()
                .tabItem {
                    Label(
                        "Playlists",
                        systemImage: "music.note.house"
                    )
                }
            
            SettingsView()
                .tabItem {
                    Label(
                        "Instellingen",
                        systemImage: "gearshape"
                    )
                }
        }
        
        // Alleen de echte UITabBar wordt verschoven.
        .background {
            TabBarShiftAnimator(
                isShifted: miniPlayerHidden
            )
        }
        
        
        // MARK: - MiniPlayer
        
        .overlay(alignment: .bottom) {
            
            ZStack {
                
                // MARK: Normal MiniPlayer
                
                if !miniPlayerHidden {
                    
                    MiniPlayer {
                        
                        miniPlayerHidden = true
                        
                    }
                    .padding(.bottom, 70)
                    .padding(.horizontal)
                    .transition(
                        .move(edge: .bottom)
                        .combined(with: .opacity)
                    )
                }
                
                
                // MARK: MiniPlayer button
                
                if miniPlayerHidden {
                    
                    HStack {
                        
                        Spacer()
                        
                        Button {
                            
                            miniPlayerHidden = false
                            
                        } label: {
                            
                            MiniPlayerEqualizer()
                                .scaleEffect(0.88)
                                .foregroundColor(.primary)
                                .frame(
                                    width: 61,
                                    height: 61
                                )
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            .regular.interactive()
                        )
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: 18
                            )
                        )
                       .padding(Edge.Set.trailing, 10)
                       .padding(Edge.Set.bottom, -5)

                    }
                    .zIndex(100)
                    .transition(
                        .scale(scale: 0.7)
                        .combined(with: .opacity)
                    )
                }
            }
            .zIndex(100)
        }
        
        .animation(
            .spring(
                response: 0.4,
                dampingFraction: 0.85
            ),
            value: miniPlayerHidden
        )
    }
}


// MARK: - MiniPlayer Equalizer

// MARK: - MiniPlayer Equalizer

struct MiniPlayerEqualizer: View {
    
    @Environment(AudioPlayerManager.self)
    private var audioPlayer
    
    var body: some View {
        
        HStack(
            alignment: .center,
            spacing: 4
        ) {
            
            RandomBar(
                isPlaying: audioPlayer.isPlaying,
                minHeight: 5,
                maxHeight: 25
            )
            
            RandomBar(
                isPlaying: audioPlayer.isPlaying,
                minHeight: 7,
                maxHeight: 18
            )
            
            RandomBar(
                isPlaying: audioPlayer.isPlaying,
                minHeight: 4,
                maxHeight: 28
            )
            
            RandomBar(
                isPlaying: audioPlayer.isPlaying,
                minHeight: 6,
                maxHeight: 22
            )
        }
        .frame(
            width: 30,
            height: 30
        )
    }
}


// MARK: - Completely Independent Random Bar

struct RandomBar: View {
    
    let isPlaying: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    
    @State private var height: CGFloat = 8
    @State private var timer: Timer?
    
    
    var body: some View {
        
        Capsule()
            .frame(
                width: 4,
                height: isPlaying ? height : 8
            )
            .onAppear {
                startRandomAnimation()
            }
            .onDisappear {
                stopAnimation()
            }
            .onChange(of: isPlaying) { _, playing in
                
                stopAnimation()
                
                if playing {
                    startRandomAnimation()
                } else {
                    withAnimation(.easeOut(duration: 0.15)) {
                        height = 8
                    }
                }
            }
    }
    
    
    private func startRandomAnimation() {
        
        stopAnimation()
        
        guard isPlaying else {
            return
        }
        
        // Iedere bar start op een andere willekeurige hoogte.
        height = CGFloat.random(
            in: minHeight...maxHeight
        )
        
        scheduleNextAnimation()
    }
    
    
    private func scheduleNextAnimation() {
        
        guard isPlaying else {
            return
        }
        
        // Volledig willekeurige nieuwe hoogte.
        let newHeight = CGFloat.random(
            in: minHeight...maxHeight
        )
        
        // Iedere bar krijgt ook een willekeurige
        // animatiesnelheid.
        let duration = Double.random(
            in: 0.08...0.30
        )
        
        // Willekeurige pauze voordat hij opnieuw beweegt.
        let delay = Double.random(
            in: 0.02...0.20
        )
        
        withAnimation(
            .easeInOut(
                duration: duration
            )
        ) {
            height = newHeight
        }
        
        timer = Timer.scheduledTimer(
            withTimeInterval: duration + delay,
            repeats: false
        ) { _ in
            
            DispatchQueue.main.async {
                scheduleNextAnimation()
            }
        }
    }
    
    
    private func stopAnimation() {
        
        timer?.invalidate()
        timer = nil
    }
}


// MARK: - TabBar Animator

struct TabBarShiftAnimator: UIViewRepresentable {
    
    let isShifted: Bool
    
    
    func makeUIView(
        context: Context
    ) -> UIView {
        
        let view = UIView()
        
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        
        return view
    }
    
    
    func updateUIView(
        _ uiView: UIView,
        context: Context
    ) {
        
        DispatchQueue.main.async {
            
            guard let tabBar = findTabBar(
                from: uiView
            ) else {
                return
            }
            
            
            let shift: CGFloat = isShifted
            ? -32
            : 0
            
            
            UIView.animate(
                withDuration: 0.4,
                delay: 0,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0.2,
                options: [
                    .beginFromCurrentState,
                    .allowUserInteraction
                ]
            ) {
                
                tabBar.transform = CGAffineTransform(
                    translationX: shift,
                    y: 0
                )
            }
        }
    }
    
    
    private func findTabBar(
        from view: UIView
    ) -> UITabBar? {
        
        if let tabBar = view as? UITabBar {
            return tabBar
        }
        
        
        var current: UIView? = view
        
        while let parent = current?.superview {
            
            if let tabBar = findTabBar(
                in: parent
            ) {
                return tabBar
            }
            
            current = parent
        }
        
        
        return nil
    }
    
    
    private func findTabBar(
        in view: UIView
    ) -> UITabBar? {
        
        for subview in view.subviews {
            
            if let tabBar = subview as? UITabBar {
                return tabBar
            }
            
            if let result = findTabBar(
                in: subview
            ) {
                return result
            }
        }
        
        return nil
    }
}


// MARK: - Preview

#Preview {
    
    ContentView()
        .environment(
            MusicLibraryManager()
        )
        .environment(
            AudioPlayerManager()
        )
}
