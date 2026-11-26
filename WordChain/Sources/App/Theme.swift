import SwiftUI
import UIKit

/// Schakel's colours. Every colour has a light and a dark version.
enum Theme {
    static let background = adaptive(light: 0xFBF6EE, dark: 0x16131D)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x221E2B)
    static let surfaceRaised = adaptive(light: 0xF3ECE0, dark: 0x2D2838)
    static let ink = adaptive(light: 0x2A2233, dark: 0xF4EEF8)
    static let inkSoft = adaptive(light: 0x7A7085, dark: 0xA79FB3)
    static let line = adaptive(light: 0xE6DCCD, dark: 0x3A3446)
    static let accent = adaptive(light: 0xEF5B3A, dark: 0xFF7A57)
    static let accentSoft = adaptive(light: 0xFFE3D9, dark: 0x4A2A25)
    static let gold = adaptive(light: 0xF2A93B, dark: 0xF6BA57)
    static let correct = adaptive(light: 0x2FA56F, dark: 0x3CC384)
    static let correctSoft = adaptive(light: 0xD7F2E4, dark: 0x1D3B2E)
    static let hinted = adaptive(light: 0xE9A72A, dark: 0xF0B940)
    static let wrong = adaptive(light: 0xD6455A, dark: 0xF0607A)
    static let wrongSoft = adaptive(light: 0xF9DCE0, dark: 0x45222B)
    static let keyFill = adaptive(light: 0xEDE4D6, dark: 0x332D3F)

    static let cornerRadius: CGFloat = 14

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func roundedFont(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// A soft card used across the app.
struct CardBackground: ViewModifier {
    var fill: Color = Theme.surface

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
    }
}

extension View {
    func card(fill: Color = Theme.surface) -> some View { modifier(CardBackground(fill: fill)) }
}

/// Shrinks a little while pressed, like a physical button.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Side-to-side shake for a wrong answer.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 9
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 6), y: 0))
    }
}
