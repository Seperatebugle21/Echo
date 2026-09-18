import SwiftUI

enum AppTab: String, Codable, CaseIterable, Identifiable {
    case home, library, podcasts, fetch, search, settings, playlists, favorites, songs

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: "contentview_home"
        case .podcasts: "podcasts_title"
        case .library: "contentview_library"
        case .fetch: "contentview_fetch"
        case .search: "contentview_search"
        case .settings: "contentview_settings"
        case .playlists: "contentview_playlists"
        case .favorites: "contentview_favorites"
        case .songs: "contentview_songs"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .podcasts: "podcasts"
        case .library: "square.stack.fill"
        case .fetch: "arrow.down.circle"
        case .search: "magnifyingglass"
        case .settings: "gearshape.fill"
        case .playlists: "music.note.list"
        case .favorites: "heart.fill"
        case .songs: "music.note"
        }
    }
}

struct TabBarConfiguration: Codable, Equatable {
    static let storageKey = "tabBarConfiguration.v1"
    static let defaults = Self(tabs: [.home, .library, .podcasts, .fetch, .search], startTab: .home)
    var tabs: [AppTab]
    var schemaVersion: Int? = 2
    var startTab: AppTab

    static func load() -> Self {
        decode(UserDefaults.standard.string(forKey: storageKey) ?? "")
    }

    static func decode(_ value: String) -> Self {
        guard let data = value.data(using: .utf8),
              var configuration = try? JSONDecoder().decode(Self.self, from: data),
              (2...5).contains(configuration.tabs.count),
              Set(configuration.tabs).count == configuration.tabs.count else { return defaults }
        if configuration.schemaVersion == nil, configuration.tabs == [.home, .library, .fetch, .search] {
            configuration.tabs.insert(.podcasts, at: 2)
        }
        configuration.schemaVersion = 2
        if !configuration.tabs.contains(configuration.startTab) {
            configuration.startTab = configuration.tabs[0]
        }
        return configuration
    }

    var encoded: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    mutating func add(_ tab: AppTab) {
        guard tabs.count < 5, !tabs.contains(tab) else { return }
        tabs.append(tab)
    }

    mutating func remove(_ tab: AppTab) {
        guard tabs.count > 2, tabs.contains(tab) else { return }
        tabs.removeAll { $0 == tab }
        if startTab == tab { startTab = tabs[0] }
    }
}

struct TabBarSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TabBarConfiguration.storageKey) private var storedTabs = ""
    @State private var draft = TabBarConfiguration.load()

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(draft.tabs) { tab in
                        VStack(spacing: 6) {
                            Image(systemName: tab.symbol)
                                .font(.title3)
                            Text(tab.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(tab == draft.startTab ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .glassEffect(.regular, in: .capsule)
                .listRowBackground(Color.clear)
            } header: {
                Text("tabbarsettingsview_preview")
            } footer: {
                Text("tabbarsettingsview_reorder_hint")
            }

            Section {
                ForEach(draft.tabs) { tab in
                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            draft.remove(tab)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .frame(width: 32, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .disabled(draft.tabs.count <= 2)
                        .accessibilityLabel(Text("tabbarsettingsview_remove_tab \(Text(tab.title))"))

                        Label(tab.title, systemImage: tab.symbol)
                        Spacer()
                        Button {
                            draft.startTab = tab
                        } label: {
                            Image(systemName: draft.startTab == tab ? "star.fill" : "star")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("tabbarsettingsview_start_tab \(Text(tab.title))"))
                        .accessibilityValue(draft.startTab == tab ? Text("tabbarsettingsview_selected") : Text("tabbarsettingsview_not_selected"))
                    }
                }
                .onMove { source, destination in
                    draft.tabs.move(fromOffsets: source, toOffset: destination)
                }
            } header: {
                Text("tabbarsettingsview_your_tabs \(draft.tabs.count)")
            } footer: {
                Text("tabbarsettingsview_tab_limits")
            }
            .environment(\.editMode, .constant(.active))

            Section("tabbarsettingsview_available_tabs") {
                ForEach(AppTab.allCases.filter { !draft.tabs.contains($0) }) { tab in
                    Button {
                        draft.add(tab)
                    } label: {
                        HStack {
                            Label(tab.title, systemImage: tab.symbol)
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                    .disabled(draft.tabs.count >= 5)
                }
            }

            Section {
                Button("tabbarsettingsview_restore_defaults") { draft = .defaults }
            }
        }
        .navigationTitle("tabbarsettingsview_title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("tabbarsettingsview_save") {
                    storedTabs = draft.encoded
                    dismiss()
                }
            }
        }
    }
}
