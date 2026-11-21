import SwiftUI
import UIKit
import ImageIO
import CoreImage

struct NowPlayingView: View {
    // Defaults preserve existing callers that present this view in a sheet.
    var onClose: (() -> Void)? = nil
    var onCloseDrag: ((CGFloat) -> Void)? = nil
    var onCloseDragEnd: ((CGFloat) -> Void)? = nil
    var onCloseDragCancel: (() -> Void)? = nil
    var renderedArtwork: PlayerArtworkImages? = nil
    var drawsBackground = true
    var tracksSliderGeometry = true
    /// While the expanding surface flies its own copy of the cover, the real one waits hidden.
    var artworkHidden = false
    /// Reports the cover's frame in `NowPlayingView.coordinateSpaceName`.
    var onArtworkFrame: ((CGRect) -> Void)? = nil

    /// Declared by the expanding surface so the flying cover can land exactly on the real one.
    static let coordinateSpaceName = "EchoNowPlayingSpace"
    static let artworkCornerRadius: CGFloat = 22

    /// Apple-style breathing: the cover sits back slightly while paused.
    static func artworkScale(isPlaying: Bool, isPreparing: Bool) -> CGFloat {
        isPlaying || isPreparing ? 1 : 0.86
    }

    @State private var sliderFrame: CGRect = .zero
    @State private var isScrubbing = false
    @State private var dragMayClose: Bool?
    @State private var localArtwork = PlayerArtworkImages.empty
    @GestureState private var closeDragActive = false
    @State private var closingDragInProgress = false
    @State private var previousBounce = 0
    @State private var nextBounce = 0
    @Namespace private var sheetZoom

    @Environment(AudioPlayerManager.self)
    private var audioPlayer

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State private var showQueue = false
    @State private var showPlaylistPicker = false
    @State private var showLyrics = false
    @State private var transcriptEpisode: PodcastEpisode?

    private var images: PlayerArtworkImages { renderedArtwork ?? localArtwork }

    var body: some View {

        ZStack {

            // MARK: - Background

            if drawsBackground {
                NowPlayingBackdrop(image: images.background)
                    .ignoresSafeArea()
            }


            // MARK: - Content

            VStack(spacing: 22) {

                closeHandle

                Spacer(minLength: 0)

                artwork

                Spacer(minLength: 0)

                // MARK: - Song Info

                if let song = audioPlayer.currentSong {
                    songInfo(song)
                }

                if let errorKey = audioPlayer.playbackErrorKey {
                    HStack(spacing: 12) {
                        Text(LocalizedStringKey(errorKey)).font(.footnote).foregroundStyle(.white)
                        Button("audio_retry") { audioPlayer.retryPlayback() }.buttonStyle(.bordered).tint(.white)
                    }
                    .padding(.horizontal, 28)
                    .accessibilityElement(children: .contain)
                    .transition(.blurReplace)
                }

                // MARK: - Progress

                NowPlayingProgress(sliderFrame: $sliderFrame, isScrubbing: $isScrubbing,
                                   tracksGeometry: tracksSliderGeometry && !closingDragInProgress)

                // MARK: - Playback Controls

                if audioPlayer.isPodcast {
                    PodcastPlaybackControls()
                } else {
                    playbackControls
                }

                // MARK: - Bottom Actions

                bottomActions

                Spacer(minLength: 8)
            }
            .animation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion),
                       value: audioPlayer.playbackErrorKey)
            // A recognized vertical drag cannot also release a playback button.
            .disabled(closingDragInProgress)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(closeDrag)
        .task(id: closeDragActive) {
            guard !closeDragActive else { return }
            await Task.yield()
            if closingDragInProgress {
                closingDragInProgress = false
                onCloseDragCancel?()
            }
            dragMayClose = nil
        }

        .task(id: audioPlayer.currentSong?.coverData ?? audioPlayer.currentSong?.imageData) {
            guard renderedArtwork == nil else { return }
            let data = audioPlayer.currentSong?.coverData ?? audioPlayer.currentSong?.imageData
            let images = await PlayerArtworkImages.prepare(data)
            guard !Task.isCancelled else { return }
            localArtwork = images
        }

