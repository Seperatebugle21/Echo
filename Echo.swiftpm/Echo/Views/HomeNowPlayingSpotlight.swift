import SwiftUI

/// Only this subtree reads playback state. Home's recommendations never observe time ticks.
struct HomeNowPlayingSpotlight: View {
    let fallback: Song?
    let queue: [Song]
    @Environment(AudioPlayerManager.self) private var player
    @Environment(MusicLibraryManager.self) private var library
    @Environment(MiniPlayerPresentation.self) private var presentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 176
    @State private var playbackFeedback = 0
    private var song: Song? { player.currentSong ?? fallback }

    var body: some View {
        Group {
            if let song {
                GeometryReader { geometry in
                    let coverSide = min(116, geometry.size.width * 0.34)
                    ZStack(alignment: .trailing) {
                        Button { open(song) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(LocalizedStringKey(player.currentSong == nil ? "home_ready_to_play" : "home_now_playing"))
                                        .font(.system(size: 9, weight: .semibold)).tracking(2)
                                    Text(song.title).font(.title3.bold()).lineLimit(2)
                                    Text(song.artist).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                                    HomePlaybackWave(isPlaying: player.currentSong != nil && player.isPlaying)
                                        .frame(height: 28).padding(.top, 2)
                                    HomePlaybackProgress(isActive: player.currentSong != nil)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                ZStack(alignment: .bottomTrailing) {
                                    HomeVinyl().frame(width: coverSide, height: coverSide).offset(x: 16)
                                    SongArtworkView(song: song, cornerRadius: 12)
                                        .frame(width: coverSide, height: coverSide).offset(x: -6)
                                }.frame(width: coverSide + 14, height: coverSide)
                                    .accessibilityHidden(true)
                            }.foregroundStyle(.white).padding(16)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .background { HomeArtworkSurface(song: song) }
                                .clipShape(.rect(cornerRadius: 22))
                        }.buttonStyle(HomePressStyle())
                            .accessibilityLabel(Text("\(song.title), \(song.artist)"))
                            .accessibilityHint(LocalizedStringKey(player.currentSong == nil ? "home_start_playback_hint" : "home_open_player_hint"))
                        // Sibling control avoids a button nested inside the card's button.
                        Button { toggle(song) } label: {
                            if player.isPreparingAudio {
                                ProgressView().tint(.black).frame(width: 44, height: 44)
                            } else {
                                Image(systemName: player.currentSong != nil && player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(.black)
                                    .frame(width: 44, height: 44)
                            }
                        }
                        .background(.white, in: .circle).buttonStyle(HomePressStyle())
                        .padding(.trailing, 12).offset(y: min(44, cardHeight / 4))
                        .accessibilityLabel(LocalizedStringKey(player.playbackErrorKey != nil ? "audio_retry" :
                            player.currentSong != nil && player.isPlaying ? "home_pause" : "home_play"))
                    }
                }.frame(height: typeSize.isAccessibilitySize ? max(cardHeight, 280) : cardHeight)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("homeview_empty_title", systemImage: "music.note").font(.headline)
                    Text("homeview_empty_description").font(.subheadline).foregroundStyle(.secondary)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: .rect(cornerRadius: 22))
            }
        }.sensoryFeedback(.selection, trigger: playbackFeedback)
    }

    private func open(_ song: Song) {
        if player.currentSong == nil { start(song) }
        if player.currentSong != nil { presentation.open(reduceMotion: reduceMotion) }
    }
    private func toggle(_ song: Song) {
        if player.currentSong == nil { start(song) } else { player.togglePlayPause() }
        playbackFeedback += 1
    }
    private func start(_ song: Song) {
        guard let url = library.getURL(for: song) else { return }
        player.lastPlaybackDirection = .fade
        player.play(song: song, url: url, queue: queue)
        player.allSongs = library.songs
        player.fillAutoNext(from: library.songs)
    }
}

private struct HomePlaybackProgress: View {
    let isActive: Bool
    @Environment(AudioPlayerManager.self) private var player
    var body: some View {
        let duration = isActive && player.duration.isFinite ? max(0, player.duration) : 0
        let time = isActive && player.currentTime.isFinite ? max(0, player.currentTime) : 0
        HStack(spacing: 6) {
            Text(verbatim: formatted(time))
            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.25))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.accentColor)
                            .frame(width: geometry.size.width * (duration > 0 ? min(1, time / duration) : 0))
                    }
            }.frame(height: 4)
            Text(verbatim: formatted(duration))
        }.font(.system(size: 10, weight: .medium)).monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("home_playback_progress")
            .accessibilityValue(Text("home_progress_value \(formatted(time)) \(formatted(duration))"))
    }
    private func formatted(_ value: Double) -> String {
        let seconds = Int(min(value, Double(Int.max / 2)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct HomePlaybackWave: View {
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        // Timeline is confined to a small Canvas and stopped while paused/backgrounded.
        let animated = isPlaying && !reduceMotion && scenePhase == .active
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !animated)) { context in
            Canvas { drawing, size in
                let phase = animated ? context.date.timeIntervalSinceReferenceDate * 2.4 : 0
                let count = 24
                let step = size.width / CGFloat(count)
                for index in 0..<count {
                    let envelope = 0.3 + 0.7 * sin(Double(index + 1) / Double(count + 1) * .pi)
                    let motion = animated ? 0.5 + 0.5 * sin(phase + Double(index) * 1.7) : 0.35
                    let height = max(3, size.height * envelope * motion)
                    let rect = CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2,
                                      width: max(1, step * 0.34), height: height)
                    drawing.fill(Path(roundedRect: rect, cornerRadius: 2),
                                 with: .color(index < 10 ? .accentColor : .white.opacity(0.55)))
                }
            }
        }.accessibilityHidden(true)
    }
}

private struct HomeVinyl: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.08))
            ForEach([0.58, 0.72, 0.86, 0.97], id: \.self) { scale in
                Circle().stroke(.white.opacity(0.1), lineWidth: 1).scaleEffect(scale)
            }
            Circle().fill(Color.accentColor).scaleEffect(0.26)
            Circle().fill(.black).scaleEffect(0.06)
        }.overlay { Circle().stroke(.white.opacity(0.15), lineWidth: 1) }
    }
}
