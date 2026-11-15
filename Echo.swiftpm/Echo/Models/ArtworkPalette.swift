import Foundation
import ImageIO

/// Colors taken from album artwork for the "colors from the cover" theme.
///
/// The accent is the most prominent vivid color, adjusted so it stays readable on
/// light and dark backgrounds. The backgrounds are the cover's dominant colors,
/// darkened for dark mode and softened for light mode so text stays legible.
struct ArtworkPalette: Equatable, Sendable {
    struct RGB: Equatable, Hashable, Sendable {
        var r, g, b: Double // 0...1

        var hex: String {
            func channel(_ value: Double) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
            return String(format: "%02X%02X%02X", channel(r), channel(g), channel(b))
        }

        /// WCAG relative luminance.
        var luminance: Double {
            func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }

        var hsb: (h: Double, s: Double, b: Double) {
            let maxValue = max(r, g, b), minValue = min(r, g, b), delta = maxValue - minValue
            var hue = 0.0
            if delta > 0 {
                if maxValue == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
                else if maxValue == g { hue = (b - r) / delta + 2 }
                else { hue = (r - g) / delta + 4 }
                hue /= 6
                if hue < 0 { hue += 1 }
            }
            return (hue, maxValue == 0 ? 0 : delta / maxValue, maxValue)
        }

        init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

        init(hue: Double, saturation: Double, brightness: Double) {
            let h = (hue - floor(hue)) * 6, c = brightness * saturation
            let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = brightness - c
            let (r, g, b): (Double, Double, Double)
            switch Int(h) {
            case 0: (r, g, b) = (c, x, 0)
            case 1: (r, g, b) = (x, c, 0)
            case 2: (r, g, b) = (0, c, x)
            case 3: (r, g, b) = (0, x, c)
            case 4: (r, g, b) = (x, 0, c)
            default: (r, g, b) = (c, 0, x)
            }
            self.init(r: r + m, g: g + m, b: b + m)
        }

        static func contrast(_ a: RGB, _ b: RGB) -> Double {
            let (light, dark) = a.luminance > b.luminance ? (a.luminance, b.luminance) : (b.luminance, a.luminance)
            return (light + 0.05) / (dark + 0.05)
        }
    }

    /// Vivid color from the cover, or nil for grayscale artwork (the chosen accent is kept).
    var accent: RGB?
    var accentForDark: RGB?
    var accentForLight: RGB?
    var darkBackground: [RGB]
    var lightBackground: [RGB]

    // MARK: Extraction

    /// Builds a palette from RGBA bytes (8 bits per channel).
    static func from(rgba pixels: [UInt8]) -> ArtworkPalette? {
        var buckets: [Int: (count: Double, r: Double, g: Double, b: Double)] = [:]
        var total = 0.0
        for index in stride(from: 0, to: pixels.count - 3, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(pixels[index]) / 255, g = Double(pixels[index + 1]) / 255, b = Double(pixels[index + 2]) / 255
            // 4 levels per channel: 64 buckets, averaged inside each.
            let key = Int(r * 3.999) << 4 | Int(g * 3.999) << 2 | Int(b * 3.999)
            var bucket = buckets[key] ?? (0, 0, 0, 0)
            bucket.count += 1; bucket.r += r; bucket.g += g; bucket.b += b
            buckets[key] = bucket
            total += 1
        }
        guard total > 0 else { return nil }
        let colors = buckets.values
            .map { (color: RGB(r: $0.r / $0.count, g: $0.g / $0.count, b: $0.b / $0.count), share: $0.count / total) }
            .sorted { $0.share > $1.share }

        // Accent: frequent and saturated, not near-black or near-white.
        let vivid = colors.compactMap { item -> (RGB, Double)? in
            let hsb = item.color.hsb
            guard hsb.s > 0.3, hsb.b > 0.25, item.share > 0.02 else { return nil }
            return (item.color, item.share * hsb.s * hsb.s * min(1, hsb.b + 0.2))
        }.max { $0.1 < $1.1 }?.0

        // Background: the two most common colors that differ visibly.
        let first = colors[0].color
        let second = colors.dropFirst().first { distance($0.color, first) > 0.18 }?.color ?? first

        return ArtworkPalette(
            accent: vivid,
            accentForDark: vivid.map { readable($0, onDark: true) },
            accentForLight: vivid.map { readable($0, onDark: false) },
            darkBackground: [first, second].map { tone($0, dark: true) },
            lightBackground: [first, second].map { tone($0, dark: false) })
    }

    /// Decodes and downsamples artwork, then builds a palette. Safe off the main thread.
    static func from(imageData data: Data) -> ArtworkPalette? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 40
              ] as CFDictionary) else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return from(rgba: pixels)
    }

    // MARK: Adjustments

    private static func distance(_ a: RGB, _ b: RGB) -> Double {
        sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))
    }

    /// Dark mode: deep, muted versions. Light mode: pale versions.
    static func tone(_ color: RGB, dark: Bool) -> RGB {
        let hsb = color.hsb
        return dark
            ? RGB(hue: hsb.h, saturation: min(hsb.s, 0.55), brightness: min(max(hsb.b * 0.35, 0.08), 0.24))
            : RGB(hue: hsb.h, saturation: min(hsb.s, 0.22), brightness: max(0.92, hsb.b))
    }

    /// Shifts brightness until the accent reaches 3:1 contrast with the matching background extreme.
    static func readable(_ color: RGB, onDark: Bool) -> RGB {
        let backdrop = onDark ? RGB(r: 0.1, g: 0.1, b: 0.1) : RGB(r: 0.97, g: 0.97, b: 0.97)
        var hsb = color.hsb
        var result = color
        for _ in 0..<20 where RGB.contrast(result, backdrop) < 3 {
            if onDark {
                hsb.b = min(1, hsb.b + 0.06)
                if hsb.b >= 1 { hsb.s = max(0, hsb.s - 0.08) }
            } else {
                hsb.b = max(0, hsb.b - 0.06)
            }
            result = RGB(hue: hsb.h, saturation: hsb.s, brightness: hsb.b)
        }
        return result
    }
}
