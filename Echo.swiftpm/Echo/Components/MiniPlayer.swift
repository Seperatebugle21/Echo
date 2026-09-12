import SwiftUI
import UIKit

struct MiniPlayer: View {
    let onMinimize: () -> Void

    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Environment(MiniPlayerPresentation.self) private var presentation
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("showCovers") private var showCovers = true

    @GestureState private var dragActive = false

    @State private var dragAxis: DragAxis?
    @State private var offset: CGFloat = 0
    @State private var pageWidth: CGFloat = 1
    @State private var origin: Song?
    @State private var previous: Song?
    @State private var next: Song?
    @State private var settling = false
    @State private var blockedUntilRelease = false
    @State private var animationToken = UUID()

    private enum DragAxis {
        case horizontal
        case vertical
    }

    private var snapAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .spring(response: 0.32, dampingFraction: 0.92)
    }

    var body: some View {
        if let current = audioPlayer.currentSong {
            HStack(spacing: 4) {
                GeometryReader { geometry in
                    let width = max(1, geometry.size.width)

                    ZStack(alignment: .leading) {
                        if let previous {
                            songPage(previous, scrolling: false)
                                .frame(width: width)
                                .offset(x: -width + offset)
                                .accessibilityHidden(true)
                        }

                        songPage(
                            origin ?? current,
                            scrolling: !dragActive && !settling
                        )
                        .frame(width: width)
                        .offset(x: offset)

                        if let next {
                            songPage(next, scrolling: false)
                                .frame(width: width)
                                .offset(x: width + offset)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(width: width, height: 44)
                    .clipped()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        max(1, proxy.size.width)
                    } action: { width in
                        if abs(pageWidth - width) > 1 {
                            reset()
                            pageWidth = width
                        }
                    }
                }
                .frame(height: 44)
                .contentShape(Rectangle())
                .gesture(
                    pagingGesture.exclusively(
                        before: TapGesture().onEnded {
                            openPlayer()
                        }
                    )
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    openPlayer()
                }
                .accessibilityLabel(
                    "\(current.title), \(current.artist)"
                )
                .accessibilityHint("Open Now Playing")
                .accessibilityAction(named: Text("Next song")) {
                    audioPlayer.next()
                }
                .accessibilityAction(named: Text("Previous song")) {
                    if let song = audioPlayer.miniPlayerPreviousSong {
                        audioPlayer.playMiniPlayerPrevious(song)
                    }
                }
                .accessibilityAction(named: Text("Minimize player")) {
                    onMinimize()
                }

                AirPlayButton()
                    .frame(width: 30, height: 44)

                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(
                        systemName: audioPlayer.isPlaying
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .font(.system(size: 19, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    audioPlayer.isPlaying ? "Pause" : "Play"
                )
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .frame(height: 52)
            .contentShape(Rectangle())
            .onChange(of: current.id) {
                presentation.cancelOpening(
                    reduceMotion: reduceMotion
                )

                reset()
                blockedUntilRelease = dragActive
            }
            .task(id: dragActive) {
                guard !dragActive else { return }

                await Task.yield()

                if !settling && dragAxis != nil {
                    presentation.cancelOpening(
                        reduceMotion: reduceMotion
                    )
                    reset()
                }

                blockedUntilRelease = false
            }
            .onDisappear {
                presentation.cancelOpening(
                    reduceMotion: reduceMotion
                )
                reset()
            }
        }
    }

    private var pagingGesture: some Gesture {
        DragGesture(
            minimumDistance: 5,
            coordinateSpace: .global
        )
        .updating($dragActive) { _, active, _ in
            active = true
        }
        .onChanged { value in
            guard !settling && !blockedUntilRelease else {
                return
            }

            if dragAxis == nil {
                dragAxis =
                    abs(value.translation.width)
                    > abs(value.translation.height)
                    ? .horizontal
                    : .vertical

                origin = audioPlayer.currentSong
                previous = audioPlayer.miniPlayerPreviousSong
                next = audioPlayer.miniPlayerNextSong
            }

            if dragAxis == .vertical {
                presentation.updateOpening(
                    translation: value.translation.height
                )
                return
            }

            guard dragAxis == .horizontal else { return }

            let x = value.translation.width
            let hasPage = x < 0
                ? next != nil
                : previous != nil

            // Direct gekoppeld aan de vinger.
            // Aan het einde van de wachtrij ontstaat weerstand.
            offset = hasPage
                ? min(pageWidth, max(-pageWidth, x))
                : 24 * x / (abs(x) + 80)
        }
        .onEnded { value in
            guard !settling && !blockedUntilRelease else {
                blockedUntilRelease = false
                return
            }

            let axis = dragAxis
            dragAxis = nil

            if axis == .vertical {
                reset()

                if presentation.isTrackingOpening {
                    presentation.finishOpening(
                        velocity: value.velocity.height,
                        reduceMotion: reduceMotion
                    )
                } else if value.translation.height > 40 {
                    onMinimize()
                }

                return
            }

            guard axis == .horizontal else {
                reset()
                return
            }

            let distance = value.translation.width
            let velocity = value.velocity.width
            let direction: Int

            if abs(velocity) > 500 {
                direction = velocity < 0 ? 1 : -1
            } else if abs(distance) > pageWidth * 0.42 {
                direction = distance < 0 ? 1 : -1
            } else {
                direction = 0
            }

            let target = direction == 1 ? next : previous

            guard direction != 0, let target else {
                snapBack()
                return
            }

            finishSwipe(
                direction: direction,
                target: target
            )
        }
    }

    private func openPlayer() {
        guard
            !settling,
            !dragActive,
            !presentation.isVisible
        else {
            return
        }

        presentation.open(reduceMotion: reduceMotion)
    }

    private func snapBack() {
        settling = true

        let token = UUID()
        animationToken = token

        withAnimation(
            snapAnimation,
            completionCriteria: .removed
        ) {
            offset = 0
        } completion: {
            guard animationToken == token else { return }
            reset()
        }
    }

    private func finishSwipe(
        direction: Int,
        target: Song
    ) {
        guard let origin else {
            reset()
            return
        }

        settling = true

        let token = UUID()
        animationToken = token

        withAnimation(
            snapAnimation,
            completionCriteria: .removed
        ) {
            offset = direction == 1
                ? -pageWidth
                : pageWidth
        } completion: {
            guard
                animationToken == token,
                audioPlayer.currentSong?.id == origin.id
            else {
                return
            }

            let liveTarget = direction == 1
                ? audioPlayer.miniPlayerNextSong
                : audioPlayer.miniPlayerPreviousSong

            guard liveTarget?.id == target.id else {
                snapBack()
                return
            }

            if direction == 1 {
                audioPlayer.next()
            } else {
                audioPlayer.playMiniPlayerPrevious(target)
            }

            reset()
        }
    }

    private func reset() {
        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            animationToken = UUID()
            offset = 0
            origin = nil
            previous = nil
            next = nil
            dragAxis = nil
            settling = false
        }
    }

    private func songPage(
        _ song: Song,
        scrolling: Bool
    ) -> some View {
        HStack(spacing: 8) {
            MiniPlayerArtwork(
                data: showCovers ? song.coverData : nil
            )

            VStack(alignment: .leading, spacing: 1) {
                if scrolling {
                    ScrollingText(text: song.title)
                        .font(
                            .system(size: 14, weight: .medium)
                        )
                        .frame(height: 17)
                } else {
                    Text(song.title)
                        .font(
                            .system(size: 14, weight: .medium)
                        )
                        .lineLimit(1)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .frame(height: 17)
                }

                Text(song.artist)
                    .font(
                        .system(size: 11, weight: .medium)
                    )
                    .foregroundStyle(
                        colorScheme == .dark
                            ? Color(white: 0.88)
                            : Color(white: 0.28)
                    )
                    .lineLimit(1)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .padding(.trailing, 8)
        .frame(height: 44)
    }
}

// Afbeeldingen alleen opnieuw decoderen wanneer de data verandert.
struct MiniPlayerArtwork: View {
    let data: Data?

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 15))
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .background(.thinMaterial)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(.rect(cornerRadius: 6))
        .onChange(of: data, initial: true) {
            image = data.flatMap {
                UIImage(data: $0)
            }
        }
    }
}

// Gebruikt de bestaande AudioPlayerManager.
extension AudioPlayerManager {
    var miniPlayerNextSong: Song? {
        if queue.indices.contains(currentIndex + 1) {
            return queue[currentIndex + 1]
        }

        // next() verandert repeat-one bij handmatig overslaan
        // naar repeat-all.
        if repeatMode != .off, let first = queue.first {
            return first
        }

        return autoNextQueue.first
    }

    var miniPlayerPreviousSong: Song? {
        // Vooraf geladen nummers worden door de huidige manager
        // niet altijd aan history toegevoegd.
        if let index = queue.firstIndex(
            where: { $0.id == currentSong?.id }
        ), index > 0 {
            return queue[index - 1]
        }

        return history.last(
            where: { $0.id != currentSong?.id }
        )
    }

    func playMiniPlayerPrevious(_ song: Song) {
        guard
            let url = getURL(for: song),
            FileManager.default.fileExists(atPath: url.path)
        else {
            return
        }

        let savedIndex = currentIndex
        var previousHistory = history

        if let index = previousHistory.lastIndex(
            where: { $0.id == song.id }
        ) {
            previousHistory.removeSubrange(index...)
        }

        play(song: song, url: url)

        guard currentSong?.id == song.id else {
            currentIndex = savedIndex
            return
        }

        history = previousHistory
        lastPlaybackDirection = .previous

        if repeatMode == .one {
            repeatMode = .all
        }
    }
}