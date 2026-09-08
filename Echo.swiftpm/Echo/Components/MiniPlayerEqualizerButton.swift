import SwiftUI

struct MiniPlayerEqualizerButton: View {
    
    @Environment(AudioPlayerManager.self)
    private var audioPlayer
    
    let action: () -> Void
    
    
    var body: some View {
        
        Button {
            action()
        } label: {
            
            EqualizerView(
                isPlaying: audioPlayer.isPlaying
            )
            .frame(
                width: 48,
                height: 48
            )
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.interactive()
        )
    }
}


// MARK: - Equalizer

struct EqualizerView: View {
    
    let isPlaying: Bool
    
    var body: some View {
        
        HStack(
            alignment: .center,
            spacing: 3
        ) {
            
            EqualizerBar(
                isPlaying: isPlaying
            )
            
            EqualizerBar(
                isPlaying: isPlaying
            )
            
            EqualizerBar(
                isPlaying: isPlaying
            )
            
            EqualizerBar(
                isPlaying: isPlaying
            )
        }
        .frame(
            width: 25,
            height: 25
        )
    }
}


// MARK: - One Completely Independent Bar

struct EqualizerBar: View {
    
    let isPlaying: Bool
    
    @State private var height: CGFloat = 8
    @State private var animationID = UUID()
    
    
    var body: some View {
        
        Capsule()
            .frame(
                width: 4,
                height: isPlaying ? height : 8
            )
            .onAppear {
                
                if isPlaying {
                    animate()
                }
            }
            .onChange(
                of: isPlaying
            ) { _, playing in
                
                if playing {
                    animate()
                } else {
                    height = 8
                }
            }
    }
    
    
    private func animate() {
        
        let newHeight = CGFloat.random(
            in: 4...24
        )
        
        let duration = Double.random(
            in: 0.08...0.30
        )
        
        let delay = Double.random(
            in: 0.02...0.25
        )
        
        
        withAnimation(
            .easeInOut(
                duration: duration
            )
        ) {
            height = newHeight
        }
        
        
        DispatchQueue.main.asyncAfter(
            deadline: .now()
            + duration
            + delay
        ) {
            
            guard isPlaying else {
                return
            }
            
            animate()
        }
    }
}
