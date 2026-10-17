import SwiftUI

struct AppCustomizationSettingsView: View {
    var body: some View {
        Form {
            Section("settings_app_customization") {
                NavigationLink { HomeSettingsView() } label: {
                    Label("home_customization_title", systemImage: "house.fill")
                }
                NavigationLink { TabBarSettingsView() } label: {
                    Label("settingsview_tab_bar", systemImage: "rectangle.bottomthird.inset.filled")
                }
                NavigationLink { ThemeSettingsView() } label: {
                    Label("settings_appearance_title", systemImage: "circle.lefthalf.filled")
                }
            }
        }
        .echoBackground()
        .navigationTitle("settings_app_customization")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HomeSettingsView: View {
    @AppStorage(HomeConfiguration.storageKey) private var storedLayout = ""
    private var configuration: HomeConfiguration { .decode(storedLayout) }

    var body: some View {
        List {
            Section {
                ForEach(configuration.sections) { section in
                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            update { $0.remove(section) }
                        } label: {
                            Image(systemName: "minus.circle.fill").frame(width: 32, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .disabled(configuration.sections.count <= HomeConfiguration.minimumSections)
                        .accessibilityLabel(Text("home_customization_remove \(Text(LocalizedStringKey(section.titleKey)))"))
                        Label(LocalizedStringKey(section.titleKey), systemImage: section.symbol)
                    }
                }
                .onMove { source, destination in
                    var sections = configuration.sections
                    sections.move(fromOffsets: source, toOffset: destination)
                    update { $0.reorder(sections) }
                }
            } header: { Text("home_customization_sections") }
              footer: { Text("home_customization_detail") }
                .environment(\.editMode, .constant(.active))

            let available = HomeSection.allCases.filter { !configuration.sections.contains($0) }
            if !available.isEmpty {
                Section("home_customization_available") {
                    ForEach(available) { section in
                        Button {
                            update { $0.add(section) }
                        } label: {
                            HStack {
                                Label(LocalizedStringKey(section.titleKey), systemImage: section.symbol)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                            }.frame(minHeight: 44)
                        }
                        .accessibilityLabel(Text("home_customization_add \(Text(LocalizedStringKey(section.titleKey)))"))
                    }
                }
            }
            Section {
                Button("tabbarsettingsview_restore_defaults") { storedLayout = HomeConfiguration.defaults.encoded }
            }
        }
        .echoBackground()
        .navigationTitle("home_customization_title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func update(_ change: (inout HomeConfiguration) -> Void) {
        var next = configuration
        change(&next)
        storedLayout = next.encoded
    }
}
