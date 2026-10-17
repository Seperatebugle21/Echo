import Foundation

/// Opaque sRGB colors keep the accent independent of the app's background palettes.
struct EchoAccentColor: Equatable, Sendable {
    static let storageKey = "theme.accentColor"
    static let defaultHex = "FF3B30"
    let hex: String

    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") { value.removeFirst() }
        self.hex = value.count == 6 && value.allSatisfy { "0123456789ABCDEF".contains($0) } ? value : Self.defaultHex
    }

    /// Pick the more legible checkmark on both bright and dark swatches.
    var usesWhiteForeground: Bool {
        let rgb = UInt32(hex, radix: 16) ?? 0xFF3B30
        func linear(_ channel: UInt32) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear((rgb >> 16) & 255) + 0.7152 * linear((rgb >> 8) & 255) + 0.0722 * linear(rgb & 255)
        return luminance < 0.179
    }
}

enum EchoAccentPreset: String, CaseIterable, Identifiable {
    case red, orange, gold, green, mint, teal, blue, indigo, purple, pink
    var id: String { rawValue }
    var titleKey: String { "accent_color_" + rawValue }
    var color: EchoAccentColor {
        let hex: String
        switch self {
        case .red: hex = EchoAccentColor.defaultHex
        case .orange: hex = "FF9500"
        case .gold: hex = "E5AC16"
        case .green: hex = "248A3D"
        case .mint: hex = "00A88F"
        case .teal: hex = "008B9E"
        case .blue: hex = "007AFF"
        case .indigo: hex = "5856D6"
        case .purple: hex = "AF52DE"
        case .pink: hex = "E83E80"
        }
        return EchoAccentColor(hex: hex)
    }
}
