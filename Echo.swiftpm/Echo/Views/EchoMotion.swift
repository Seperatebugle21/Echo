import SwiftUI
import UIKit
import CoreImage

/// Echo's shared motion language. Every screen uses the same few springs, so
/// presses, transitions and scrolling feel like one continuous system.
enum EchoMotion {
    /// Quick response for presses and small state changes.
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.82)
    /// Default for content that moves or changes size.
    static let fluid = Animation.spring(response: 0.5, dampingFraction: 0.86)
    /// A soft overshoot for things that "land", like the cover when playback resumes.
    static let bouncy = Animation.spring(response: 0.46, dampingFraction: 0.66)
    /// Releases after a press spring back with a little life.
    static let release = Animation.spring(response: 0.42, dampingFraction: 0.6)
    /// Slow crossfades for backgrounds and colors.
    static let ambient = Animation.easeInOut(duration: 0.9)

    static func motion(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : animation
    }
}

// MARK: - Buttons

/// Pressing an icon control on the player: it sinks in, a soft halo appears and
/// it springs back on release.
struct EchoPlayerControlStyle: ButtonStyle {
    let halo: Bool
    let pressedScale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(halo: Bool = true, pressedScale: CGFloat = 0.84) {
        self.halo = halo
        self.pressedScale = pressedScale
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if halo {
                    Circle()
                        .fill(.white.opacity(configuration.isPressed ? 0.16 : 0))
                        .padding(-10)
                        .scaleEffect(configuration.isPressed || reduceMotion ? 1 : 0.5)
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .animation(
                reduceMotion ? nil : configuration.isPressed ? EchoMotion.snappy : EchoMotion.release,
                value: configuration.isPressed
            )
    }
}

// MARK: - Scrolling

/// Items in a horizontal rail ease down and fade slightly as they leave the edge,
/// so the rail feels like it flows instead of being cut off.
private struct EchoRailItemModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        let strength: Double = reduceMotion ? 0 : 1
        content.scrollTransition(.interactive(timingCurve: .easeOut), axis: .horizontal) { view, phase in
            view
                .scaleEffect(1 - abs(phase.value) * 0.08 * strength)
                .opacity(1 - abs(phase.value) * 0.35 * strength)
        }
    }
}

/// Sections settle into place as they scroll in and recede as they scroll out.
private struct EchoScrollSectionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        let strength: Double = reduceMotion ? 0 : 1
        content.scrollTransition(.interactive, axis: .vertical) { view, phase in
            view
                .scaleEffect(1 - abs(phase.value) * 0.05 * strength)
                .opacity(1 - abs(phase.value) * 0.4 * strength)
        }
    }
}

/// A one-time staggered entrance: content rises, sharpens and fades in.
private struct EchoRevealModifier: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 26)
            .onAppear {
                guard !shown else { return }
                let delay = Double(min(index, 8)) * 0.055
                withAnimation(reduceMotion ? .easeOut(duration: 0.2)
                              : .spring(response: 0.62, dampingFraction: 0.86).delay(delay)) {
                    shown = true
                }
            }
    }
}

/// A colored glow made from the content itself, like light passing through the artwork.
private struct EchoArtworkGlowModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                content
                    .blur(radius: radius)
                    .opacity(colorScheme == .dark ? opacity : opacity * 0.8)
                    .scaleEffect(0.94)
                    .offset(y: radius * 0.55)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

extension View {
    func echoRailItem() -> some View { modifier(EchoRailItemModifier()) }
    func echoScrollSection() -> some View { modifier(EchoScrollSectionModifier()) }
    func echoReveal(_ index: Int = 0) -> some View { modifier(EchoRevealModifier(index: index)) }
    func echoArtworkGlow(radius: CGFloat = 24, opacity: Double = 0.65) -> some View {
        modifier(EchoArtworkGlowModifier(radius: radius, opacity: opacity))
    }

    /// Marks the view a zoom navigation transition grows out of.
    @ViewBuilder
    func echoZoomSource(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace { matchedTransitionSource(id: id, in: namespace) } else { self }
    }

    /// The destination grows out of the matching `echoZoomSource`, and can be pulled back into it.
    @ViewBuilder
    func echoZoomDestination(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace { navigationTransition(.zoom(sourceID: id, in: namespace)) } else { self }
    }
}

// MARK: - Living backdrop

