import SwiftUI

/// What Now Playing shows in place of the large cover, like Apple Music's lyrics and queue.
enum NowPlayingPanel: Equatable {
    case lyrics, queue
}

// MARK: - Lyrics

/// The lyrics engine shared by Now Playing and the standalone lyrics screen.
///
/// Playback time is read only by a tiny tracker view. This view and its lines are
/// rebuilt when the sung line changes, not on every playback tick.
struct LyricsScroller: View {
    var embedded = false

    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("developerShowLyricsSources") private var showLyricsSources = false
    @State private var selectedProvider = LyricsProvider.automatic
    @State private var lines: [LyricLine] = []
    @State private var activeIndex = -1
    @State private var userScrolling = false
    @State private var resumeTask: Task<Void, Never>?
    /// The first position is set instantly, so opening lyrics never scrolls through the song.
    @State private var placed = false
    /// Drives the one-time cascade when the lyrics appear.
    @State private var entered = false

    private var anchor: UnitPoint { UnitPoint(x: 0.5, y: embedded ? 0.24 : 0.3) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                // Lazy: only the lines on screen are built and rendered.
                LazyVStack(alignment: .leading, spacing: embedded ? 22 : 26) {
                    if lines.isEmpty {
                        if let lyrics = audioPlayer.currentLyrics, !lyrics.isEmpty {
                            Text(lyrics)
                                .font(.system(size: embedded ? 24 : 26, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineSpacing(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        } else if !audioPlayer.isLoadingLyrics {
                            unavailableView.transition(.opacity)
                        }
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            LyricsLineRow(
                                text: line.text,
                                distance: activeIndex < 0 ? index + 1 : index - activeIndex,
                                userScrolling: userScrolling,
                                size: embedded ? 30 : 32,
                                reduceMotion: reduceMotion,
                                entered: entered,
                                order: min(abs(index - max(activeIndex, 0)), 10)
                            ) {
                                audioPlayer.seek(to: line.time)
                                userScrolling = false
                            }
                            .id(index)
                        }
                    }
                    if showLyricsSources { sourceControls }
                    if audioPlayer.isLoadingLyrics {
                        LyricsBreathingDots(active: true)
                            .padding(.vertical, 12)
                            .transition(.opacity)
                    }
                    if let key = audioPlayer.lyricsStatusKey {
                        Text(LocalizedStringKey(key)).font(.footnote).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, embedded ? 28 : 24)
                .padding(.top, embedded ? 36 : 110)
                .padding(.bottom, embedded ? 260 : 340)
                .animation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion), value: lines.isEmpty)
            }
            // Lines dissolve into the edges instead of being cut off.
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: embedded ? 0.1 : 0.08),
                    .init(color: .black, location: 0.86),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .interacting, .tracking:
                    resumeTask?.cancel()
                    if !userScrolling {
                        withAnimation(.easeOut(duration: 0.25)) { userScrolling = true }
                    }
                case .idle:
                    guard userScrolling else { return }
                    resumeTask?.cancel()
                    resumeTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.4)) { userScrolling = false }
                        follow(proxy, to: activeIndex)
                    }
                default:
                    break
                }
            }
            .background {
                LyricsTimeTracker(times: lines.map(\.time)) { index in
                    guard index != activeIndex else { return }
                    activeIndex = index
                    guard !userScrolling, index >= 0 else { return }
                    if placed {
                        follow(proxy, to: index)
                    } else {
                        placed = true
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { proxy.scrollTo(index, anchor: anchor) }
                    }
                }
            }
            .onAppear {
                parseLyrics()
                if activeIndex >= 0 { proxy.scrollTo(activeIndex, anchor: anchor) }
                Task { @MainActor in
                    await Task.yield()
                    entered = true
                }
            }
            .onChange(of: lines.count) {
                if activeIndex >= 0 { proxy.scrollTo(activeIndex, anchor: anchor) }
            }
        }
        .onChange(of: audioPlayer.currentSyncedLyrics) { parseLyrics() }
        .onChange(of: audioPlayer.currentLyrics) { parseLyrics() }
        .onChange(of: audioPlayer.currentSong?.id) {
            selectedProvider = .automatic
            activeIndex = -1
            placed = false
        }
        .onChange(of: showLyricsSources) { if !showLyricsSources { selectedProvider = .automatic } }
        .onDisappear { resumeTask?.cancel() }
    }

    private func follow(_ proxy: ScrollViewProxy, to index: Int) {
        guard index >= 0 else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.7, dampingFraction: 0.86)) {
            proxy.scrollTo(index, anchor: anchor)
        }
    }

    private func parseLyrics() {
        guard let synced = audioPlayer.currentSyncedLyrics else {
            lines = []
            return
        }
        lines = synced.components(separatedBy: .newlines).compactMap(Self.parseLine)
    }

    private static func parseLine(_ line: String) -> LyricLine? {
        guard line.hasPrefix("["), let closing = line.firstIndex(of: "]") else { return nil }
        let timeString = String(line[line.index(after: line.startIndex)..<closing])
        let text = String(line[line.index(after: closing)...]).trimmingCharacters(in: .whitespaces)
        let parts = timeString.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return LyricLine(time: minutes * 60 + seconds, text: text)
    }

    @ViewBuilder
    private var unavailableView: some View {
        if audioPlayer.lyricsNeedsInternet {
            ContentUnavailableView(LocalizedStringKey("lyrics_wifi_needed_title"), systemImage: "wifi",
                description: Text(LocalizedStringKey("lyrics_wifi_needed_description")))
                .foregroundStyle(.white)
        } else {
            ContentUnavailableView(LocalizedStringKey("lyrics_unavailable_title"), systemImage: "text.quote",
                description: Text(LocalizedStringKey("lyrics_unavailable_description")))
                .foregroundStyle(.white)
        }
    }

    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if audioPlayer.currentLyrics != nil || audioPlayer.currentSyncedLyrics != nil {
                HStack {
                    Text(LocalizedStringKey(audioPlayer.currentLyricsSource?.titleKey ?? "lyrics_source_unknown"))
                    Text(verbatim: "·")
                    Text(LocalizedStringKey(lines.isEmpty ? "lyrics_plain" : "lyrics_synchronized"))
                }
                .font(.caption)
            }
            Picker("lyrics_choose_source", selection: $selectedProvider) {
                ForEach(LyricsProvider.allCases) { provider in
                    Text(LocalizedStringKey(provider.titleKey)).tag(provider)
                }
            }
            .pickerStyle(.menu)
            Button {
                audioPlayer.refreshLyrics(provider: selectedProvider)
            } label: {
                Label("lyrics_search_again", systemImage: "arrow.clockwise")
            }
            .disabled(audioPlayer.isLoadingLyrics || audioPlayer.currentSong == nil)
            if let url = audioPlayer.currentLyricsSourceURL, url.scheme == "https" {
                Link("lyrics_open_source", destination: url)
            }
        }
        .foregroundStyle(.white)
        .tint(.white)
    }
}

