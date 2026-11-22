import SwiftUI
import UIKit

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
    @State private var source = HomeSpotlightGeometry()
    private var song: Song? { player.currentSong ?? fallback }

    var body: some View {
        Group {
            if let song {
                GeometryReader { geometry in
                    ZStack(alignment: .trailing) {
                        Button { open(song) } label: {
                            HomeNowPlayingCardFace(song: song, size: geometry.size)
                                .contentShape(.rect(cornerRadius: 22))
                        }.buttonStyle(HomePressStyle())
                            .accessibilityLabel(Text("\(song.title), \(song.artist)"))
                            .accessibilityIdentifier("home-now-playing-card")
                            .accessibilityHint(LocalizedStringKey(player.currentSong == nil ? "home_start_playback_hint" : "home_open_player_hint"))
                        // Sibling control avoids a button nested inside the card's button.
                        Button { toggle(song) } label: {
                            HomeSpotlightPlaybackSymbol().contentShape(.circle)
                        }
                        .background(.white, in: .circle).buttonStyle(HomePressStyle())
                        .padding(.trailing, 12).offset(y: min(44, geometry.size.height / 4))
                        .accessibilityIdentifier("home-now-playing-toggle")
                        .accessibilityLabel(LocalizedStringKey(player.playbackErrorKey != nil ? "audio_retry" :
                            player.currentSong != nil && player.isPlaying ? "home_pause" : "home_play"))
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { source.frame = $0 }
                .frame(height: typeSize.isAccessibilitySize ? max(cardHeight, 280) : cardHeight)
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
        if let current = player.currentSong {
            presentation.openFromHomeCard(song: current, frame: source.frame, reduceMotion: reduceMotion)
        }
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

private final class HomeSpotlightGeometry { var frame: CGRect = .zero }

/// The same noninteractive face is used while Home's card grows into Now Playing.
struct HomeNowPlayingCardFace: View {
    let song: Song
    let size: CGSize
    var showsPlaybackSymbol = false
    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The cover's frame inside a face of `size`; the expanding player flies the cover from here.
    static func coverFrame(for size: CGSize) -> CGRect {
        let side = min(116, size.width * 0.34)
        return CGRect(x: size.width - 29 - side, y: (size.height - side) / 2, width: side, height: side)
    }

    private var playing: Bool { player.currentSong?.id == song.id && player.isPlaying }

    var body: some View {
        let coverSide = min(116, size.width * 0.34)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(player.currentSong == nil ? "home_ready_to_play" : "home_now_playing"))
                    .font(.system(size: 9, weight: .semibold)).tracking(2)
                    .contentTransition(.opacity)
                VStack(alignment: .leading, spacing: 6) {
                    Text(song.title).font(.title3.bold()).lineLimit(2)
                    Text(song.artist).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
                .id(song.id)
                .transition(reduceMotion ? AnyTransition.opacity
                    : AnyTransition.asymmetric(
                        insertion: AnyTransition.offset(y: 12).combined(with: AnyTransition.opacity),
                        removal: AnyTransition.offset(y: -12).combined(with: AnyTransition.opacity)))
                HomePlaybackWave()
                    .frame(height: 28).padding(.top, 2)
                HomePlaybackProgress(isActive: player.currentSong != nil)
            }.frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: .bottomTrailing) {
                // The record slides out from behind the sleeve and spins while the song plays.
                HomeSpinningVinyl(song: song, spinning: playing && !reduceMotion)
                    .frame(width: coverSide, height: coverSide)
                    .offset(x: playing ? 22 : 10)
                SongArtworkView(song: song, cornerRadius: 12)
                    .id(song.id)
                    .transition(AnyTransition.scale(scale: 0.9).combined(with: AnyTransition.opacity))
                    .frame(width: coverSide, height: coverSide).homeCoverShadow().offset(x: -6)
            }.frame(width: coverSide + 14, height: coverSide).accessibilityHidden(true)
        }
        .foregroundStyle(.white).padding(16)
        .frame(width: size.width, height: size.height)
        .background { HomeSpotlightSurface(song: song, animated: playing) }
        .clipShape(.rect(cornerRadius: 22))
        .animation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion), value: song.id)
        .animation(EchoMotion.motion(EchoMotion.bouncy, reduceMotion: reduceMotion), value: playing)
        .overlay(alignment: .trailing) {
            if showsPlaybackSymbol {
                HomeSpotlightPlaybackSymbol().background(.white, in: .circle)
                    .padding(.trailing, 12).offset(y: min(44, size.height / 4))
            }
        }
    }
}

