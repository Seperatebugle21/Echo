import SwiftUI

struct ContentView: View {
    @Environment(AudioPlayerManager.self) private var audioPlayer
    @State private var miniPlayerHidden = false

    var body: some View {
        TabView {

            HomeView()
                .tabItem {
                    Label(
                        "contentview_home",
                        systemImage: "house.fill"
                    )
                }

            LibraryView()
                .tabItem {
                    Label(
                        "contentview_library",
                        systemImage: "square.stack.fill"
                    )
                }

            FetchView()
                .tabItem {
                    Label(
                        "contentview_fetch",
                        systemImage: "arrow.down.circle"
                    )
                }

            SearchView()
                .tabItem {
                    Label(
                        "contentview_search",
                        systemImage: "magnifyingglass"
                    )
                }
        }

        .modifier(MiniPlayerAccessoryModifier(
            isEnabled: audioPlayer.currentSong != nil,
            isMinimized: $miniPlayerHidden
        ))
        .animation(
            .spring(response: 0.4, dampingFraction: 0.85),
            value: miniPlayerHidden
        )
    }
}

// The TabView supplies the Liquid Glass surface and positions the player.
private struct MiniPlayerAccessoryModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var isMinimized: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content
                .tabViewBottomAccessory(isEnabled: isEnabled) {
                    accessory
                }
        } else {
            // iOS 26.0 has no isEnabled overload.
            content
                .tabViewBottomAccessory {
                    if isEnabled {
                        accessory
                    }
                }
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if isMinimized {
            Button {
                isMinimized = false
            } label: {
                MiniPlayerEqualizer()
                    .scaleEffect(0.88)
                    .foregroundStyle(.primary)
                    .frame(width: 61, height: 57)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open miniplayer")
        } else {
            MiniPlayer {
                isMinimized = true
            }
        }
    }
}

// MARK: - Mini Player Equalizer

struct MiniPlayerEqualizer: View {

    @Environment(
        AudioPlayerManager.self
    )
    private var audioPlayer


    var body: some View {

        HStack(
            alignment: .center,
            spacing: 4
        ) {

            RandomBar(
                isPlaying:
                    audioPlayer.isPlaying,
                minHeight: 5,
                maxHeight: 25
            )

            RandomBar(
                isPlaying:
                    audioPlayer.isPlaying,
                minHeight: 7,
                maxHeight: 18
            )

            RandomBar(
                isPlaying:
                    audioPlayer.isPlaying,
                minHeight: 4,
                maxHeight: 28
            )

            RandomBar(
                isPlaying:
                    audioPlayer.isPlaying,
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


// MARK: - Equalizer Bar

struct RandomBar: View {

    let isPlaying: Bool

    let minHeight: CGFloat

    let maxHeight: CGFloat


    @State private var height:
        CGFloat = 8


    var body: some View {

        Capsule()

            .frame(
                width: 4,
                height:
                    isPlaying
                    ? height
                    : 8
            )

            .task(
                id:
                    isPlaying
            ) {

                guard isPlaying else {

                    withAnimation(
                        .easeOut(
                            duration: 0.15
                        )
                    ) {

                        height = 8
                    }

                    return
                }


                while
                    !Task.isCancelled
                    &&
                    isPlaying
                {

                    let newHeight =
                        CGFloat.random(
                            in:
                                minHeight
                                ...
                                maxHeight
                        )


                    let duration =
                        Double.random(
                            in:
                                0.08
                                ...
                                0.30
                        )


                    let delay =
                        Double.random(
                            in:
                                0.02
                                ...
                                0.20
                        )


                    withAnimation(
                        .easeInOut(
                            duration:
                                duration
                        )
                    ) {

                        height =
                            newHeight
                    }


                    let totalNanoseconds =
                        UInt64(
                            (
                                duration
                                +
                                delay
                            )
                            *
                            1_000_000_000
                        )


                    try?
                        await Task.sleep(
                            nanoseconds:
                                totalNanoseconds
                        )
                }
            }
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

