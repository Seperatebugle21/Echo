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
                .modifier(MiniPlayerDockModifier(isMinimized: $miniPlayerHidden, isActive: selectedTab == 0))
                .tag(0)
                .tabItem {
                    Label(
                        "contentview_home",
                        systemImage: "house.fill"
                    )
                }

            LibraryView()
                .modifier(MiniPlayerDockModifier(isMinimized: $miniPlayerHidden, isActive: selectedTab == 1))
                .tag(1)
                .tabItem {
                    Label(
                        "contentview_library",
                        systemImage: "square.stack.fill"
                    )
                }

            FetchView()
                .modifier(MiniPlayerDockModifier(isMinimized: $miniPlayerHidden, isActive: selectedTab == 2))
                .tag(2)
                .tabItem {
                    Label(
                        "contentview_fetch",
                        systemImage: "arrow.down.circle"
                    )
                }

            SearchView()
                .modifier(MiniPlayerDockModifier(isMinimized: $miniPlayerHidden, isActive: selectedTab == 3))
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
                        Color.clear.allowsHitTesting(false)
                        // One persistent player; tabs only report its reserved space.
                        let slot = presentation.dockSlotFrame
                        ResizableMiniPlayerDock(
                            isMinimized: $miniPlayerHidden, isActive: true
                        )
                        .frame(width: max(68, slot.width - 16), height: 64)
                        .offset(
                            x: slot.minX - fullGeometry.frame(in: .global).minX + 8,
                            y: slot.minY - fullGeometry.frame(in: .global).minY
                        )
                        .opacity(audioPlayer.currentSong != nil && slot.width > 0 ? 1 : 0)
                        .allowsHitTesting(audioPlayer.currentSong != nil && slot.width > 0)
                        .accessibilityHidden(presentation.isVisible)

                        if audioPlayer.currentSong != nil {
                            ExpandedPlayerSurface(
                                presentation: presentation,
                                bounds: fullGeometry.frame(in: .global),
                                safeInsets: safeGeometry.safeAreaInsets
                            )
                            .opacity(presentation.isVisible ? 1 : 0)
                            .allowsHitTesting(presentation.isExpanded)
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        presentation.containerFrame = frame
                    }
                }
                .ignoresSafeArea()
            }
        }
        .environment(presentation)
        .onChange(of: audioPlayer.currentSong?.id) {
            if audioPlayer.currentSong == nil { presentation.reset() }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active { presentation.cancelInteraction() }
        }
    }
}

// Attach to each tab's content: its bottom safe area ends ABOVE the tab bar.
// A custom glass surface can shrink in width; the system accessory cannot.
private struct MiniPlayerDockModifier: ViewModifier {
    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Environment(MiniPlayerPresentation.self) private var presentation
    @Binding var isMinimized: Bool
    let isActive: Bool
    @State private var slotFrame: CGRect = .zero

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if audioPlayer.currentSong != nil {
                Color.clear
                    .frame(height: 70)
                    .allowsHitTesting(false)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        slotFrame = frame
                        if isActive && frame.width > 0 {
                            presentation.dockSlotFrame = frame
                        }
                    }
                    .onChange(of: isActive) {
                        if isActive && slotFrame.width > 0 {
                            presentation.dockSlotFrame = slotFrame
                        }
                    }
            }
        }
    }
}

