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

/// Overscroll at the top of a collection page. Only the stretching cover and the
/// search pill read it, so the page itself is not rebuilt while you pull.
@MainActor @Observable
final class EchoPullState {
    var amount: CGFloat = 0
}

/// An album, artist or playlist page, like Joi Tunes: the cover at the top, the whole
/// page filled with the cover's colors at once, tinted title, buttons and tracks.
/// Pulling down stretches the cover over the top and reveals a search pill; pull far
/// enough and let go to search inside the page.
struct EchoCollectionPage<Info: View, Rows: View>: View {
    let artworkData: Data?
    /// Shown instead of the artwork from `artworkData`, e.g. a playlist's own cover.
    var heroImage: UIImage? = nil
    /// Up to four covers shown as a 2×2 collage (playlists without their own cover).
    var collage: [Data] = []
    /// Always show the cover as a rounded card (playlists).
    var cardStyle = false
    var searchText: Binding<String>? = nil
    /// Lets the page hide its own toolbar buttons while searching.
    var searchActive: Binding<Bool>? = nil
    @ViewBuilder let info: (EchoCollectionColors) -> Info
    @ViewBuilder let rows: (EchoCollectionColors) -> Rows

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var style: EchoCollectionStyle?
    @State private var loaded = false
    @State private var pull = EchoPullState()
    @State private var localSearching = false
    @State private var pastThreshold = false
    @State private var pageWidth: CGFloat = 390

    private var searching: Bool {
        get { searchActive?.wrappedValue ?? localSearching }
        nonmutating set {
            if let searchActive { searchActive.wrappedValue = newValue } else { localSearching = newValue }
        }
    }
    @FocusState private var searchFocused: Bool

    private static var searchThreshold: CGFloat { 90 }

    private var colors: EchoCollectionColors {
        guard let palette = style?.palette else { return .plain }
        let dark = colorScheme == .dark
        let background = (dark ? palette.darkBackground : palette.lightBackground)
            .map { Color(red: $0.r, green: $0.g, blue: $0.b) }
        let tint = (dark ? palette.accentForDark : palette.accentForLight)
            .map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? .primary
        return EchoCollectionColors(tint: tint, background: background)
    }

    /// Collages and covers with a light border sit on the page as a rounded card.
    private var card: Bool { cardStyle || (style?.lightEdges ?? false) }

    var body: some View {
        let colors = self.colors
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if searching {
                        // Results start right under the search field in the bar.
                        Color.clear.frame(height: topInset + 6)
                    } else {
                        hero(topInset: topInset)
                        info(colors)
                            .padding(.horizontal, 20)
                            .padding(.top, card ? 18 : -24)
                            .transition(.opacity)
                    }
                    rows(colors)
                        .padding(.top, 8)
                }
                .padding(.bottom, 40)
                .animation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion), value: searching)
            }
            .ignoresSafeArea(edges: .top)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, amount in
                pull.amount = max(0, amount)
                let past = amount > Self.searchThreshold
                if past != pastThreshold { pastThreshold = past }
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                // Released past the threshold: open the search field.
                if oldPhase == .interacting && newPhase != .interacting && pastThreshold
                    && searchText != nil && !searching {
                    openSearch()
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        }
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
        // No bar or blur at the top: the cover runs to the edge of the screen.
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .scrollEdgeEffectHidden(true, for: .top)
        // The search pill and, while searching, the search field live in the bar itself,
        // between the back and sort buttons.
        .toolbar {
            if searchText != nil {
                ToolbarItem(placement: .principal) {
                    if searching {
                        searchField
                    } else {
                        EchoPullSearchPill(pull: pull, threshold: Self.searchThreshold, tint: colors.tint)
                    }
                }
                if searching {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: closeSearch) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("action_close")
                        .tint(.primary)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(searching)
        .sensoryFeedback(.impact(weight: .light), trigger: pastThreshold) { _, past in
            past && EchoHaptics.allows(essential: false)
        }
        .task(id: artworkData) {
            let loadedStyle = await EchoCollectionStyle.load(artworkData)
            guard !Task.isCancelled else { return }
            style = loadedStyle
            loaded = true
        }
    }

    // MARK: Search

    private func openSearch() {
        withAnimation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion)) { searching = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            searchFocused = true
        }
    }

    private func closeSearch() {
        searchFocused = false
        withAnimation(EchoMotion.motion(EchoMotion.fluid, reduceMotion: reduceMotion)) {
            searchText?.wrappedValue = ""
            searching = false
        }
    }

    @ViewBuilder
    private var searchField: some View {
        if let searchText {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("collection_search", text: searchText)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.wrappedValue.isEmpty {
                    Button { searchText.wrappedValue = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(width: max(200, pageWidth - 110), height: 38)
            .background(.ultraThinMaterial, in: .capsule)
        }
    }

    // MARK: Hero

    @ViewBuilder
    private func hero(topInset: CGFloat) -> some View {
        let image = heroImage ?? style?.cover
        if card {
            EchoStretchingHero(pull: pull, anchor: .center) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if collage.count >= 2 && heroImage == nil {
                            EchoCoverCollage(covers: collage)
                        } else {
                            cover(image)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 26, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
            }
            .padding(.horizontal, 16)
            .padding(.top, topInset + 4)
            .accessibilityHidden(true)
        } else {
            EchoStretchingHero(pull: pull, anchor: .bottom) {
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

/// Grows with the pull so the cover always fills the top; nothing else redraws.
private struct EchoStretchingHero<Content: View>: View {
    let pull: EchoPullState
    let anchor: UnitPoint
    @ViewBuilder let content: Content

    var body: some View {
        content
            .scaleEffect(1 + pull.amount / 320, anchor: anchor)
            .offset(y: anchor == .bottom ? 0 : -pull.amount / 2)
    }
}

/// Appears while pulling down; fills in once letting go would open search.
private struct EchoPullSearchPill: View {
    let pull: EchoPullState
    let threshold: CGFloat
    let tint: Color

    var body: some View {
        let progress = min(1, max(0, (pull.amount - 20) / (threshold - 20)))
        let ready = pull.amount >= threshold
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.subheadline.weight(.semibold))
            Text("collection_search").font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(ready ? Color.black.opacity(0.8) : Color.primary)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background {
            Capsule().fill(ready ? AnyShapeStyle(tint) : AnyShapeStyle(.ultraThinMaterial))
        }
        .scaleEffect(0.7 + 0.3 * progress)
        .opacity(progress)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: ready)
        .accessibilityHidden(true)
    }
}

/// Four covers in a square, for playlists without their own cover.
struct EchoCoverCollage: View {
    let covers: [Data]
    var body: some View {
        let tiles = Array(covers.prefix(4))
        GeometryReader { geometry in
            let half = geometry.size.width / 2
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    tile(tiles, 0, half)
                    tile(tiles, 1, half)
                }
                HStack(spacing: 0) {
                    tile(tiles, 2, half)
                    tile(tiles, 3, half)
                }
            }
        }
    }

    private func tile(_ tiles: [Data], _ index: Int, _ side: CGFloat) -> some View {
        // Two covers repeat crosswise; three repeat the first in the last corner.
        let order = tiles.count == 2 ? [0, 1, 1, 0] : [0, 1, 2, 3]
        let data = tiles.isEmpty ? nil : tiles[order[index] % tiles.count]
        return CachedSongArtwork(data: data)
            .frame(width: side, height: side)
            .clipped()
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
