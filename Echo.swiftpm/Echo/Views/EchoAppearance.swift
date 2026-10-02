import SwiftUI

@MainActor @Observable final class EchoTheme {
    static let shared = EchoTheme()
    var mode: String { didSet { defaults.set(mode, forKey: "appearanceMode") } }
    var darkStyle: String { didSet { defaults.set(darkStyle, forKey: "darkBackgroundStyle") } }
    var gradient: Bool { didSet { save() } }
    var first: String { didSet { save() } }
    var second: String { didSet { save() } }
    var direction: String { didSet { save() } }
    var whiteText: Bool { didSet { save() } }
    @ObservationIgnored private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: "appearanceMode") ?? "system"
        darkStyle = defaults.string(forKey: "darkBackgroundStyle") ?? "charcoal"
        gradient = defaults.bool(forKey: "theme.gradient")
        first = defaults.string(forKey: "theme.first") ?? "182235"
        second = defaults.string(forKey: "theme.second") ?? "64478C"
        direction = defaults.string(forKey: "theme.direction") ?? "diagonal"
        whiteText = defaults.object(forKey: "theme.whiteText") as? Bool ?? true
    }
    private func save() {
        defaults.set(gradient, forKey: "theme.gradient")
        defaults.set(first, forKey: "theme.first")
        defaults.set(second, forKey: "theme.second")
        defaults.set(direction, forKey: "theme.direction")
        defaults.set(whiteText, forKey: "theme.whiteText")
    }
    var colorScheme: ColorScheme? {
        switch mode { case "dark": .dark; case "light": .light; case "custom": whiteText ? .dark : .light; default: nil }
    }
    var start: UnitPoint { direction == "horizontal" ? .leading : direction == "vertical" ? .top : .topLeading }
    var end: UnitPoint { direction == "horizontal" ? .trailing : direction == "vertical" ? .bottom : .bottomTrailing }
    var background: LinearGradient {
        LinearGradient(colors: [Color(echoHex: first), Color(echoHex: gradient ? second : first)], startPoint: start, endPoint: end)
    }
}

extension Color {
    init(echoHex: String) {
        let value = UInt32(echoHex, radix: 16) ?? 0x182235
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    @MainActor var echoHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

private struct EchoBackgroundModifier: ViewModifier {
    private let theme = EchoTheme.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usesCharcoal: Bool { colorScheme == .dark && theme.darkStyle == "charcoal" }

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(theme.mode == "custom" || usesCharcoal ? .hidden : .automatic)
            .background {
                if theme.mode == "custom" {
                    theme.background.ignoresSafeArea()
                } else if usesCharcoal {
                    Color(red: 0.11, green: 0.12, blue: 0.14).ignoresSafeArea()
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: theme.first)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: theme.second)
    }
}

struct ThemeSettingsView: View {
    @Bindable private var theme = EchoTheme.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let presets = ["182235", "000000", "202228", "F4E9D8", "DCEDE6", "364C43", "533859", "BDD5EF"]
    var body: some View {
        Form {
            Section("settings_appearance_title") {
                Picker("settings_appearance_title", selection: $theme.mode) {
                    Text("appearance_system").tag("system")
                    Text("appearance_light").tag("light")
                    Text("appearance_dark").tag("dark")
                    Text("theme_custom").tag("custom")
                }.pickerStyle(.segmented)
            }
            if theme.mode != "custom" {
                Section("appearance_dark_background") {
                    HStack(spacing: 16) {
                        darkCard("black", hex: "000000", key: "appearance_background_black")
                        darkCard("charcoal", hex: "1C1F24", key: "appearance_background_charcoal")
                    }.listRowBackground(Color.clear)
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("theme_preview").font(.title2.bold())
                        Text("theme_preview_detail").opacity(0.75)
                        Label("libraryview_songs", systemImage: "music.note")
                            .padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background((theme.whiteText ? Color.white : .black).opacity(0.12), in: .rect(cornerRadius: 16))
                    }.foregroundStyle(theme.whiteText ? Color.white : .black)
                        .padding(20).frame(maxWidth: .infinity)
                        .background(theme.background, in: .rect(cornerRadius: 24))
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                Section("theme_background") {
                    Picker("theme_background", selection: $theme.gradient) {
                        Text("theme_solid").tag(false)
                        Text("theme_gradient").tag(true)
                    }.pickerStyle(.segmented)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))]) {
                        ForEach(presets, id: \.self) { hex in
                            Button { theme.first = hex } label: {
                                Circle().fill(Color(echoHex: hex)).frame(width: 38, height: 38)
                                    .overlay { if theme.first == hex { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white).shadow(radius: 2) } }
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(Text("theme_color_code \(hex)"))
                                .accessibilityAddTraits(theme.first == hex ? .isSelected : [])
                        }
                    }
                    ColorPicker("theme_first_color", selection: colorBinding(first: true), supportsOpacity: false)
                    if theme.gradient {
                        ColorPicker("theme_second_color", selection: colorBinding(first: false), supportsOpacity: false)
                        Picker("theme_direction", selection: $theme.direction) {
                            Text("theme_horizontal").tag("horizontal")
                            Text("theme_vertical").tag("vertical")
                            Text("theme_diagonal").tag("diagonal")
                        }
                    }
                    Picker("theme_text", selection: $theme.whiteText) {
                        Text("theme_black_text").tag(false)
                        Text("theme_white_text").tag(true)
                    }.pickerStyle(.segmented)
                }
            }
        }.echoBackground().navigationTitle("settings_appearance_title").navigationBarTitleDisplayMode(.inline)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.88), value: theme.mode)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.88), value: theme.gradient)
    }
    private func colorBinding(first: Bool) -> Binding<Color> {
        Binding(get: { Color(echoHex: first ? theme.first : theme.second) }, set: { color in
            if first { theme.first = color.echoHex } else { theme.second = color.echoHex }
        })
    }
    private func darkCard(_ style: String, hex: String, key: LocalizedStringKey) -> some View {
        Button { theme.darkStyle = style } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 16).fill(Color(echoHex: hex)).frame(height: 70)
                    .overlay { if theme.darkStyle == style { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white).font(.title2) } }
                Text(key).font(.subheadline)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain).accessibilityAddTraits(theme.darkStyle == style ? .isSelected : [])
    }
}

extension View {
    func echoBackground() -> some View { modifier(EchoBackgroundModifier()) }
}
