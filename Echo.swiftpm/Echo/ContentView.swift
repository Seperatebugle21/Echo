import SwiftUI
import Observation

struct ContentView: View {
    @State private var miniPlayerHidden = false
    @State private var selectedTab = 0
    @State private var presentation = MiniPlayerPresentation()

    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .modifier(
                    MiniPlayerDockModifier(
                        isMinimized: $miniPlayerHidden,
                        isActive: selectedTab == 0
                    )
                )
                .tag(0)
                .tabItem {
                    Label(
                        "contentview_home",
                        systemImage: "house.fill"
                    )
                }

            LibraryView()
                .modifier(
                    MiniPlayerDockModifier(
                        isMinimized: $miniPlayerHidden,
                        isActive: selectedTab == 1
                    )
                )
                .tag(1)
                .tabItem {
                    Label(
                        "contentview_library",
                        systemImage: "square.stack.fill"
                    )
                }

            FetchView()
                .modifier(
                    MiniPlayerDockModifier(
                        isMinimized: $miniPlayerHidden,
                        isActive: selectedTab == 2
                    )
                )
                .tag(2)
                .tabItem {
                    Label(
                        "contentview_fetch",
                        systemImage: "arrow.down.circle"
                    )
                }

            SearchView()
                .modifier(
                    MiniPlayerDockModifier(
                        isMinimized: $miniPlayerHidden,
                        isActive: selectedTab == 3
                    )
                )
                .tag(3)
                .tabItem {
                    Label(
                        "contentview_search",
                        systemImage: "magnifyingglass"
                    )
                }
        }
        .accessibilityHidden(presentation.isVisible)
        .overlay {
            GeometryReader { safeGeometry in
                GeometryReader { fullGeometry in
                    ZStack(alignment: .topLeading) {
                        Color.clear

                        if presentation.isVisible {
                            ExpandedPlayerSurface(
                                presentation: presentation,
                                bounds: fullGeometry.frame(
                                    in: .global
                                ),
                                safeInsets: safeGeometry.safeAreaInsets
                            )
                        }
                    }
                    .onGeometryChange(
                        for: CGRect.self
                    ) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        presentation.containerFrame = frame
                    }
                }
                .ignoresSafeArea()
            }
            // De oorspronkelijke swipe blijft tijdens het
            // openen eigenaar van de aanraking.
            .allowsHitTesting(presentation.isExpanded)
        }
        .environment(presentation)
        .onChange(of: audioPlayer.currentSong?.id) {
            if audioPlayer.currentSong == nil {
                presentation.reset()
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                presentation.cancelInteraction()
            }
        }
    }
}

private struct MiniPlayerDockModifier: ViewModifier {
    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Environment(MiniPlayerPresentation.self) private var presentation

    @Binding var isMinimized: Bool

    let isActive: Bool

    @State private var lastFrame: CGRect = .zero

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if audioPlayer.currentSong != nil {
                ResizableMiniPlayerDock(
                    isMinimized: $isMinimized
                )
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    lastFrame = frame

                    if isActive && !presentation.isVisible {
                        presentation.dockFrame = frame
                    }
                }
                .onChange(of: isActive) {
                    if isActive {
                        presentation.dockFrame = lastFrame
                    }
                }
                .opacity(presentation.isVisible ? 0 : 1)
                .allowsHitTesting(true)
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
                MiniPlayer {
                    setMinimized(true)
                }
                .frame(
                    width: geometry.size.width,
                    height: 52
                )
                .opacity(isMinimized ? 0 : 1)
                .allowsHitTesting(!isMinimized)
                .accessibilityHidden(isMinimized)

