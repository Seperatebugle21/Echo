import SwiftUI
import UIKit
import ImageIO

/// Colors of an album or artist page, taken from its cover.
struct EchoCollectionColors {
    var tint: Color
    var background: [Color]
    static let plain = EchoCollectionColors(tint: .primary, background: [])
}

/// The prepared cover and colors of a collection page. Computed once per cover,
/// off the main thread, and remembered so returning to a page is instant.
struct EchoCollectionStyle: @unchecked Sendable {
    let cover: UIImage?
    let palette: ArtworkPalette?
    /// Covers with a light border (a white sleeve) sit on the page as a rounded card;
    /// the others run edge to edge and fade into the page.
    let lightEdges: Bool

    static func load(_ data: Data?) async -> EchoCollectionStyle? {
        guard let data else { return nil }
        let key = data.count &+ data.hashValue
        if let cached = await EchoCollectionStyleCache.shared.style(for: key) { return cached }
        let style = await Task.detached(priority: .userInitiated) { () -> EchoCollectionStyle in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cover = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1000,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else {
                return EchoCollectionStyle(cover: nil, palette: ArtworkPalette.from(imageData: data), lightEdges: false)
            }
            return EchoCollectionStyle(cover: UIImage(cgImage: cover),
                                       palette: ArtworkPalette.from(imageData: data),
                                       lightEdges: edgeLuminance(cover) > 0.82)
        }.value
        await EchoCollectionStyleCache.shared.remember(style, for: key)
        return style
    }

    /// Average brightness of the outermost pixels of a 16×16 version of the cover.
    private static func edgeLuminance(_ image: CGImage) -> Double {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return 0 }
        var sum = 0.0, count = 0.0
        for y in 0..<side {
            for x in 0..<side where x == 0 || y == 0 || x == side - 1 || y == side - 1 {
                let i = (y * side + x) * 4
                sum += (0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])) / 255
                count += 1
            }
        }
        return count > 0 ? sum / count : 0
    }
}

actor EchoCollectionStyleCache {
    static let shared = EchoCollectionStyleCache()
    private var styles: [Int: EchoCollectionStyle] = [:]
    private var order: [Int] = []

    func style(for key: Int) -> EchoCollectionStyle? { styles[key] }

    func remember(_ style: EchoCollectionStyle, for key: Int) {
        if styles.updateValue(style, forKey: key) == nil { order.append(key) }
        while order.count > 24 { styles[order.removeFirst()] = nil }
    }
}

/// An album or artist page: the cover at the top, the whole page filled with the
/// cover's colors at once, and the title, buttons and tracks tinted to match.
/// The cover stays still and centered; nothing zooms or drifts.
struct EchoCollectionPage<Info: View, Rows: View>: View {
    let artworkData: Data?
    @ViewBuilder let info: (EchoCollectionColors) -> Info
    @ViewBuilder let rows: (EchoCollectionColors) -> Rows

    @Environment(\.colorScheme) private var colorScheme
    @State private var style: EchoCollectionStyle?
    @State private var loaded = false

    private var colors: EchoCollectionColors {
        guard let palette = style?.palette else { return .plain }
        let dark = colorScheme == .dark
        let background = (dark ? palette.darkBackground : palette.lightBackground)
            .map { Color(red: $0.r, green: $0.g, blue: $0.b) }
        let tint = (dark ? palette.accentForDark : palette.accentForLight)
            .map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? .primary
        return EchoCollectionColors(tint: tint, background: background)
    }

    var body: some View {
        let card = style?.lightEdges ?? false
        let colors = self.colors
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(card: card, colors: colors)
                info(colors)
                    .padding(.horizontal, 20)
                    .padding(.top, card ? 18 : -24)
                rows(colors)
                    .padding(.top, 8)
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: loaded && !card ? .top : [])
        .background {
            ZStack {
                if colors.background.count > 1 {
                    LinearGradient(colors: colors.background, startPoint: .top, endPoint: .bottom)
                } else if let color = colors.background.first {
                    color
                }
            }
            .ignoresSafeArea()
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: artworkData) {
            let loadedStyle = await EchoCollectionStyle.load(artworkData)
            guard !Task.isCancelled else { return }
            style = loadedStyle
            loaded = true
        }
    }

    @ViewBuilder
    private func hero(card: Bool, colors: EchoCollectionColors) -> some View {
        let image = style?.cover
        if card {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { cover(image) }
                .clipShape(.rect(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .accessibilityHidden(true)
        } else {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { cover(image) }
                .clipped()
                .mask {
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.68),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func cover(_ image: UIImage?) -> some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if loaded {
                CachedSongArtwork(data: artworkData)
            }
        }
        .animation(.easeOut(duration: 0.2), value: image == nil)
    }
}

// MARK: - Building blocks

/// A small outlined label such as "Album" or a genre.
struct EchoCollectionPill: View {
    let text: Text
    let tint: Color
    var body: some View {
        text
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: .capsule)
            .overlay { Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1) }
    }
}

/// A round outlined icon button next to the title.
struct EchoCollectionIconButton: View {
    let symbol: String
    let tint: Color
    let label: LocalizedStringKey
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 50, height: 50)
                .background(tint.opacity(0.1), in: .circle)
                .overlay { Circle().strokeBorder(tint.opacity(0.4), lineWidth: 1) }
                .contentShape(.circle)
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel(label)
    }
}

/// Shuffle and the big round play button on the right of the action row.
struct EchoCollectionPlayButtons: View {
    let tint: Color
    let shuffle: () -> Void
    let play: () -> Void
    var body: some View {
        HStack(spacing: 18) {
            Button(action: shuffle) {
                Image(systemName: "shuffle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(HomePressStyle())
            .accessibilityLabel("shuffle_action")
            Button(action: play) {
                Image(systemName: "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.black.opacity(0.8))
                    .frame(width: 64, height: 64)
                    .background(tint, in: .circle)
                    .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5) }
                    .shadow(color: tint.opacity(0.4), radius: 10, y: 4)
                    .contentShape(.circle)
            }
            .buttonStyle(HomePressStyle())
            .accessibilityLabel("play_all_action")
        }
    }
}

/// A thin line in the page's tint between the header and the description or tracks.
struct EchoCollectionDivider: View {
    let tint: Color
    var body: some View {
        Rectangle().fill(tint.opacity(0.22)).frame(height: 1)
    }
}
