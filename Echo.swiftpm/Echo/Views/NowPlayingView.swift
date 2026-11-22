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
    /// Lyrics or queue in place of the large cover; kept while the player is closed.
    @State private var panel: NowPlayingPanel?
    /// Mounted shortly after the cover starts gliding, so building the lyrics or
    /// queue never lands on the same frames as the morph.
    @State private var shownPanel: NowPlayingPanel?
    @State private var panelToken = 0
    @State private var panelFrame: CGRect = .zero
    // One cover and one title block glide between these slots (in the content's own space).
    @State private var bigCoverSlot: CGRect = .zero
    @State private var smallCoverSlot: CGRect = .zero
    @State private var bigTitleSlot: CGRect = .zero
    @State private var smallTitleSlot: CGRect = .zero
    @State private var contentWidth: CGFloat = 0
    // The same slots in the expanding surface's space, for the flying cover.
    @State private var bigCoverSurface: CGRect = .zero
    @State private var smallCoverSurface: CGRect = .zero
    private static let contentSpace = "EchoNowPlayingContent"

    @Environment(AudioPlayerManager.self)
    private var audioPlayer

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State private var showPlaylistPicker = false
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

                if let panel {
                    // MARK: - Lyrics / queue (the cover shrinks into the header)

                    if let song = audioPlayer.currentSong {
                        compactHeader(song)
                    }

                    ZStack {
                        if let shownPanel {
                            panelContent(shownPanel)
                                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.asymmetric(
                                    insertion: AnyTransition.offset(y: 70)
                                        .combined(with: AnyTransition.scale(scale: 0.94, anchor: .top))
                                        .combined(with: AnyTransition.opacity),
                                    removal: AnyTransition.offset(y: 30).combined(with: AnyTransition.opacity)))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { panelFrame = $0 }
                    .transition(AnyTransition.opacity)
                } else {
                    Spacer(minLength: 0)

                    bigCoverPlaceholder

                    Spacer(minLength: 0)

                    // MARK: - Song Info

                    if let song = audioPlayer.currentSong {
                        songInfo(song)
                            .transition(AnyTransition.opacity)
                    }
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
            .coordinateSpace(.named(Self.contentSpace))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            // The cover and title live above the layout and glide between their slots.
            .overlay(alignment: .topLeading) { movingLayer }
            .onChange(of: panel) { if panel == nil { panelFrame = .zero } }
            .onChange(of: reportedCoverFrame, initial: true) { _, frame in
                if frame.width > 0 { onArtworkFrame?(frame) }
            }
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
    }

    // MARK: - Panels

    private func toggle(_ target: NowPlayingPanel) {
        panelToken += 1
        let token = panelToken
        let morph: Animation = reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.88)
        if panel == target {
            // Closing: let the content go first (cheap), then the cover grows back.
            withAnimation(.easeOut(duration: 0.14)) { shownPanel = nil }
            withAnimation(morph) { panel = nil }
        } else if panel != nil {
            // Switching between lyrics and queue: no cover movement, just a crossfade.
            withAnimation(.easeInOut(duration: 0.25)) {
                panel = target
                shownPanel = target
            }
        } else {
            withAnimation(morph) { panel = target }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 200))
                guard panelToken == token, panel == target else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.74)) { shownPanel = target }
            }
        }
    }

    @ViewBuilder
    private func panelContent(_ panel: NowPlayingPanel) -> some View {
        switch panel {
        case .lyrics: LyricsScroller(embedded: true).id(NowPlayingPanel.lyrics)
        case .queue: NowPlayingQueuePanel().id(NowPlayingPanel.queue)
        }
    }

    /// Apple Music style: the cover lands top-left, next to the song's title.
    /// Only empty slots here; the real cover and title glide into them.
    private func compactHeader(_ song: Song) -> some View {
        HStack(spacing: 14) {
            Color.clear
                .frame(width: 64, height: 64)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.contentSpace)) } action: {
                    smallCoverSlot = $0
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.coordinateSpaceName)) } action: {
                    smallCoverSurface = $0
                }

            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.contentSpace)) } action: {
                    smallTitleSlot = $0
                }

            NowPlayingOptionsButton(song: song,
                addToPlaylist: { showPlaylistPicker = true },
                showLyrics: { if panel != .lyrics { toggle(.lyrics) } })
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Moving cover and title

    private var reportedCoverFrame: CGRect {
        panel == nil ? bigCoverSurface : (smallCoverSurface.width > 0 ? smallCoverSurface : bigCoverSurface)
    }

    /// Before the header has been laid out once, its slots follow from its fixed layout.
    private var smallCoverTarget: CGRect {
        smallCoverSlot.width > 0 ? smallCoverSlot : CGRect(x: 24, y: 50, width: 64, height: 64)
    }

    private var smallTitleTarget: CGRect {
        smallTitleSlot.width > 0 ? smallTitleSlot
            : CGRect(x: 102, y: 50, width: max(40, contentWidth - 198), height: 64)
    }

    /// Each layer is positioned from the top-left corner of the content by its own slot.
    /// The explicit top-leading stack matters: an overlay's implicit stack centers its
    /// children on each other, which pushed the title down and the small cover sideways.
    private var movingLayer: some View {
        let big = panel == nil
        let cover = big ? bigCoverSlot : smallCoverTarget
        return ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            if cover.width > 0 {
                coverLayer(frame: cover, big: big)
            }
            if let song = audioPlayer.currentSong {
                let slot = big ? bigTitleSlot : smallTitleTarget
                if slot.width > 0 {
                    titleLayer(song, slot: slot, big: big)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func titleLayer(_ song: Song, slot: CGRect, big: Bool) -> some View {
        let scale: CGFloat = big ? 1 : 0.76
        return VStack(alignment: .leading, spacing: 4) {
            ScrollingText(text: song.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(height: 30)
            NowPlayingArtistButton(song: song)
        }
        .id(song.id)
        .transition(songInfoTransition)
        .frame(width: max(1, slot.width / scale), height: 58, alignment: .leading)
        .scaleEffect(scale, anchor: .topLeading)
        .offset(x: slot.minX, y: slot.midY - 29 * scale)
        .animation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion), value: song.id)
    }

    // MARK: - Song info

    private func songInfo(_ song: Song) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.contentSpace)) } action: { frame in
                    if bigTitleSlot.width > 0 {
                        withAnimation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion)) { bigTitleSlot = frame }
                    } else {
                        bigTitleSlot = frame
                    }
                }

            NowPlayingOptionsButton(song: song,
                addToPlaylist: { showPlaylistPicker = true },
                showLyrics: { toggle(.lyrics) })
        }
        .padding(.horizontal, 28)
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
                actionButton(panel == .lyrics ? "quote.bubble.fill" : "quote.bubble", zoomID: "lyrics",
                             label: "lyrics_action", active: panel == .lyrics) {
                    toggle(.lyrics)
                }
            }

            if let id = audioPlayer.currentSong?.podcastEpisodeID,
               let episode = PodcastStore.shared.state.episodes[id] {
                actionButton("text.bubble", zoomID: "transcript", label: "podcasts_transcript") {
                    transcriptEpisode = episode
                }
            }

            actionButton("list.bullet", zoomID: "queue", label: "queue_action", active: panel == .queue) {
                toggle(.queue)
            }
        }
        .padding(.horizontal, 24)
    }

    private func actionButton(_ symbol: String, zoomID: String, label: String, active: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? Color.black : .white.opacity(0.9))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(.white.opacity(active ? 0.92 : 0))
                        .scaleEffect(active ? 0.86 : 0.4)
                }
                .contentShape(.circle)
                .animation(EchoMotion.motion(EchoMotion.bouncy, reduceMotion: reduceMotion), value: active)
        }
        .buttonStyle(EchoPlayerControlStyle())
        .matchedTransitionSource(id: zoomID, in: sheetZoom)
        .accessibilityLabel(LocalizedStringKey(label))
        .accessibilityAddTraits(active ? .isSelected : [])
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
                    // Lyrics and the queue scroll; only the header and controls pull the player down.
                    let startedOnPanel = panel != nil && panelFrame.contains(value.startLocation)
                    dragMayClose = !startedOnSlider && !startedOnPanel
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

    /// Reserves the large cover's square; the cover itself is drawn by `coverLayer`.
    private var bigCoverPlaceholder: some View {
        Color.clear
            .frame(maxWidth: 360, maxHeight: 360)
            .aspectRatio(1, contentMode: .fit)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.contentSpace)) } action: { frame in
                if bigCoverSlot.width > 0 {
                    withAnimation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion)) { bigCoverSlot = frame }
                } else {
                    bigCoverSlot = frame
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.coordinateSpaceName)) } action: {
                bigCoverSurface = $0
            }
            .padding(.horizontal, 28)
            .layoutPriority(1)
            .accessibilityHidden(true)
    }

    /// The one cover in Now Playing. It glides and resizes between the large slot and the
    /// lyrics/queue header, breathes with play/pause when large, and changes with the song.
    private func coverLayer(frame: CGRect, big: Bool) -> some View {
        let playing = artworkScale == 1
        let radius: CGFloat = big ? Self.artworkCornerRadius : 10
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
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
                        .font(.system(size: big ? 90 : 24))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .transition(.opacity)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(shape)
        .animation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion),
                   value: images.cover.map { ObjectIdentifier($0) })
        .opacity(artworkHidden ? 0 : 1)
        // Light from the artwork itself falls behind it. No live blur: the glow is the
        // already blurred thumbnail with a soft gradient edge, and the shadow is cast by
        // a plain shape, so moving the cover never re-renders an offscreen blur.
        .background {
            ZStack {
                if let glow = images.background {
                    Image(uiImage: glow)
                        .resizable()
                        .scaledToFill()
                        .saturation(1.4)
                        .mask { EllipticalGradient(colors: [.black, .black.opacity(0.7), .clear], center: .center) }
                        .scaleEffect(playing ? 1.25 : 1.05)
                        .offset(y: playing ? 24 : 12)
                        .opacity(artworkHidden || !big ? 0 : playing ? 0.9 : 0.55)
                        .animation(.easeOut(duration: 0.45), value: artworkHidden)
                }
                shape
                    .fill(.black)
                    .shadow(color: .black.opacity(big ? (playing ? 0.4 : 0.25) : 0.3),
                            radius: big ? (playing ? 28 : 16) : 10, y: big ? (playing ? 18 : 8) : 5)
                    .opacity(artworkHidden ? 0 : 1)
            }
            .allowsHitTesting(false)
        }
        .scaleEffect(big ? artworkScale : 1)
        .animation(EchoMotion.motion(EchoMotion.bouncy, reduceMotion: reduceMotion), value: artworkScale)
        .contentShape(shape)
        // Tapping the small cover brings the large one back.
        .onTapGesture { if let panel { toggle(panel) } }
        .allowsHitTesting(!big)
        .offset(x: frame.minX, y: frame.minY)
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
