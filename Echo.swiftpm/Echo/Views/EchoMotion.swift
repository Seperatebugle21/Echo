import SwiftUI
import UIKit

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
            .blur(radius: shown || reduceMotion ? 0 : 4)
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
                ZStack {
                    if let image {
                        EchoDriftingArtwork(
                            image: image, size: size,
                            animated: animated && !reduceMotion && scenePhase == .active
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

private struct EchoDriftingArtwork: View {
    let image: UIImage
    let size: CGSize
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { context in
            let t = animated ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 36_000) : 0
            let side = max(size.width, size.height)
            ZStack {
                // A full cover so the edges are never visible, even when rotated.
                layer(side: side * 1.6, angle: t * 4, x: CGFloat(sin(t / 13)) * size.width * 0.12,
                      y: CGFloat(cos(t / 17)) * size.height * 0.06, opacity: 1, soft: false)
                layer(side: side * 1.05, angle: -t * 7 + 110, x: CGFloat(cos(t / 9)) * size.width * 0.28,
                      y: CGFloat(sin(t / 11)) * size.height * 0.18, opacity: 0.85, soft: true)
                layer(side: side * 0.8, angle: t * 10 + 230, x: CGFloat(sin(t / 7 + 1)) * size.width * 0.3,
                      y: CGFloat(cos(t / 8 + 2)) * size.height * 0.24, opacity: 0.7, soft: true)
            }
            .frame(width: size.width, height: size.height)
            .saturation(1.35)
        }
    }

    @ViewBuilder
    private func layer(side: CGFloat, angle: Double, x: CGFloat, y: CGFloat,
                       opacity: Double, soft: Bool) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .mask {
                if soft {
                    RadialGradient(colors: [.black, .black.opacity(0.6), .clear],
                                   center: .center, startRadius: side * 0.12, endRadius: side * 0.5)
                } else {
                    Rectangle()
                }
            }
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
            .opacity(opacity)
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
            let data = player.currentSong?.coverData ?? player.currentSong?.imageData
            let prepared = await PlayerArtworkImages.prepareBackdrop(data)
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
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                            paused: !animated || reduceMotion || scenePhase != .active)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 36_000)
                        let moving = animated && !reduceMotion
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .scaleEffect(moving ? 1.1 + 0.06 * CGFloat(sin(t / 9)) : 1.02)
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