private struct ResizableMiniPlayerDock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(MiniPlayerPresentation.self) private var presentation
    @Binding var isMinimized: Bool
    let isActive: Bool
    @State private var lastFrame: CGRect = .zero

    var body: some View {
        GeometryReader { geometry in
            let expandedWidth = max(52, geometry.size.width - 16)
            let width = isMinimized ? 52 : expandedWidth

            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .trailing) {
                    MiniPlayer { isMinimized = true }
                        .frame(width: expandedWidth, height: 52)
                        .opacity(isMinimized ? 0 : 1)
                        .allowsHitTesting(!isMinimized)
                        .accessibilityHidden(isMinimized)

                    Button { isMinimized = false } label: {
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
                .frame(width: width, height: 52, alignment: .trailing)
                .clipShape(.capsule)
                .glassEffect(.regular.interactive(), in: .capsule)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    lastFrame = frame
                    if isActive && !isMinimized && !presentation.isVisible {
                        presentation.dockFrame = frame
                    }
                }
                .onChange(of: isActive) {
                    if isActive && !isMinimized {
                        presentation.dockFrame = lastFrame
                    }
                }
                .offset(x: -8, y: 12)
                .opacity(presentation.isVisible ? 0 : 1)
                .allowsHitTesting(true)

                MiniPlayerTouchHalo(
                    isMinimized: isMinimized,
                    onRestore: { isMinimized = false },
                    onMinimize: { isMinimized = true }
                )
                .frame(width: width + 16, height: 64)
                .allowsHitTesting(!presentation.isExpanded)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .animation(
                reduceMotion ? .linear(duration: 0.12)
                    : .spring(response: 0.42, dampingFraction: 0.86),
                value: isMinimized
            )
        }
        .frame(height: 64)
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
// Shared by the stationary mini player and the full-window expansion layer.
@Observable
final class MiniPlayerPresentation {
    var dockSlotFrame: CGRect = .zero
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
        max(1, sourceFrame.minY - containerFrame.minY)
    }

    private func prepare() -> Bool {
        guard dockFrame.width > 0, containerFrame.height > 0 else { return false }
        sourceFrame = dockFrame
        token = UUID()
        isVisible = true
        return true
    }

    func updateOpening(translation: CGFloat) {
        guard !isExpanded else { return }
        if !isTrackingOpening {
            guard !isVisible, translation < 0, prepare() else { return }
            isTrackingOpening = true
        }
        // Source top minus finger translation: no lagging animation while held.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            progress = min(1, max(0, -translation / travel))
        }
    }

    func finishOpening(velocity: CGFloat, reduceMotion: Bool) {
        guard isTrackingOpening else { return }
        isTrackingOpening = false
        let open = velocity < -650 || (velocity <= 650 && progress > 0.35)
        settle(open: open, reduceMotion: reduceMotion)
    }

    func cancelOpening(reduceMotion: Bool) {
        guard isTrackingOpening else { return }
        isTrackingOpening = false
        settle(open: false, reduceMotion: reduceMotion)
    }

    func open(reduceMotion: Bool) {
        guard !isVisible, prepare() else { return }
        let openingToken = token
        Task { @MainActor in
            // Mount the collapsed surface before animating a tap-open.
            await Task.yield()
            guard token == openingToken, isVisible else { return }
            settle(open: true, reduceMotion: reduceMotion)
        }
    }

    func close(reduceMotion: Bool) {
        guard isVisible else { return }
        settle(open: false, reduceMotion: reduceMotion)
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
            progress = min(1, max(0, 1 - translation / travel))
        }
    }

    func finishClosing(velocity: CGFloat, reduceMotion: Bool) {
        guard isTrackingClosing else { return }
        isTrackingClosing = false
        let close = velocity > 650 || (velocity >= -650 && progress < 0.65)
        settle(open: !close, reduceMotion: reduceMotion)
    }

    func cancelClosing(reduceMotion: Bool) {
        guard isTrackingClosing else { return }
        isTrackingClosing = false
        settle(open: true, reduceMotion: reduceMotion)
    }

    private func settle(open: Bool, reduceMotion: Bool) {
        let currentToken = UUID()
        token = currentToken
        let animation: Animation = reduceMotion
            ? .linear(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.94)
        withAnimation(animation, completionCriteria: .removed) {
            progress = open ? 1 : 0
        } completion: {
            guard self.token == currentToken else { return }
            self.isExpanded = open
            self.isVisible = open
        }
    }

    func cancelInteraction() {
        guard isTrackingOpening || isTrackingClosing else { return }
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
    @State private var renderedArtwork = PlayerArtworkImages.empty

    private var rectangle: CGRect {
        let source = presentation.sourceFrame.offsetBy(
            dx: -bounds.minX, dy: -bounds.minY
        )
        let p = presentation.progress
        return CGRect(
            x: source.minX * (1 - p),
            y: source.minY * (1 - p),
            width: source.width + (bounds.width - source.width) * p,
            height: source.height + (bounds.height - source.height) * p
        )
    }

    var body: some View {
        let rect = rectangle
        let p = presentation.progress
        let compactOpacity = min(1, max(0, (1 - p) / 0.30))
        let backgroundProgress = min(1, max(0, p / 0.15))
        let shape = RoundedRectangle(
            cornerRadius: 26 * (1 - p), style: .continuous
        )

        ZStack(alignment: .topLeading) {
            // Same backdrop, same full-screen dimensions at EVERY progress value.
            // Its top pixels are revealed first; no temporary black surface.
            NowPlayingBackdrop(image: renderedArtwork.background)
                .frame(width: bounds.width, height: bounds.height)
                .opacity(backgroundProgress)
                .allowsHitTesting(false)

            NowPlayingView(
                onClose: { presentation.close(reduceMotion: reduceMotion) },
                onCloseDrag: { presentation.updateClosing(translation: $0) },
                onCloseDragEnd: {
                    presentation.finishClosing(
                        velocity: $0, reduceMotion: reduceMotion
                    )
                },
                onCloseDragCancel: {
                    presentation.cancelClosing(reduceMotion: reduceMotion)
                },
                renderedArtwork: renderedArtwork,
                drawsBackground: false
            )
            .padding(.top, safeInsets.top)
            .padding(.bottom, safeInsets.bottom)
            .frame(width: bounds.width, height: bounds.height)
            .opacity(min(1, max(0, (p - 0.08) / 0.27)))
            .accessibilityHidden(!presentation.isExpanded)

            // Includes artwork, title, artist, AirPlay and playback controls.
            // Appears progressively during closing, not only at the endpoint.
            MiniPlayerTransitionRow(backgroundProgress: backgroundProgress)
                .frame(width: max(52, presentation.sourceFrame.width), height: 52)
                .opacity(compactOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(
            width: max(1, rect.width), height: max(1, rect.height),
            alignment: .topLeading
        )
        .contentShape(shape)
        .clipShape(shape)
        .glassEffect(.regular.interactive(), in: shape)
        .offset(x: rect.minX, y: rect.minY)
        .accessibilityAction(.escape) {
            presentation.close(reduceMotion: reduceMotion)
        }
        .task(id: audioPlayer.currentSong?.coverData ?? audioPlayer.currentSong?.imageData) {
            let data = audioPlayer.currentSong?.coverData ?? audioPlayer.currentSong?.imageData
            let images = await PlayerArtworkImages.prepare(data)
            guard !Task.isCancelled else { return }
            renderedArtwork = images
        }
    }
}
