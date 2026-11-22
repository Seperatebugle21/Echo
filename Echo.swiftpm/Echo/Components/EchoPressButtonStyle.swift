import SwiftUI

/// Shrinks a control slightly while pressed, like the system music player's transport buttons.
struct EchoPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.86
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == EchoPressButtonStyle {
    static var echoPress: EchoPressButtonStyle { EchoPressButtonStyle() }
}