/// The only lyrics view that reads the playback clock.
private struct LyricsTimeTracker: View {
    let times: [Double]
    let onChange: (Int) -> Void
    @Environment(AudioPlayerManager.self) private var audioPlayer

    var body: some View {
        // A small lead, so a line lights up as it is sung rather than just after.
        let index = Self.index(at: audioPlayer.currentTime + 0.25, in: times)
        Color.clear
            .onChange(of: index, initial: true) { _, newIndex in onChange(newIndex) }
    }

    private static func index(at time: Double, in times: [Double]) -> Int {
        var low = 0, high = times.count - 1, result = -1
        while low <= high {
            let mid = (low + high) / 2
            if times[mid] <= time { result = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return result
    }
}

/// One lyric line. Lines after the sung one follow it with a small delay each,
/// so a line change ripples down the page.
private struct LyricsLineRow: View {
    let text: String
    let distance: Int
    let userScrolling: Bool
    let size: CGFloat
    let reduceMotion: Bool
    var entered = true
    var order = 0
    let action: () -> Void

    private var isCurrent: Bool { distance == 0 }

    private var opacity: Double {
        if isCurrent { return 1 }
        if userScrolling { return 0.6 }
        return distance < 0 ? 0.3 : 0.38
    }

    private var blur: CGFloat {
        guard !userScrolling, !reduceMotion, abs(distance) > 1 else { return 0 }
        return min(CGFloat(abs(distance) - 1) * 0.8, 2.6)
    }

    var body: some View {
        Button(action: action) {
            Group {
                if text.isEmpty {
                    LyricsBreathingDots(active: isCurrent)
                } else {
                    Text(text)
                        .font(.system(size: size, weight: .bold))
                        .multilineTextAlignment(.leading)
                }
            }
            .foregroundStyle(.white.opacity(opacity))
            .blur(radius: blur)
            .scaleEffect(isCurrent || reduceMotion ? 1 : 0.96, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(
            reduceMotion ? .easeOut(duration: 0.2)
                : .spring(response: 0.6, dampingFraction: 0.84)
                    .delay(Double(min(max(distance, 0), 6)) * 0.04),
            value: distance
        )
        .animation(.easeInOut(duration: 0.3), value: userScrolling)
        // Lines spring in one after another, starting at the sung line.
        .offset(y: entered || reduceMotion ? 0 : 44)
        .opacity(entered ? 1 : 0)
        .animation(
            reduceMotion ? .easeOut(duration: 0.2)
                : .spring(response: 0.6, dampingFraction: 0.72).delay(Double(order) * 0.045),
            value: entered
        )
    }
}

/// Three breathing dots for instrumental breaks and loading.
struct LyricsBreathingDots: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                if active && !reduceMotion {
                    Circle()
                        .frame(width: 11, height: 11)
                        .phaseAnimator([0.45, 1.0]) { dot, phase in
                            dot.scaleEffect(phase).opacity(phase)
                        } animation: { _ in
                            .easeInOut(duration: 0.75).delay(Double(index) * 0.18)
                        }
                } else {
                    Circle().frame(width: 11, height: 11).opacity(0.6)
                }
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}

// MARK: - Queue

/// The queue inside Now Playing: up next and autoplay, on the same living background.
struct NowPlayingQueuePanel: View {
    @Environment(AudioPlayerManager.self) private var audioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAutoNext = true
    @State private var entered = false

    private var upcoming: [Song] {
        Array(audioPlayer.queue.dropFirst(audioPlayer.currentIndex + 1))
    }

    var body: some View {
        List {
            if audioPlayer.repeatMode != .off {
                HStack(spacing: 10) {
                    Image(systemName: audioPlayer.repeatMode == .one ? "repeat.1" : "repeat")
                        .font(.subheadline.bold())
                    Text(audioPlayer.repeatMode == .one ? "repeat_one_active" : "repeat_all_active")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.white.opacity(0.12), in: .capsule)
                .panelRow()
            }

            let songs = upcoming
            if !songs.isEmpty {
                header("queue_up_next")
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    Button { audioPlayer.playFromQueue(song) } label: { QueuePanelRow(song: song) }
                        .buttonStyle(HomePressStyle())
                        .cascade(entered, order: index + 1, reduceMotion: reduceMotion)
                        .panelRow()
                }
                .onMove { from, to in
                    let offset = audioPlayer.currentIndex + 1
                    audioPlayer.moveQueue(from: IndexSet(from.map { $0 + offset }), to: to + offset)
                }
                .onDelete { offsets in
                    let offset = audioPlayer.currentIndex + 1
                    audioPlayer.removeFromQueue(at: IndexSet(offsets.map { $0 + offset }))
                }
            }

            if !audioPlayer.autoNextQueue.isEmpty {
                Button {
                    withAnimation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion)) {
                        showAutoNext.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("queue_auto_next").font(.title3.bold())
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .rotationEffect(.degrees(showAutoNext ? 0 : -90))
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 14)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .panelRow()

                if showAutoNext {
                    ForEach(Array(audioPlayer.autoNextQueue.enumerated()), id: \.element.id) { index, song in
                        Button {
                            if let url = audioPlayer.getURL(for: song) {
                                audioPlayer.play(song: song, url: url, queue: [])
                            }
                        } label: { QueuePanelRow(song: song).opacity(0.8) }
                            .buttonStyle(HomePressStyle())
                            .cascade(entered, order: songs.count + index + 2, reduceMotion: reduceMotion)
                            .panelRow()
                    }
                }
            }

            if songs.isEmpty && audioPlayer.autoNextQueue.isEmpty {
                Text("queue_up_next")
                    .font(.title3.bold())
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .panelRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.colorScheme, .dark)
        .contentMargins(.bottom, 40, for: .scrollContent)
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.05),
                .init(color: .black, location: 0.9),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .animation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion), value: upcoming.map(\.id))
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                entered = true
            }
        }
    }

    private func header(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.title3.bold())
            .foregroundStyle(.white)
            .padding(.top, 10)
            .panelRow()
            .moveDisabled(true)
            .deleteDisabled(true)
    }
}

private struct QueuePanelRow: View {
    let song: Song
    var body: some View {
        HStack(spacing: 12) {
            CachedSongArtwork(data: song.coverData ?? song.imageData)
                .frame(width: 46, height: 46)
                .clipShape(.rect(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.body.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Text(song.artist).font(.subheadline).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

private extension View {
    /// Rows spring in one after another the first time the panel appears.
    func cascade(_ entered: Bool, order: Int, reduceMotion: Bool) -> some View {
        offset(y: entered || reduceMotion ? 0 : 40)
            .opacity(entered ? 1 : 0)
            .animation(
                reduceMotion ? .easeOut(duration: 0.2)
                    : .spring(response: 0.55, dampingFraction: 0.72).delay(Double(min(order, 12)) * 0.04),
                value: entered
            )
    }

    func panelRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 24, bottom: 5, trailing: 24))
    }
}
