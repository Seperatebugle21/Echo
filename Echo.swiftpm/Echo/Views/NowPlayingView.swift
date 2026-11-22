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
    /// The safe-area inset above this view, so a full-screen cover can reach the top edge.
    var topInset: CGFloat = 0

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
    // Haptics
    @State private var playHaptic = 0
    @State private var panelHaptic = 0
    @State private var swipeHaptic = 0
    // Swiping the cover to change songs
    @State private var coverSwipe: CGFloat = 0
    @State private var swipeIsHorizontal: Bool?
    @State private var swipeCommitting = false
    // What the cover and title show. They change together, in one slide, once the
    // new song's cover is ready (normally instantly: neighbors are prepared ahead).
    @State private var shownSong: Song?
    @State private var shown = PlayerArtworkImages.empty
    @State private var slideMode = CoverSlide.forward
    // The songs on either side, so a swipe shows the next cover right beside the finger.
    @State private var nextSong: Song?
    @State private var nextArt = PlayerArtworkImages.empty
    @State private var previousSong: Song?
    @State private var previousArt = PlayerArtworkImages.empty
    // Lyrics: the controls step aside after a few quiet seconds
    @State private var controlsHidden = false
    @State private var idleTask: Task<Void, Never>?
    @AppStorage(ThemeSettingsView.fullCoverKey) private var fullCover = false
    @State private var transcriptEpisode: PodcastEpisode?

    private enum CoverSlide { case forward, backward, fade }
    private static let coverGap: CGFloat = 26

    private var images: PlayerArtworkImages {
        shownSong != nil || audioPlayer.currentSong == nil ? shown : (renderedArtwork ?? localArtwork)
    }

    /// Changes when the song or its artwork changes.
    private var songArtworkKey: String {
        guard let song = audioPlayer.currentSong else { return "none" }
        return "\(song.id)-\(song.artworkRevision)"
    }

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

                if !immersiveLyrics {
                    // MARK: - Progress

                    NowPlayingProgress(sliderFrame: $sliderFrame, isScrubbing: $isScrubbing,
                                       tracksGeometry: tracksSliderGeometry && !closingDragInProgress)
                        .transition(controlsTransition)

                    // MARK: - Playback Controls

                    Group {
                        if audioPlayer.isPodcast {
                            PodcastPlaybackControls()
                        } else {
                            playbackControls
                        }
                    }
                    .transition(controlsTransition)

                    // MARK: - Bottom Actions

                    bottomActions
                        .transition(controlsTransition)
                }

                Spacer(minLength: 8)
            }
            .animation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion),
                       value: audioPlayer.playbackErrorKey)
            .coordinateSpace(.named(Self.contentSpace))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            // The cover and title live above the layout and glide between their slots.
            .overlay(alignment: .topLeading) { movingLayer }
            .onChange(of: panel) {
                if panel == nil { panelFrame = .zero }
                if panel == .lyrics {
                    scheduleControlsHide()
                } else {
                    idleTask?.cancel()
                    if controlsHidden { withAnimation(EchoMotion.fluid) { controlsHidden = false } }
                }
            }
            .onChange(of: reportedCoverFrame, initial: true) { _, frame in
                if frame.width > 0 { onArtworkFrame?(frame) }
            }
            // A recognized vertical drag cannot also release a playback button.
            .disabled(closingDragInProgress)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(closeDrag)
        .simultaneousGesture(TapGesture().onEnded { wakeControls() })
        // Limited (default): play/pause and swiping to another song. Full adds the rest.
        .sensoryFeedback(.impact(weight: .medium), trigger: playHaptic) { _, _ in EchoHaptics.allows(essential: true) }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: swipeHaptic) { _, _ in EchoHaptics.allows(essential: true) }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: nextBounce) { _, _ in EchoHaptics.allows(essential: false) }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: previousBounce) { _, _ in EchoHaptics.allows(essential: false) }
        .sensoryFeedback(.selection, trigger: panelHaptic) { _, _ in EchoHaptics.allows(essential: false) }
        .task(id: closeDragActive) {
            guard !closeDragActive else { return }
            await Task.yield()
            if closingDragInProgress {
                closingDragInProgress = false
                onCloseDragCancel?()
            }
            dragMayClose = nil
        }

        .task(id: songArtworkKey) { await showCurrentSong() }

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

    // MARK: - Immersive lyrics

    private var immersiveLyrics: Bool { controlsHidden && panel == .lyrics }

    private var controlsTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity
            : AnyTransition.offset(y: 36).combined(with: AnyTransition.opacity)
    }

    private func scheduleControlsHide() {
        idleTask?.cancel()
        guard panel == .lyrics else { return }
        idleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, panel == .lyrics, !isScrubbing, !closingDragInProgress else { return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) { controlsHidden = true }
        }
    }

    /// Any touch brings the controls back and restarts the quiet timer.
    private func wakeControls() {
        if controlsHidden {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { controlsHidden = false }
        }
        scheduleControlsHide()
    }

    // MARK: - Swiping the cover

    private var coverTravel: CGFloat { max(bigCoverSlot.width, 200) + Self.coverGap }

    private var coverSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard panel == nil, !closingDragInProgress, !swipeCommitting else { return }
                if swipeIsHorizontal == nil {
                    swipeIsHorizontal = abs(value.translation.width) > abs(value.translation.height)
                }
                guard swipeIsHorizontal == true else { return }
                let x = value.translation.width
                let hasNeighbor = x < 0 ? nextSong != nil : previousSong != nil
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    // Follows the finger; resists where the queue ends.
                    coverSwipe = hasNeighbor ? max(-coverTravel, min(coverTravel, x)) : 24 * x / (abs(x) + 80)
                }
            }
            .onEnded { value in
                let horizontal = swipeIsHorizontal == true
                swipeIsHorizontal = nil
                guard horizontal, panel == nil, !swipeCommitting else { return }
                let dx = value.translation.width
                let vx = value.velocity.width
                let direction = abs(vx) > 600 ? (vx < 0 ? 1 : -1) : abs(dx) > 100 ? (dx < 0 ? 1 : -1) : 0
                let target = direction == 1 ? nextSong : direction == -1 ? previousSong : nil
                guard let target else {
                    withAnimation(EchoMotion.release) { coverSwipe = 0 }
                    return
                }
                let art = direction == 1 ? nextArt : previousArt
                swipeCommitting = true
                withAnimation(.spring(response: 0.34, dampingFraction: 0.95), completionCriteria: .logicallyComplete) {
                    coverSwipe = direction == 1 ? -coverTravel : coverTravel
                } completion: {
                    swipeHaptic += 1
                    // The neighbor now sits in the middle: make it the shown cover in the
                    // same instant, so nothing animates a second time.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        shown = art
                        shownSong = target
                        coverSwipe = 0
                    }
                    if direction == 1 { audioPlayer.next() } else { audioPlayer.playMiniPlayerPrevious(target) }
                    swipeCommitting = false
                }
            }
    }

    /// Brings in the current song's cover and title together, sliding like a swipe.
    private func showCurrentSong() async {
        let song = audioPlayer.currentSong
        let prepared = await PlayerArtworkImages.cached(song: song)
        guard !Task.isCancelled else { return }
        if shownSong == nil || song == nil || shownSong?.id == song?.id || reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = !(shownSong?.id == song?.id && shown.cover !== prepared.cover)
            withTransaction(transaction) {
                shown = prepared
                shownSong = song
            }
        } else {
            // Let the player finish starting the new song before anything moves.
            await Task.yield()
            guard !Task.isCancelled else { return }
            switch audioPlayer.lastPlaybackDirection {
            case .next: slideMode = .forward
            case .previous: slideMode = .backward
            case .fade: slideMode = .fade
            }
            withAnimation(slideMode == .fade ? .easeInOut(duration: 0.35) : .spring(response: 0.48, dampingFraction: 0.92)) {
                shown = prepared
                shownSong = song
            }
        }
        // Prepare the covers on either side for swiping and the next skip.
        let upcoming = audioPlayer.miniPlayerNextSong
        let earlier = audioPlayer.miniPlayerPreviousSong
        let upcomingArt = await PlayerArtworkImages.cached(song: upcoming)
        let earlierArt = await PlayerArtworkImages.cached(song: earlier)
        guard !Task.isCancelled else { return }
        nextSong = upcoming
        nextArt = upcomingArt
        previousSong = earlier
        previousArt = earlierArt
    }

    private func coverTransition(width: CGFloat, inset: CGFloat, full: Bool) -> AnyTransition {
        guard !reduceMotion, !full, slideMode != .fade else { return AnyTransition.opacity }
        // Far enough that the outgoing cover leaves the screen completely.
        let distance = (width + max(inset, 0) + Self.coverGap) * (slideMode == .forward ? 1 : -1)
        return AnyTransition.asymmetric(insertion: AnyTransition.offset(x: distance),
                                        removal: AnyTransition.offset(x: -distance))
    }

    private var titleTransition: AnyTransition {
        guard !reduceMotion, slideMode != .fade else { return AnyTransition.opacity }
        let distance: CGFloat = slideMode == .forward ? 90 : -90
        return AnyTransition.asymmetric(
            insertion: AnyTransition.offset(x: distance).combined(with: AnyTransition.opacity),
            removal: AnyTransition.offset(x: -distance).combined(with: AnyTransition.opacity))
    }

    private func toggle(_ target: NowPlayingPanel) {
        panelHaptic += 1
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
        if panel == nil && fullCover && contentWidth > 0 {
            // Full-screen cover: it starts at the top of the surface.
            return CGRect(x: 0, y: 0, width: contentWidth, height: contentWidth)
        }
        return panel == nil ? bigCoverSurface : (smallCoverSurface.width > 0 ? smallCoverSurface : bigCoverSurface)
    }

    /// The full-screen cover's square, reaching up to the top edge of the screen.
    private var fullCoverFrame: CGRect {
        CGRect(x: 0, y: -topInset, width: contentWidth, height: contentWidth)
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
        let full = big && fullCover && contentWidth > 0
        let cover = full ? fullCoverFrame : big ? bigCoverSlot : smallCoverTarget
        return ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            // The title is drawn below the cover, so while gliding it passes underneath.
            if let song = shownSong ?? audioPlayer.currentSong {
                let slot = big ? bigTitleSlot : smallTitleTarget
                if slot.width > 0 {
                    titleLayer(song, slot: slot, big: big)
                }
            }
            if cover.width > 0 {
                coverLayer(frame: cover, big: big, full: full)
            }
            // The cover now covers the close handle, so draw the handle again on top
            // (the real one underneath still takes the taps).
            if full {
                Capsule()
                    .fill(.white.opacity(0.7))
                    .frame(width: 38, height: 5)
                    .frame(width: contentWidth, height: 28)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
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
        .transition(titleTransition)
        .frame(width: max(1, slot.width / scale), height: 58, alignment: .leading)
        .scaleEffect(scale, anchor: .topLeading)
        .offset(x: slot.minX, y: slot.midY - 29 * scale)
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
                playHaptic += 1
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
                if dragMayClose == nil { wakeControls() }
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
            // Swipe the cover sideways for the next or previous song.
            .contentShape(Rectangle())
            .gesture(coverSwipeGesture)
            .padding(.horizontal, 28)
            .layoutPriority(1)
            .accessibilityHidden(true)
    }

    /// The one cover in Now Playing. It glides and resizes between the large slot and the
    /// lyrics/queue header, breathes with play/pause when large, and changes with the song.
    private func coverLayer(frame: CGRect, big: Bool, full: Bool) -> some View {
        let playing = artworkScale == 1
        let radius: CGFloat = full ? 0 : big ? Self.artworkCornerRadius : 10
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let card = big && !full
        let cardShadow = card && !artworkHidden
        return ZStack {
            // Each cover is clipped on its own, so the outgoing and incoming covers can
            // travel side by side across the screen like a carousel.
            Group {
                if let image = images.cover {
                    coverCard(image, size: frame.size, shape: shape, shadow: cardShadow, playing: playing)
                        .id(ObjectIdentifier(image))
                } else {
                    coverPlaceholder(size: frame.size, shape: shape, big: big)
                        .id("placeholder")
                }
            }
            .transition(coverTransition(width: frame.width, inset: frame.minX, full: full))

            // While swiping, the next (or previous) cover waits right beside it.
            if big && !full && coverSwipe != 0 {
                let forward = coverSwipe < 0
                let neighbor = forward ? nextArt.cover : previousArt.cover
                Group {
                    if let neighbor {
                        coverCard(neighbor, size: frame.size, shape: shape, shadow: cardShadow, playing: playing)
                    } else {
                        coverPlaceholder(size: frame.size, shape: shape, big: big)
                    }
                }
                .offset(x: (forward ? 1 : -1) * (frame.width + Self.coverGap))
                .opacity((forward ? nextSong : previousSong) == nil ? 0 : 1)
            }
        }
        .frame(width: frame.width, height: frame.height)
        // Full screen: darker at the very top for the status bar, fading out at the bottom.
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: frame.height * 0.25)
                .opacity(full ? 1 : 0)
                .allowsHitTesting(false)
        }
        // Only the full-screen cover fades out at the bottom. Otherwise the mask reaches
        // well past the cover, so it never cuts the shadow into square corners.
        .mask {
            ZStack {
                // Wide enough sideways for covers sliding fully off screen.
                Rectangle().padding(.vertical, -140).padding(.horizontal, -1200).opacity(full ? 0 : 1)
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.55),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .frame(width: frame.width, height: frame.height)
                .opacity(full ? 1 : 0)
            }
        }
        .opacity(artworkHidden ? 0 : 1)
        .scaleEffect(card ? artworkScale : 1)
        .animation(EchoMotion.motion(EchoMotion.bouncy, reduceMotion: reduceMotion), value: artworkScale)
        // Follows the finger when swiped; the neighbor moves along beside it.
        .offset(x: big && !full ? coverSwipe : 0)
        .contentShape(shape)
        // Tapping the small cover brings the large one back.
        .onTapGesture { if let panel { toggle(panel) } }
        .allowsHitTesting(!big)
        .offset(x: frame.minX, y: frame.minY)
        .accessibilityHidden(true)
    }

    /// One cover, clipped to its shape, casting its own shadow so it can travel.
    private func coverCard(_ image: UIImage, size: CGSize, shape: RoundedRectangle,
                           shadow: Bool, playing: Bool) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            // Only a soft shadow of the cover itself: no glow and no shape behind it.
            .shadow(color: .black.opacity(shadow ? 0.3 : 0), radius: 20, y: 12)
    }

    private func coverPlaceholder(size: CGSize, shape: RoundedRectangle, big: Bool) -> some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.12))
            Image(systemName: "music.note")
                .font(.system(size: big ? 90 : 24))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
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

    /// Same as `prepare`, but remembers recent covers, so skipping to a song whose cover
    /// was prepared ahead (the next and previous songs are) shows it at once.
    /// The song's prepared artwork, keyed by song and artwork revision: nothing is
    /// read or hashed on the main thread, and a cached song returns at once.
    static func cached(song: Song?) async -> PlayerArtworkImages {
        guard let song else { return .empty }
        let key = song.id.hashValue &+ song.artworkRevision &* 31
        if let hit = await PlayerArtworkCache.shared.images(for: key) { return hit }
        let data = await SongArtworkLoader.data(for: song)
        let images = await prepare(data)
        await PlayerArtworkCache.shared.remember(images, for: key)
        return images
    }

    /// The blurred backdrop for a song, read and prepared off the main thread.
    static func prepareBackdrop(song: Song?) async -> UIImage? {
        if let song, let hit = await PlayerArtworkCache.shared.images(for: song.id.hashValue &+ song.artworkRevision &* 31) {
            return hit.background
        }
        return await prepareBackdrop(await SongArtworkLoader.data(for: song))
    }

    static func cached(_ data: Data?) async -> PlayerArtworkImages {
        guard let data else { return .empty }
        let key = data.count &+ data.hashValue
        if let hit = await PlayerArtworkCache.shared.images(for: key) { return hit }
        let images = await prepare(data)
        await PlayerArtworkCache.shared.remember(images, for: key)
        return images
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
    private var scrubAtEdge: Bool {
        scrub.isActive && (scrub.position <= 0.25 || scrub.position >= scrub.duration - 0.25)
    }
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
                // A tick when you grab the bar, and a firmer one at either end.
                .sensoryFeedback(.selection, trigger: scrub.isActive) { _, active in
                    active && EchoHaptics.allows(essential: false)
                }
                .sensoryFeedback(.impact(weight: .light), trigger: scrubAtEdge) { _, atEdge in
                    atEdge && EchoHaptics.allows(essential: false)
                }



    }
    private static func formatTime(_ time: Double) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        let seconds = Int(time)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

actor PlayerArtworkCache {
    static let shared = PlayerArtworkCache()
    private var store: [Int: PlayerArtworkImages] = [:]
    private var order: [Int] = []

    func images(for key: Int) -> PlayerArtworkImages? { store[key] }

    func remember(_ images: PlayerArtworkImages, for key: Int) {
        if store.updateValue(images, forKey: key) == nil { order.append(key) }
        while order.count > 8 { store[order.removeFirst()] = nil }
    }
}