                Button {
                    setMinimized(false)
                } label: {
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
            .frame(
                width: isMinimized ? 52 : geometry.size.width,
                height: 52,
                alignment: .trailing
            )
            .clipShape(.capsule)
            .glassEffect(
                .regular.interactive(),
                in: .capsule
            )
            .frame(
                maxWidth: .infinity,
                alignment: .trailing
            )
            .animation(
                reduceMotion
                    ? .linear(duration: 0.12)
                    : .spring(
                        response: 0.42,
                        dampingFraction: 0.86
                    ),
                value: isMinimized
            )
        }
        .frame(height: 52)
    }

    private func setMinimized(_ value: Bool) {
        isMinimized = value
    }
}

struct MiniPlayerEqualizer: View {
    @Environment(AudioPlayerManager.self) private var audioPlayer

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
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
        .frame(width: 30, height: 30)
    }
}

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

                while !Task.isCancelled && isPlaying {
                    let newHeight = CGFloat.random(
                        in: minHeight...maxHeight
                    )

                    let duration = Double.random(
                        in: 0.08...0.30
                    )

                    let delay = Double.random(
                        in: 0.02...0.20
                    )

                    withAnimation(
                        .easeInOut(duration: duration)
                    ) {
                        height = newHeight
                    }

                    let totalNanoseconds = UInt64(
                        (duration + delay) * 1_000_000_000
                    )

                    try? await Task.sleep(
                        nanoseconds: totalNanoseconds
                    )
                }
            }
    }
}

@Observable
final class MiniPlayerPresentation {
    var dockFrame: CGRect = .zero
    var containerFrame: CGRect = .zero

    private(set) var sourceFrame: CGRect = .zero
    private(set) var progress: CGFloat = 0
    private(set) var isVisible = false
    private(set) var isExpanded = false
    private(set) var isTrackingOpening = false

    private var isTrackingClosing = false
    private var token = UUID()

    private var travel: CGFloat {
        max(
            1,
            sourceFrame.minY - containerFrame.minY
        )
    }

    private func prepare() -> Bool {
        guard
            dockFrame.width > 0,
            containerFrame.height > 0
        else {
            return false
        }

        sourceFrame = dockFrame
        token = UUID()
        isVisible = true

        return true
    }

    func updateOpening(translation: CGFloat) {
        guard !isExpanded else { return }

        if !isTrackingOpening {
            guard
                !isVisible,
                translation < 0,
                prepare()
            else {
                return
            }

            isTrackingOpening = true
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            progress = min(
                1,
                max(0, -translation / travel)
            )
        }
    }

    func finishOpening(
        velocity: CGFloat,
        reduceMotion: Bool
    ) {
        guard isTrackingOpening else { return }

        isTrackingOpening = false

        let open =
            velocity < -650
            || (velocity <= 650 && progress > 0.35)

        settle(
            open: open,
            reduceMotion: reduceMotion
        )
    }

    func cancelOpening(reduceMotion: Bool) {
        guard isTrackingOpening else { return }

        isTrackingOpening = false

        settle(
            open: false,
            reduceMotion: reduceMotion
        )
    }

    func open(reduceMotion: Bool) {
        guard !isVisible, prepare() else { return }

        let openingToken = token

        Task { @MainActor in
            await Task.yield()

            guard
                token == openingToken,
                isVisible
            else {
                return
            }

            settle(
                open: true,
                reduceMotion: reduceMotion
            )
        }
    }

    func close(reduceMotion: Bool) {
        guard isVisible else { return }

        settle(
            open: false,
            reduceMotion: reduceMotion
        )
    }

    func updateClosing(translation: CGFloat) {
        guard isExpanded else { return }

        if !isTrackingClosing {
            isTrackingClosing = true
            token = UUID()
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            progress = min(
                1,
                max(0, 1 - translation / travel)
            )
        }
    }

    func finishClosing(
        velocity: CGFloat,
        reduceMotion: Bool
    ) {
        guard isTrackingClosing else { return }

        isTrackingClosing = false

        let close =
            velocity > 650
            || (velocity >= -650 && progress < 0.65)

        settle(
            open: !close,
            reduceMotion: reduceMotion
        )
    }