        // MARK: - Sheets (they grow out of the button that opened them)

        .sheet(isPresented: $showQueue) {
            QueueView()
                .navigationTransition(.zoom(sourceID: "queue", in: sheetZoom))
        }

        .sheet(isPresented: $showPlaylistPicker) {
            if let song = audioPlayer.currentSong {
                PlaylistPickerView(song: song)
                    .navigationTransition(.zoom(sourceID: "playlist", in: sheetZoom))
            }
        }

        .sheet(item: $transcriptEpisode) { episode in
            PodcastTranscriptView(episode: episode)
                .navigationTransition(.zoom(sourceID: "transcript", in: sheetZoom))
        }

        .sheet(isPresented: $showLyrics) {
            NavigationStack {
                LyricsView()
            }
            .navigationTransition(.zoom(sourceID: "lyrics", in: sheetZoom))
        }
    }

    // MARK: - Song info

    private func songInfo(_ song: Song) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                ScrollingText(text: song.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(height: 30)

                NowPlayingArtistButton(song: song)
            }
            .id(song.id)
            .transition(songInfoTransition)

            Spacer(minLength: 0)

            NowPlayingOptionsButton(song: song,
                addToPlaylist: { showPlaylistPicker = true },
                showLyrics: { showLyrics = true })
        }
        .padding(.horizontal, 28)
        .animation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion), value: song.id)
    }

    /// New songs slide in from the side they come from.
    private var songInfoTransition: AnyTransition {
        guard !reduceMotion else { return AnyTransition.opacity }
        let distance: CGFloat
        switch audioPlayer.lastPlaybackDirection {
        case .next: distance = 44
        case .previous: distance = -44
        case .fade: distance = 0
        }
        return AnyTransition.asymmetric(
            insertion: AnyTransition.offset(x: distance).combined(with: AnyTransition.opacity),
            removal: AnyTransition.offset(x: -distance).combined(with: AnyTransition.opacity)
        )
    }

    // MARK: - Controls

    private var playbackControls: some View {
        HStack(spacing: 0) {

            toggleButton(symbol: "shuffle", active: audioPlayer.shuffleEnabled,
                         label: "shuffle_action") {
                audioPlayer.toggleShuffle()
            }

            Spacer(minLength: 0)

            Button {
                previousBounce += 1
                audioPlayer.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce.down, options: .speed(1.4), value: previousBounce)
                    .frame(width: 64, height: 64)
                    .contentShape(.circle)
            }
            .buttonStyle(EchoPlayerControlStyle())
            .accessibilityLabel(LocalizedStringKey("previous_track_action"))

            Spacer(minLength: 0)

            Button {
                audioPlayer.togglePlayPause()
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                    .frame(width: 84, height: 84)
                    .contentShape(.circle)
            }
            .buttonStyle(EchoPlayerControlStyle(pressedScale: 0.8))
            .accessibilityLabel(
                audioPlayer.isPlaying
                ? LocalizedStringKey("pause_action")
                : LocalizedStringKey("play_action")
            )

            Spacer(minLength: 0)

            Button {
                nextBounce += 1
                audioPlayer.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce.down, options: .speed(1.4), value: nextBounce)
                    .frame(width: 64, height: 64)
                    .contentShape(.circle)
            }
            .buttonStyle(EchoPlayerControlStyle())
            .accessibilityLabel(LocalizedStringKey("next_track_action"))

            Spacer(minLength: 0)

            toggleButton(symbol: audioPlayer.repeatMode == .one ? "repeat.1" : "repeat",
                         active: audioPlayer.repeatMode != .off, label: "repeat_action") {
                audioPlayer.toggleRepeat()
            }
        }
        .padding(.horizontal, 20)
    }

    /// Shuffle and repeat light up with a soft pill instead of only changing color.
    private func toggleButton(symbol: String, active: Bool, label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : .white.opacity(0.8))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(.white.opacity(active ? 0.16 : 0))
                        .scaleEffect(active ? 1 : 0.4)
                }
                .contentShape(.circle)
                .animation(EchoMotion.motion(EchoMotion.bouncy, reduceMotion: reduceMotion), value: active)
        }
        .buttonStyle(EchoPlayerControlStyle(halo: false))
        .accessibilityLabel(LocalizedStringKey(label))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var bottomActions: some View {
        HStack(spacing: 6) {

            AirPlayButton(tintColor: .white, activeTintColor: .white)
                .frame(width: 30, height: 30)
                .frame(width: 44, height: 44)

            Spacer()

            if !audioPlayer.isPodcast {
                actionButton("music.note.list", zoomID: "playlist", label: "add_to_playlist_action") {
                    showPlaylistPicker = true
                }
                actionButton("quote.bubble", zoomID: "lyrics", label: "lyrics_action") {
                    showLyrics = true
                }
            }

            if let id = audioPlayer.currentSong?.podcastEpisodeID,
               let episode = PodcastStore.shared.state.episodes[id] {
                actionButton("text.bubble", zoomID: "transcript", label: "podcasts_transcript") {
                    transcriptEpisode = episode
                }
            }

            actionButton("list.bullet", zoomID: "queue", label: "queue_action") {
                showQueue = true
            }
        }
        .padding(.horizontal, 24)
    }

    private func actionButton(_ symbol: String, zoomID: String, label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(EchoPlayerControlStyle())
        .matchedTransitionSource(id: zoomID, in: sheetZoom)
        .accessibilityLabel(LocalizedStringKey(label))
    }

    private var closeHandle: some View {
        Button {
            guard !closingDragInProgress else { return }
            close()
        } label: {
            Capsule()
                .fill(.white.opacity(0.55))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close Now Playing")
    }

    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($closeDragActive) { _, active, _ in active = true }
            .onChanged { value in
                guard !isScrubbing else { return }
                if dragMayClose == nil {
                    // Preserve seeking, even if a slider drag is slightly diagonal.
                    let startedOnSlider = sliderFrame
                        .insetBy(dx: -12, dy: -12)
                        .contains(value.startLocation)
                    dragMayClose = !startedOnSlider
                        && value.translation.height > 0
                        && abs(value.translation.height) > abs(value.translation.width)
                }
                guard dragMayClose == true else { return }
                closingDragInProgress = true
                onCloseDrag?(value.translation.height)
            }
            .onEnded { value in
                let shouldFinish = closingDragInProgress
                closingDragInProgress = false
                dragMayClose = nil
                guard shouldFinish else { return }
                if let onCloseDragEnd {
                    onCloseDragEnd(value.velocity.height)
                } else if value.translation.height > 70 || value.velocity.height > 650 {
                    close()
                }
            }
    }

    private func close() {
        if let onClose { onClose() }
        else { dismiss() }
    }

    // MARK: - Artwork

    private var artworkScale: CGFloat {
        Self.artworkScale(isPlaying: audioPlayer.isPlaying, isPreparing: audioPlayer.isPreparingAudio)
    }

    private var artworkTransition: AnyTransition {
        guard !reduceMotion else { return AnyTransition.opacity }
        let distance: CGFloat
        switch audioPlayer.lastPlaybackDirection {
        case .next: distance = 70
        case .previous: distance = -70
        case .fade:
            return AnyTransition.scale(scale: 0.94).combined(with: AnyTransition.opacity)
        }
        let shrink = AnyTransition.scale(scale: 0.92).combined(with: AnyTransition.opacity)
        return AnyTransition.asymmetric(
            insertion: AnyTransition.offset(x: distance).combined(with: shrink),
            removal: AnyTransition.offset(x: -distance).combined(with: shrink))
    }

    private var artwork: some View {
        let playing = artworkScale == 1
        let shape = RoundedRectangle(cornerRadius: Self.artworkCornerRadius, style: .continuous)
        return Color.clear
            .frame(maxWidth: 360, maxHeight: 360)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    if let image = images.cover {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .id(ObjectIdentifier(image))
                            .transition(artworkTransition)
                    } else {
                        ZStack {
                            Rectangle().fill(.white.opacity(0.12))
                            Image(systemName: "music.note")
                                .font(.system(size: 90))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .transition(.opacity)
                    }
                }
                .clipShape(shape)
                .animation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion),
                           value: images.cover.map { ObjectIdentifier($0) })
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.coordinateSpaceName))
            } action: { frame in
                onArtworkFrame?(frame)
            }
            .opacity(artworkHidden ? 0 : 1)
            // Light from the artwork itself falls behind it.
            .background {
                if let glow = images.background {
                    Image(uiImage: glow)
                        .resizable()
                        .scaledToFill()
                        .clipShape(shape)
                        .blur(radius: 28)
                        .saturation(1.4)
                        .opacity(artworkHidden ? 0 : playing ? 0.85 : 0.5)
                        .scaleEffect(playing ? 1.02 : 0.9)
                        .offset(y: playing ? 26 : 14)
                        .animation(.easeOut(duration: 0.45), value: artworkHidden)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(artworkHidden ? 0 : playing ? 0.4 : 0.25),
                    radius: playing ? 30 : 16, y: playing ? 18 : 8)
            .scaleEffect(artworkScale)
            .animation(EchoMotion.motion(EchoMotion.bouncy, reduceMotion: reduceMotion), value: artworkScale)
            .padding(.horizontal, 28)
            .layoutPriority(1)
            .accessibilityHidden(true)
    }
}

