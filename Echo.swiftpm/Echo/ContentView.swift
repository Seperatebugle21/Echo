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
        
        // Verschuift de echte UITabBar op een stabiele manier
        .background {
            TabBarShiftAnimator(
                isShifted: miniPlayerHidden
            )
        }
        
        // MARK: - MiniPlayer Overlay
        .overlay(alignment: .bottom) {
            ZStack {
                
                // MARK: Normal MiniPlayer
                if !miniPlayerHidden {
                    MiniPlayer {
                        miniPlayerHidden = true
                    }
                    .padding(.bottom, 60)
                    .padding(.horizontal)
                    .transition(
                        .move(edge: .bottom)
                        .combined(with: .opacity)
                    )
                }
                
                // MARK: MiniPlayer Button (Equalizer)
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
                        .padding(.trailing, 20)
                        .offset(y: 12) // Offset gebruikt in plaats van negatieve bottom padding
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


// MARK: - Random Bar (Met Structured Concurrency Task)

struct RandomBar: View {
    
    let isPlaying: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    
    @State private var height: CGFloat = 8
    
    var body: some View {
        Capsule()
            .frame(
                width: 4,
                height: isPlaying ? height : 8
            )
            .task(id: isPlaying) {
                guard isPlaying else {
                    withAnimation(.easeOut(duration: 0.15)) {
                        height = 8
                    }
                    return
                }
                
                // Animatieloop op de achtergrond zonder Timer-leaks
                while !Task.isCancelled && isPlaying {
                    let newHeight = CGFloat.random(in: minHeight...maxHeight)
                    let duration = Double.random(in: 0.08...0.30)
                    let delay = Double.random(in: 0.02...0.20)
                    
                    withAnimation(.easeInOut(duration: duration)) {
                        height = newHeight
                    }
                    
                    let totalNanoseconds = UInt64((duration + delay) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: totalNanoseconds)
                }
            }
    }
}


// MARK: - TabBar Animator (Gerepareerde Positie Tracker)

// MARK: - TabBar Animator (Natieve UITabBar Fix)

struct TabBarShiftAnimator: UIViewRepresentable {
    
    let isShifted: Bool
    
    func makeUIView(context: Context) -> ShiftTrackerView {
        let view = ShiftTrackerView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }
    
    func updateUIView(_ uiView: ShiftTrackerView, context: Context) {
        uiView.isShifted = isShifted
        uiView.updatePosition(animated: context.transaction.animation != nil)
    }
    
    // Custom UIView die direct op het UIKit layout-niveau ingrijpt
    class ShiftTrackerView: UIView {
        
        var isShifted: Bool = false {
            didSet {
                if oldValue != isShifted {
                    setNeedsLayout()
                }
            }
        }
        
        override func didMoveToWindow() {
            super.didMoveToWindow()
            updatePosition(animated: false)
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            // Zonder DispatchQueue.main.async! 
            // Dit zorgt ervoor dat UIKit de tabbar NIET eerst in het midden kan tekenen.
            updatePosition(animated: false)
        }
        
        func updatePosition(animated: Bool) {
            guard let window = self.window,
                  let tabBar = findTabBar(in: window) else { return }
            
            let targetX: CGFloat = isShifted ? -32 : 0
            let targetTransform = CGAffineTransform(translationX: targetX, y: 0)
            
            // Voorkom dubbele updates als de transform al klopt
            if tabBar.transform == targetTransform { return }
            
            if animated {
                UIView.animate(
                    withDuration: 0.4,
                    delay: 0,
                    usingSpringWithDamping: 0.82,
                    initialSpringVelocity: 0.2,
                    options: [.beginFromCurrentState, .allowUserInteraction]
                ) {
                    tabBar.transform = targetTransform
                }
            } else {
                tabBar.transform = targetTransform
            }
        }
        
        private func findTabBar(in view: UIView) -> UITabBar? {
            if let tabBar = view as? UITabBar { return tabBar }
            for subview in view.subviews {
                if let found = findTabBar(in: subview) { return found }
            }
            return nil
        }
    }
}


// MARK: - Preview

#Preview {
    ContentView()
        .environment(MusicLibraryManager())
        .environment(AudioPlayerManager())
}
