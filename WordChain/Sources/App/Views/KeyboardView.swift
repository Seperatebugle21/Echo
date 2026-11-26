import SwiftUI

/// On-screen keyboard. Both languages use the same Latin letters.
struct KeyboardView: View {
    var enterTitle: String
    var enterEnabled: Bool
    var onLetter: (Character) -> Void
    var onDelete: () -> Void
    var onEnter: () -> Void

    private let rows: [[Character]] = [
        Array("qwertyuiop"),
        Array("asdfghjkl"),
        Array("zxcvbnm"),
    ]

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 6
            let keyWidth = min((proxy.size.width - spacing * 9) / 10, 48)
            let keyHeight = min(keyWidth * 1.35, 56)
            VStack(spacing: 8) {
                HStack(spacing: spacing) {
                    ForEach(rows[0], id: \.self) { key($0, width: keyWidth, height: keyHeight) }
                }
                HStack(spacing: spacing) {
                    ForEach(rows[1], id: \.self) { key($0, width: keyWidth, height: keyHeight) }
                }
                HStack(spacing: spacing) {
                    actionKey(width: keyWidth * 1.5 + spacing / 2, height: keyHeight) {
                        Text(enterTitle)
                            .font(Theme.roundedFont(13, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } action: {
                        onEnter()
                    }
                    .opacity(enterEnabled ? 1 : 0.55)
                    ForEach(rows[2], id: \.self) { key($0, width: keyWidth, height: keyHeight) }
                    actionKey(width: keyWidth * 1.5 + spacing / 2, height: keyHeight) {
                        Image(systemName: "delete.left.fill").font(.system(size: 19, weight: .semibold))
                    } action: {
                        onDelete()
                    }
                    .accessibilityLabel("Delete")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 190)
    }

    private func key(_ letter: Character, width: CGFloat, height: CGFloat) -> some View {
        Button {
            Haptics.tap()
            onLetter(letter)
        } label: {
            Text(String(letter).uppercased())
                .font(Theme.roundedFont(20, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: width, height: height)
                .background(Theme.keyFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 0, y: 2)
        }
        .buttonStyle(KeyPressStyle())
    }

    private func actionKey<Label: View>(width: CGFloat, height: CGFloat, @ViewBuilder label: () -> Label,
                                        action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            label()
                .foregroundStyle(Theme.ink)
                .frame(width: width, height: height)
                .background(Theme.line, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 0, y: 2)
        }
        .buttonStyle(KeyPressStyle())
    }
}

/// Keys pop up a little while pressed.
private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.12 : 1)
            .offset(y: configuration.isPressed ? -4 : 0)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