// Shared images are prepared once per artwork change, outside the gesture path.
// UIImage instances are immutable here and are only rendered after preparation.
struct PlayerArtworkImages: @unchecked Sendable {
    let cover: UIImage?
    let background: UIImage?
    static let empty = PlayerArtworkImages(cover: nil, background: nil)

    /// Only the small blurred backdrop, for pages that tint themselves with the song's colors.
    static func prepareBackdrop(_ data: Data?) async -> UIImage? {
        guard let data else { return nil }
        return await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 180,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let small = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return PlayerArtworkImages.blurred(small).map { UIImage(cgImage: $0) } ?? UIImage(cgImage: small)
        }.value
    }

    static func blurred(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: 20)
            .cropped(to: input.extent)
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: input.extent)
    }

    static func prepare(_ data: Data?) async -> PlayerArtworkImages {
        guard let data else { return .empty }
        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return PlayerArtworkImages.empty
            }

            func thumbnail(_ maximumSize: Int) -> CGImage? {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumSize,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                return CGImageSourceCreateThumbnailAtIndex(
                    source, 0, options as CFDictionary
                )
            }

            guard let cover = thumbnail(900) else {
                return PlayerArtworkImages.empty
            }

            var background: UIImage?
            if let small = thumbnail(180), let output = PlayerArtworkImages.blurred(small) {
                background = UIImage(cgImage: output)
            }
            return PlayerArtworkImages(
                cover: UIImage(cgImage: cover),
                background: background ?? UIImage(cgImage: cover)
            )
        }.value
    }
}