private struct HomeSpotlightPlaybackSymbol: View {
    @Environment(AudioPlayerManager.self) private var player
    var body: some View {
        Group {
            if player.isPreparingAudio {
                ProgressView().tint(.black)
            } else {
                Image(systemName: player.currentSong != nil && player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(.black)
            }
        }.frame(width: 44, height: 44)
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
    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var capturing = false

    private var animated: Bool {
        visible && player.currentSong != nil && player.isPlaying && !player.isPodcast &&
            !player.isPreparingAudio && !reduceMotion && scenePhase == .active
    }

    var body: some View {
        // Only Canvas redraws at display cadence; the Home layout never receives frame ticks.
        TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: !animated)) { _ in
            Canvas { drawing, size in
                let frame = player.homeVisualizationFrame()
                let time = ProcessInfo.processInfo.systemUptime
                let step = size.width / 32
                for index in 0..<32 {
                    let level = animated ? frame.level(at: index, time: time) : 0
                    let height = 2 + (size.height - 2) * level
                    let rect = CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2,
                                      width: max(1, step * 0.48), height: height)
                    drawing.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.white.opacity(0.8)))
                }
            }
        }
        .onAppear { visible = true; updateCapture() }
        .onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
        .onChange(of: animated) { updateCapture() }
        .onDisappear { visible = false; stopCapture() }
        .accessibilityHidden(true)
    }

    private func updateCapture() {
        if animated && !capturing {
            capturing = true
            player.beginHomeVisualization()
        } else if !animated { stopCapture() }
    }
    private func stopCapture() {
        guard capturing else { return }
        capturing = false
        player.endHomeVisualization()
    }
}

/// The record: static grooves in SwiftUI, and a turning label and light streak drawn
/// by Core Animation, so it keeps spinning smoothly even while the app is busy.
private struct HomeSpinningVinyl: View {
    let song: Song
    let spinning: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = true

    private var active: Bool {
        spinning && visible && scenePhase == .active && !EchoPowerState.shared.lowPower
    }

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.08))
            ForEach([0.58, 0.72, 0.86, 0.97], id: \.self) { scale in
                Circle().stroke(.white.opacity(0.1), lineWidth: 1).scaleEffect(scale)
            }
            HomeVinylSpinner(song: song, spinning: active, tint: UIColor(Color.accentColor))
            Circle().fill(.black).scaleEffect(0.06)
        }
        .overlay { Circle().stroke(.white.opacity(0.15), lineWidth: 1) }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
    }
}

private struct HomeVinylSpinner: UIViewRepresentable {
    let song: Song
    let spinning: Bool
    let tint: UIColor

    func makeUIView(context: Context) -> HomeVinylSpinnerView { HomeVinylSpinnerView() }

    func updateUIView(_ view: HomeVinylSpinnerView, context: Context) {
        view.show(song: song, tint: tint)
        view.setSpinning(spinning)
    }
}

final class HomeVinylSpinnerView: UIView {
    private let rotor = CALayer()
    private let streak = CAGradientLayer()
    private let label = CALayer()
    private let labelTint = CALayer()
    private var songKey: SongArtworkKey?
    private var spinning = true
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        streak.type = .conic
        streak.startPoint = CGPoint(x: 0.5, y: 0.5)
        streak.endPoint = CGPoint(x: 0.5, y: 0)
        streak.colors = [UIColor.clear, UIColor.white.withAlphaComponent(0.14), UIColor.clear, UIColor.clear,
                         UIColor.white.withAlphaComponent(0.1), UIColor.clear].map(\.cgColor)
        label.contentsGravity = .resizeAspectFill
        label.masksToBounds = true
        label.backgroundColor = UIColor(white: 0.2, alpha: 1).cgColor
        rotor.addSublayer(streak)
        rotor.addSublayer(label)
        label.addSublayer(labelTint)
        layer.addSublayer(rotor)
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi
        spin.duration = 360.0 / 55.0
        spin.repeatCount = .infinity
        rotor.add(spin, forKey: "spin")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rotor.frame = bounds
        streak.frame = bounds
        streak.cornerRadius = bounds.width / 2
        streak.masksToBounds = true
        let side = bounds.width * 0.36
        label.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        label.cornerRadius = side / 2
        labelTint.frame = label.bounds
        CATransaction.commit()
    }

    func show(song: Song, tint: UIColor) {
        labelTint.backgroundColor = tint.withAlphaComponent(0.18).cgColor
        let key = SongArtworkKey(song, pixels: 150)
        guard key != songKey else { return }
        songKey = key
        if let cached = SongArtworkLoader.cachedImage(key) {
            label.contents = cached.cgImage
            return
        }
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            let image = await SongArtworkLoader.image(for: song, key: key)
            guard !Task.isCancelled, let self, self.songKey == key else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.label.contents = image?.cgImage
            CATransaction.commit()
        }
    }

    /// Stops in place and continues from the same angle.
    func setSpinning(_ run: Bool) {
        guard run != spinning else { return }
        spinning = run
        if run {
            let paused = rotor.timeOffset
            rotor.speed = 1
            rotor.timeOffset = 0
            rotor.beginTime = 0
            rotor.beginTime = rotor.convertTime(CACurrentMediaTime(), from: nil) - paused
        } else {
            let now = rotor.convertTime(CACurrentMediaTime(), from: nil)
            rotor.speed = 0
            rotor.timeOffset = now
        }
    }
}

/// The card's background: the song's own colors, softly drifting while it plays.
private struct HomeSpotlightSurface: View {
    let song: Song
    let animated: Bool
    @State private var backdrop: UIImage?
    @State private var visible = true

    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.25)
            EchoLivingBackdrop(image: backdrop, animated: false, dim: 0.22)
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.45)],
                           startPoint: .top, endPoint: .bottom)
        }
        .onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
        .task(id: song.id) {
            let prepared = await PlayerArtworkImages.prepareBackdrop(song: song)
            guard !Task.isCancelled else { return }
            backdrop = prepared
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