/// Slowly drifting, layered artwork colors behind the player and lyrics.
/// The input is an already blurred, small image, so no live blur runs per frame:
/// only layer transforms change, a few dozen times per second.
struct EchoLivingBackdrop: View {
    let image: UIImage?
    var animated = true
    var dim: Double = 0.42
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                // Opaque base: while one cover's colours fade into the next, both are
                // partly transparent, and the app must never show through.
                Color(white: 0.08)
                ZStack {
                    if let image {
                        EchoDriftingArtwork(
                            image: image, size: size,
                            animated: animated && !reduceMotion && scenePhase == .active
                                && !EchoPowerState.shared.lowPower
                        )
                        .id(ObjectIdentifier(image))
                        .transition(.opacity)
                    } else {
                        LinearGradient(
                            colors: [Color(white: 0.22), Color(white: 0.10)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        .transition(.opacity)
                    }
                }
                .animation(EchoMotion.ambient, value: image.map { ObjectIdentifier($0) })

                Color.black.opacity(dim)
                LinearGradient(
                    colors: [.black.opacity(0.06), .black.opacity(0.14), .black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Three slowly turning, drifting layers of the blurred cover. Animated by Core
/// Animation in the render server, so the motion stays smooth even while the app
/// itself is busy, and SwiftUI never redraws for it.
private struct EchoDriftingArtwork: UIViewRepresentable {
    let image: UIImage
    let size: CGSize
    let animated: Bool

    func makeUIView(context: Context) -> EchoDriftView { EchoDriftView() }

    func updateUIView(_ view: EchoDriftView, context: Context) {
        view.configure(image: image, size: size, animated: animated)
    }
}

final class EchoDriftView: UIView {
    private struct Layer {
        let scale: CGFloat
        let degreesPerSecond: Double
        let startAngle: Double
        let drift: CGSize
        let driftPeriod: Double
        let opacity: Float
        let soft: Bool
    }

    private static let specs = [
        Layer(scale: 1.6, degreesPerSecond: 4, startAngle: 0, drift: CGSize(width: 0.12, height: 0.06),
              driftPeriod: 82, opacity: 1, soft: false),
        Layer(scale: 1.05, degreesPerSecond: -7, startAngle: 110, drift: CGSize(width: 0.28, height: 0.18),
              driftPeriod: 57, opacity: 0.85, soft: true),
        Layer(scale: 0.8, degreesPerSecond: 10, startAngle: 230, drift: CGSize(width: 0.3, height: 0.24),
              driftPeriod: 44, opacity: 0.7, soft: true),
    ]
    private static let context = CIContext(options: [.cacheIntermediates: false])

    private var layersByIndex: [CALayer] = []
    private var imageID: ObjectIdentifier?
    private var builtSize: CGSize = .zero
    private var running = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(image: UIImage, size: CGSize, animated: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        if imageID != ObjectIdentifier(image) {
            imageID = ObjectIdentifier(image)
            let contents = Self.saturated(image) ?? image.cgImage
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in layersByIndex { layer.contents = contents }
            CATransaction.commit()
            if layersByIndex.isEmpty { build(size: size, contents: contents) }
        }
        if size != builtSize, !layersByIndex.isEmpty {
            let contents = layersByIndex.first?.contents
            layersByIndex.forEach { $0.removeFromSuperlayer() }
            layersByIndex = []
            build(size: size, contents: contents)
        }
        setRunning(animated)
    }

    private func build(size: CGSize, contents: Any?) {
        builtSize = size
        let side = max(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for spec in Self.specs {
            let layer = CALayer()
            let edge = side * spec.scale
            layer.bounds = CGRect(x: 0, y: 0, width: edge, height: edge)
            layer.position = center
            layer.contents = contents
            layer.contentsGravity = .resizeAspectFill
            layer.opacity = spec.opacity
            if spec.soft {
                let mask = CAGradientLayer()
                mask.type = .radial
                mask.frame = layer.bounds
                mask.colors = [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0.6).cgColor, UIColor.clear.cgColor]
                mask.locations = [0.24, 0.6, 1]
                mask.startPoint = CGPoint(x: 0.5, y: 0.5)
                mask.endPoint = CGPoint(x: 1, y: 1)
                layer.mask = mask
            }
            let start = spec.startAngle * .pi / 180
            layer.transform = CATransform3DMakeRotation(start, 0, 0, 1)

            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = start
            spin.toValue = start + (spec.degreesPerSecond > 0 ? 2 : -2) * .pi
            spin.duration = 360 / abs(spec.degreesPerSecond)
            spin.repeatCount = .infinity
            layer.add(spin, forKey: "spin")

            let drift = CABasicAnimation(keyPath: "position")
            drift.fromValue = CGPoint(x: center.x - spec.drift.width * size.width, y: center.y - spec.drift.height * size.height)
            drift.toValue = CGPoint(x: center.x + spec.drift.width * size.width, y: center.y + spec.drift.height * size.height)
            drift.duration = spec.driftPeriod / 2
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(drift, forKey: "drift")

            self.layer.addSublayer(layer)
            layersByIndex.append(layer)
        }
    }

    /// Pauses in place and resumes from the same spot.
    private func setRunning(_ run: Bool) {
        guard run != running else { return }
        running = run
        let root = layer
        if run {
            let paused = root.timeOffset
            root.speed = 1
            root.timeOffset = 0
            root.beginTime = 0
            root.beginTime = root.convertTime(CACurrentMediaTime(), from: nil) - paused
        } else {
            let now = root.convertTime(CACurrentMediaTime(), from: nil)
            root.speed = 0
            root.timeOffset = now
        }
    }

    /// The colors a little richer, like the previous `.saturation(1.35)`, done once per cover.
    private static func saturated(_ image: UIImage) -> CGImage? {
        guard let cg = image.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIColorControls") else { return cg }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(1.35, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage else { return cg }
        return context.createCGImage(output, from: input.extent) ?? cg
    }
}

/// A soft wash of the playing song's colors at the top of a page. It scrolls
/// away with the content and crossfades when the song changes.
struct EchoAmbientGlow: View {
    var height: CGFloat = 460
    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(ObjectIdentifier(image))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .saturation(1.4)
        .opacity(colorScheme == .dark ? 0.6 : 0.42)
        .mask {
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(0.7), location: 0.45),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .animation(EchoMotion.ambient, value: image.map { ObjectIdentifier($0) })
        .task(id: player.currentSong?.id) {
            let prepared = await PlayerArtworkImages.prepareBackdrop(song: player.currentSong)
            guard !Task.isCancelled else { return }
            image = prepared
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A page background washed in one cover's colors, for album, artist and show pages.
/// Respects Echo's custom and charcoal themes by leaving their base visible.
struct EchoArtworkWash: View {
    let data: Data?
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?
    private let theme = EchoTheme.shared

    private var drawsBase: Bool {
        theme.mode != "custom" && !theme.backgroundFromArtwork
            && !(colorScheme == .dark && theme.darkStyle == "charcoal")
    }

    var body: some View {
        ZStack(alignment: .top) {
            if drawsBase { Color(uiColor: .systemGroupedBackground) }
            ZStack {
                if let image {
                    EchoLivingBackdrop(image: image, animated: false, dim: 0)
                        .transition(.opacity)
                }
            }
            .frame(height: 520)
            .opacity(colorScheme == .dark ? 0.55 : 0.4)
            .mask {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.6), location: 0.5),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .animation(EchoMotion.ambient, value: image == nil)
        .task(id: data) {
            let prepared = await PlayerArtworkImages.prepareBackdrop(data)
            guard !Task.isCancelled else { return }
            image = prepared
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Moving cover

/// A cover that slowly drifts, zooms and breathes, filling its frame edge to edge.
/// Your own files have no motion artwork like Apple Music's video covers, so the
/// still image itself moves; only layer transforms change, 30 times a second.
struct EchoMovingArtwork: View {
    let image: UIImage?
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                if let image {
                    let lowPower = EchoPowerState.shared.lowPower
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                            paused: !animated || reduceMotion || lowPower || scenePhase != .active)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 36_000)
                        let moving = animated && !reduceMotion && !lowPower
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .scaleEffect(moving ? 1.1 + 0.06 * CGFloat(sin(t / 9)) : 1)
                            .offset(x: moving ? CGFloat(sin(t / 11)) * size.width * 0.035 : 0,
                                    y: moving ? CGFloat(cos(t / 13)) * size.height * 0.025 : 0)
                            .rotationEffect(.degrees(moving ? sin(t / 17) * 1.2 : 0))
                    }
                    .id(ObjectIdentifier(image))
                    .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .animation(EchoMotion.ambient, value: image.map { ObjectIdentifier($0) })
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Bottom blur

/// Content blurs softly as it slides under the tab bar and mini player, like Joi Tunes.
struct EchoBottomFade: View {
    var height: CGFloat = 150

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.7), location: 0.45),
                    .init(color: .black, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(height: height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Low Power Mode

/// Continuous decorative motion (drifting backdrops, moving covers, the spinning
/// record) pauses while Low Power Mode is on.
@MainActor @Observable
final class EchoPowerState {
    static let shared = EchoPowerState()
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                EchoPowerState.shared.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}

// MARK: - Hero artwork

/// A large, slowly moving cover that fades out at the bottom, used at the top of
/// playlist and artist pages (album pages run it edge to edge).
struct EchoHeroArtwork<Fallback: View>: View {
    let image: UIImage?
    var cornerRadius: CGFloat = 28
    @ViewBuilder var fallback: Fallback

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    if image == nil { fallback }
                    EchoMovingArtwork(image: image, animated: false)
                }
                .mask {
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.6),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Haptics

/// Settings > Appearance > Haptic feedback: full, limited (default) or off.
/// Limited keeps only the essentials: play/pause and swiping to another song.
enum EchoHaptics {
    static let key = "hapticsLevel"

    static func allows(essential: Bool) -> Bool {
        switch UserDefaults.standard.string(forKey: key) ?? "limited" {
        case "off": return false
        case "full": return true
        default: return essential
        }
    }
}