// Used by both standalone Now Playing and the interactive transition.
// No live blur shader or repeated image decoding during a drag: the drifting
// layers only move an already blurred thumbnail.
struct NowPlayingBackdrop: View {
    let image: UIImage?
    var animated = true

    var body: some View {
        EchoLivingBackdrop(image: image, animated: animated)
    }
}

// Time updates only invalidate this small subtree, not the artwork and full player.
private struct NowPlayingProgress: View {
    @State private var scrub = PlaybackScrubState()
    @GestureState private var dragActive = false
    @State private var invalidatedDrag = false
    @State private var scrubPlaybackGeneration: UUID?

    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var sliderFrame: CGRect
    @Binding var isScrubbing: Bool
    let tracksGeometry: Bool
    private var displayPosition: Double { scrub.isActive ? scrub.position : audioPlayer.currentTime }
    var body: some View {
        VStack(spacing: 5) {

            GeometryReader { geometry in
                let width = max(1, geometry.size.width - 14)
                let fraction = min(1, max(0, displayPosition / max(1, audioPlayer.duration)))
                // The bar swells while you hold it, like the system media controls.
                Capsule()
                    .fill(.white.opacity(scrub.isActive ? 0.3 : 0.22))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(.white.opacity(scrub.isActive ? 1 : 0.88))
                            .frame(width: min(geometry.size.width, max(0, width * fraction + 7)))
                    }
                    .clipShape(.capsule)
                    .frame(height: 12)
                    .animation(EchoMotion.motion(EchoMotion.bouncy, reduceMotion: reduceMotion)) { bar in
                        bar.scaleEffect(y: scrub.isActive ? 1 : 0.42)
                    }
                    .frame(maxHeight: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .updating($dragActive) { _, active, _ in active = true }
                        .onChanged { value in
                            guard !invalidatedDrag else { return }
                            if !scrub.isActive {
                                scrub.begin(songID: audioPlayer.currentSong?.id,
                                    position: audioPlayer.currentTime, duration: audioPlayer.duration)
                                scrubPlaybackGeneration = audioPlayer.playbackGeneration
                            }
                            guard scrub.isActive else { return }
                            isScrubbing = true
                            scrub.update((value.location.x - 7) / width * scrub.duration)
                        }
                        .onEnded { value in
                            if !invalidatedDrag && scrubPlaybackGeneration == audioPlayer.playbackGeneration {
                                scrub.update((value.location.x - 7) / width * scrub.duration)
                                if let target = scrub.finish(songID: audioPlayer.currentSong?.id) {
                                    audioPlayer.seek(to: target)
                                }
                            }
                            scrub.cancel()
                            isScrubbing = false
                            invalidatedDrag = false
                        }
                )
                .accessibilityElement()
                .accessibilityLabel("now_playing_position")
                .accessibilityValue(Self.formatTime(displayPosition))
                .accessibilityAdjustableAction { direction in
                    guard audioPlayer.duration > 0 else { return }
                    let target: Double
                    switch direction {
                    case .increment: target = min(audioPlayer.duration, audioPlayer.currentTime + 10)
                    case .decrement: target = max(0, audioPlayer.currentTime - 10)
                    @unknown default: return
                    }
                    audioPlayer.seek(to: target)
                }
                .onGeometryChange(for: CGRect.self) { proxy in
                    tracksGeometry ? proxy.frame(in: .global) : .zero
                } action: { frame in
                    if frame != .zero && sliderFrame != frame { sliderFrame = frame }
                }
            }
            .frame(height: 44)
            .task(id: dragActive) {
                guard !dragActive else { return }
                // onEnded consumes the transaction first. Cancellation only discards it.
                await Task.yield()
                guard !Task.isCancelled, !dragActive else { return }
                scrub.cancel()
                isScrubbing = false
                invalidatedDrag = false
            }
            .onDisappear {
                scrub.cancel()
                isScrubbing = false
            }
            .onChange(of: audioPlayer.currentSong?.id) {
                invalidatedDrag = dragActive
                scrub.cancel()
                isScrubbing = false
            }
            .onChange(of: audioPlayer.playbackGeneration) {
                invalidatedDrag = dragActive
                scrub.cancel()
                isScrubbing = false
            }

                    HStack {

                        Text(
                            Self.formatTime(
                                displayPosition
                            )
                        )

                        Spacer()

                        Text(
                            Self.formatTime(
                                audioPlayer.duration
                            )
                        )
                    }
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(
                        .white.opacity(scrub.isActive ? 0.95 : 0.6)
                    )
                    .animation(EchoMotion.motion(EchoMotion.snappy, reduceMotion: reduceMotion)) { labels in
                        labels.offset(y: scrub.isActive ? 4 : 0)
                    }
                }
                .padding(.horizontal, 28)



    }
    private static func formatTime(_ time: Double) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        let seconds = Int(time)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
