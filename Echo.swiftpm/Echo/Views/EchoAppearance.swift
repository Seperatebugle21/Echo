import SwiftUI

private struct EchoBackgroundModifier: ViewModifier {
    @AppStorage("darkBackgroundStyle") private var darkBackgroundStyle = "black"
    @Environment(\.colorScheme) private var colorScheme

    private var usesCharcoal: Bool { colorScheme == .dark && darkBackgroundStyle == "charcoal" }

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(usesCharcoal ? .hidden : .automatic)
            .background {
                if usesCharcoal {
                    Color(red: 0.11, green: 0.12, blue: 0.14).ignoresSafeArea()
                }
            }
    }
}

extension View {
    func echoBackground() -> some View { modifier(EchoBackgroundModifier()) }
}
