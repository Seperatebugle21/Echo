import SwiftUI

struct ContentView: View {
    @State private var miniPlayerHidden = false

    var body: some View {
        TabView {

            HomeView()
                .modifier(MiniPlayerDockModifier(isMinimized: $miniPlayerHidden))
                .tabItem {
                    Label(
                        "contentview_home",
                        systemImage: "house.fill"
                    )
                }

            LibraryView()
                .modifier(MiniPlayerDockModifier(isMinimized: $miniPlayerHidden))
                .tabItem {
                    Label(
                        "contentview_library",
                        systemImage: "square.stack.fill"
                    )
                }

            FetchView()
                .modifier(MiniPlayerDockModifier(isMinimized: $miniPlayerHidden))
                .tabItem {
                    Label(
                        "contentview_fetch",
                        systemImage: "arrow.down.circle"
                    )
                }

            SearchView()
                .modifier(MiniPlayerDockModifier(isMinimized: $miniPlayerHidden))
                .tabItem {
                    Label(
                        "contentview_search",
                        systemImage: "magnifyingglass"
                    )
                }
        }

    }
}

// Attach to each tab's content: its bottom safe area ends ABOVE the tab bar.
// A custom glass surface can shrink in width; the system accessory cannot.
private struct MiniPlayerDockModifier: ViewModifier {
    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Binding var isMinimized: Bool

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if audioPlayer.currentSong != nil {
                ResizableMiniPlayerDock(isMinimized: $isMinimized)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
        }
    }
}

private struct ResizableMiniPlayerDock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isMinimized: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                // Keep a full-width layout during the morph so text never squashes.
                MiniPlayer { setMinimized(true) }
                    .frame(width: geometry.size.width, height: 52)
                    .opacity(isMinimized ? 0 : 1)
                    .allowsHitTesting(!isMinimized)
                    .accessibilityHidden(isMinimized)

                Button { setMinimized(false) } label: {
                    MiniPlayerEqualizer()
                        .scaleEffect(0.8)
                        .frame(width: 52, height: 52)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open miniplayer")
                .opacity(isMinimized ? 1 : 0)
                .scaleEffect(isMinimized ? 1 : 0.65)
                .allowsHitTesting(isMinimized)
                .accessibilityHidden(!isMinimized)
            }
            .frame(width: isMinimized ? 52 : geometry.size.width,
                   height: 52, alignment: .trailing)
            .clipShape(.capsule)
            .glassEffect(.regular.interactive(), in: .capsule)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .animation(reduceMotion ? .linear(duration: 0.12)
                       : .spring(response: 0.42, dampingFraction: 0.86),
                       value: isMinimized)
        }
        .frame(height: 52)
    }

    private func setMinimized(_ value: Bool) {
        isMinimized = value
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