    func cancelClosing(reduceMotion: Bool) {
        guard isTrackingClosing else { return }

        isTrackingClosing = false

        settle(
            open: true,
            reduceMotion: reduceMotion
        )
    }

    private func settle(
        open: Bool,
        reduceMotion: Bool
    ) {
        let currentToken = UUID()
        token = currentToken

        let animation: Animation = reduceMotion
            ? .linear(duration: 0.12)
            : .spring(
                response: 0.38,
                dampingFraction: 0.94
            )

        withAnimation(
            animation,
            completionCriteria: .removed
        ) {
            progress = open ? 1 : 0
        } completion: {
            guard self.token == currentToken else {
                return
            }

            self.isExpanded = open
            self.isVisible = open
        }
    }

    func cancelInteraction() {
        guard isTrackingOpening || isTrackingClosing else {
            return
        }

        token = UUID()
        isTrackingOpening = false
        isTrackingClosing = false
        progress = isExpanded ? 1 : 0
        isVisible = isExpanded
    }

    func reset() {
        token = UUID()
        progress = 0
        isVisible = false
        isExpanded = false
        isTrackingOpening = false
        isTrackingClosing = false
    }
}

private struct ExpandedPlayerSurface: View {
    let presentation: MiniPlayerPresentation
    let bounds: CGRect
    let safeInsets: EdgeInsets

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AudioPlayerManager.self) private var audioPlayer

    @AppStorage("showCovers") private var showCovers = true

    private var rectangle: CGRect {
        let source = presentation.sourceFrame.offsetBy(
            dx: -bounds.minX,
            dy: -bounds.minY
        )

        let p = presentation.progress

        return CGRect(
            x: source.minX * (1 - p),
            y: source.minY * (1 - p),
            width: source.width
                + (bounds.width - source.width) * p,
            height: source.height
                + (bounds.height - source.height) * p
        )
    }

    var body: some View {
        let rect = rectangle
        let p = presentation.progress

        let shape = RoundedRectangle(
            cornerRadius: 26 * (1 - p),
            style: .continuous
        )

        ZStack(alignment: .topLeading) {
            Color.black.opacity(min(1, p * 4))

            NowPlayingView(
                onClose: {
                    presentation.close(
                        reduceMotion: reduceMotion
                    )
                },
                onCloseDrag: {
                    presentation.updateClosing(
                        translation: $0
                    )
                },
                onCloseDragEnd: {
                    presentation.finishClosing(
                        velocity: $0,
                        reduceMotion: reduceMotion
                    )
                },
                onCloseDragCancel: {
                    presentation.cancelClosing(
                        reduceMotion: reduceMotion
                    )
                }
            )
            .padding(.top, safeInsets.top)
            .padding(.bottom, safeInsets.bottom)
            .frame(
                width: bounds.width,
                height: bounds.height
            )
            .opacity(min(1, p * 4))
            .accessibilityHidden(!presentation.isExpanded)

            if let song = audioPlayer.currentSong {
                HStack(spacing: 8) {
                    MiniPlayerArtwork(
                        data: showCovers ? song.coverData : nil
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title)
                            .font(
                                .system(size: 14, weight: .medium)
                            )

                        Text(song.artist)
                            .font(
                                .system(size: 11, weight: .medium)
                            )
                    }
                    .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(
                    width: presentation.sourceFrame.width,
                    height: 52
                )
                .opacity(max(0, 1 - p * 6))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(
            width: max(1, rect.width),
            height: max(1, rect.height),
            alignment: .topLeading
        )
        .clipShape(shape)
        .glassEffect(.regular, in: shape)
        .offset(x: rect.minX, y: rect.minY)
        .accessibilityAction(.escape) {
            presentation.close(
                reduceMotion: reduceMotion
            )
        }
    }
}

#Preview {
    ContentView()
        .environment(MusicLibraryManager())
        .environment(AudioPlayerManager())
}