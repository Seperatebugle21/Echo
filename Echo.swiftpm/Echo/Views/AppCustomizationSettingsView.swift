import SwiftUI

struct AppCustomizationSettingsView: View {
    @AppStorage(HomeConfiguration.storageKey) private var storedHome = ""
    @AppStorage(TabBarConfiguration.storageKey) private var storedTabs = ""
    @Environment(\.echoSystemColorScheme) private var systemScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private let theme = EchoTheme.shared
    private var home: HomeConfiguration { .decode(storedHome) }
    private var tabs: TabBarConfiguration { .decode(storedTabs) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("customization_intro_title").font(.title2.bold())
                    Text("customization_intro_detail").font(.subheadline).foregroundStyle(.secondary)
                }
                CustomizationAppPreview(sections: home.sections, tabs: tabs)
                AccentColorPanel()
                VStack(alignment: .leading, spacing: 12) {
                    Text("customization_layout_title").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    NavigationLink { HomeSettingsView() } label: {
                        CustomizationDestinationCard(title: "home_customization_title", detail: "customization_home_detail", symbol: "house.fill") {
                            HStack(spacing: 10) {
                                ForEach(Array(home.sections.prefix(3))) { section in
                                    CustomizationIcon(symbol: section.symbol, size: 36)
                                }
                                Spacer(minLength: 0)
                                Text("customization_home_count \(home.sections.count)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            }.accessibilityHidden(true)
                        }
                    }.accessibilityIdentifier("customization-home")
                    NavigationLink { TabBarSettingsView() } label: {
                        CustomizationDestinationCard(title: "settingsview_tab_bar", detail: "settingsview_tab_bar_detail", symbol: "rectangle.bottomthird.inset.filled") {
                            CustomizationTabsPreview(configuration: tabs)
                        }
                    }.accessibilityIdentifier("customization-tabs")
                }.buttonStyle(HomePressStyle())
                NavigationLink { ThemeSettingsView() } label: {
                    CustomizationDestinationCard(title: "settings_appearance_title", detail: "customization_appearance_detail", symbol: "circle.lefthalf.filled") {
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                        let palette = theme.palette(for: systemScheme)
                        layout {
                            appearanceSwatch("appearance_light", colors: [.white, Color(white: 0.92)], foreground: .black)
                            appearanceSwatch("appearance_dark", colors: [Color(white: 0.12), .black], foreground: .white)
                            appearanceSwatch("theme_custom", colors: [Color(echoHex: palette.first), Color(echoHex: palette.gradient ? palette.second : palette.first)],
                                             foreground: palette.whiteText ? .white : .black)
                        }.accessibilityHidden(true)
                    }
                }.buttonStyle(HomePressStyle()).accessibilityIdentifier("customization-appearance")
                Label("customization_saved_detail", systemImage: "checkmark.circle")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .echoBackground()
        .navigationTitle("settings_app_customization")
        .navigationBarTitleDisplayMode(.large)
    }

    private func appearanceSwatch(_ title: LocalizedStringKey, colors: [Color], foreground: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "textformat").font(.title3.weight(.semibold))
            Text(title).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(foreground)
        .padding(.vertical, 16).frame(maxWidth: .infinity)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08)) }
    }
}

private struct AccentColorPanel: View {
    @Bindable private var theme = EchoTheme.shared
    private var colorBinding: Binding<Color> {
        Binding(get: { theme.accentColor }, set: { theme.accent = EchoAccentColor(hex: $0.echoHex) })
    }
    private var selectedTitle: LocalizedStringKey {
        LocalizedStringKey(EchoAccentPreset.allCases.first { $0.color == theme.accent }?.titleKey ?? "theme_custom")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                CustomizationIcon(symbol: "paintpalette.fill")
                VStack(alignment: .leading, spacing: 4) {
                    Text("customization_accent_title").font(.headline)
                    Text(selectedTitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "slider.horizontal.3").foregroundStyle(Color.accentColor).accessibilityHidden(true)
            }
            Text("customization_accent_detail").font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 10)], spacing: 12) {
                ForEach(EchoAccentPreset.allCases) { preset in
                    let selected = theme.accent == preset.color
                    Button { theme.accent = preset.color } label: {
                        Circle().fill(Color(echoHex: preset.color.hex))
                            .overlay {
                                if selected {
                                    Image(systemName: "checkmark").font(.body.bold())
                                        .foregroundStyle(preset.color.usesWhiteForeground ? Color.white : .black)
                                }
                            }
                            .padding(5)
                            .overlay { Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2) }
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(HomePressStyle())
                    .accessibilityLabel(LocalizedStringKey(preset.titleKey))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("accent-preset-" + preset.rawValue)
                }
            }
            Divider()
            ColorPicker("customization_accent_custom", selection: colorBinding, supportsOpacity: false)
                .accessibilityIdentifier("accent-custom-color")
            Button {
                theme.accent = EchoAccentColor(hex: EchoAccentColor.defaultHex)
            } label: {
                Label("customization_accent_reset", systemImage: "arrow.counterclockwise")
                    .font(.subheadline).frame(minHeight: 44)
            }
            .disabled(theme.accent.hex == EchoAccentColor.defaultHex)
        }
        .padding(18).customizationSurface()
        .accessibilityIdentifier("customization-accent")
    }
}

private struct CustomizationAppPreview: View {
    let sections: [HomeSection]
    let tabs: TabBarConfiguration
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(verbatim: "Echo").font(.title.bold())
                Spacer()
                Text("customization_live_preview").font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1), in: .capsule)
            }
            CustomizationHomePreview(sections: sections)
            CustomizationTabsPreview(configuration: tabs)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 26).fill(Color.accentColor.opacity(0.06))
        }
        .customizationSurface(cornerRadius: 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("customization_live_preview")
    }
}

struct CustomizationHomePreview: View {
    let sections: [HomeSection]
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(sections.prefix(3))) { section in
                HStack(spacing: 10) {
                    CustomizationIcon(symbol: section.symbol, size: 32)
                    Text(LocalizedStringKey(section.titleKey)).font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !typeSize.isAccessibilitySize {
                        Image(systemName: section == .nowPlaying ? "waveform" : "rectangle.split.3x1.fill")
                            .font(.title3).foregroundStyle(Color.accentColor.opacity(0.6))
                    }
                }.padding(10)
                    .background(.primary.opacity(0.04), in: .rect(cornerRadius: 16))
            }
        }.accessibilityHidden(true)
    }
}

private struct CustomizationTabsPreview: View {
    let configuration: TabBarConfiguration
    var body: some View {
        HStack(spacing: 6) {
            ForEach(configuration.tabs) { tab in
                Image(systemName: tab.symbol).font(.body.weight(.medium))
                    .foregroundStyle(tab == configuration.startTab ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(tab == configuration.startTab ? Color.accentColor.opacity(0.1) : .clear, in: .rect(cornerRadius: 12))
            }
        }.padding(6).background(.primary.opacity(0.04), in: .rect(cornerRadius: 18))
            .accessibilityHidden(true)
    }
}

private struct CustomizationDestinationCard<Preview: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    @ViewBuilder let preview: () -> Preview
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                CustomizationIcon(symbol: symbol)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary).padding(.top, 4)
            }
            preview()
        }.padding(18).customizationSurface()
    }
}

struct CustomizationIcon: View {
    let symbol: String
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: symbol).font(size < 40 ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
            .foregroundStyle(Color.accentColor).frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.1), in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

extension View {
    func customizationSurface(cornerRadius: CGFloat = 22) -> some View {
        background(.thinMaterial, in: .rect(cornerRadius: cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.primary.opacity(0.07)) }
    }
}
