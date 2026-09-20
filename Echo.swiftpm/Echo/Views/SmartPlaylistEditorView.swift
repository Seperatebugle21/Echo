import SwiftUI
import Combine

struct SmartPlaylistEditorView: View {
    @Environment(MusicLibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var configuration: SmartPlaylistConfiguration

    init(playlist: Playlist) {
        self.playlist = playlist
        // An editable draft, intentionally seeded once when the sheet opens.
        _configuration = State(initialValue: playlist.smartRules ?? SmartPlaylistConfiguration())
    }

    var body: some View {
        NavigationStack {
            Form {
                SmartPlaylistRulesForm(configuration: $configuration)
            }
            .navigationTitle("smart_edit_rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action_cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action_save") {
                        library.updateSmartRules(configuration, for: playlist.id)
                        dismiss()
                    }
                    .disabled(!configuration.isValid)
                }
            }
        }
    }
}

struct SmartPlaylistRulesForm: View {
    @Environment(MusicLibraryManager.self) private var library
    @Binding var configuration: SmartPlaylistConfiguration
    @State private var now = Date()

    private var matchingSongs: [Song] {
        configuration.songs(in: library.songs, favorites: Set(library.favoriteSongIDs), now: now)
    }

    var body: some View {
        Section {
            Picker("smart_match", selection: $configuration.matchMode) {
                ForEach(SmartPlaylistConfiguration.MatchMode.allCases, id: \.self) { mode in
                    Text(LocalizedStringKey(mode.labelKey)).tag(mode)
                }
            }
        } header: {
            Text("smart_rules")
        } footer: {
            Text("smart_rules_help")
        }

        ForEach($configuration.rules) { $rule in
            Section {
                SmartPlaylistRuleRow(rule: $rule)
                Button("smart_remove_rule", role: .destructive) {
                    configuration.rules.removeAll { $0.id == rule.id }
                }
                .disabled(configuration.rules.count == 1)
            }
        }

        Section {
            Button("smart_add_rule", systemImage: "plus") {
                configuration.rules.append(SmartPlaylistRule())
            }
        }

        Section("smart_order_limit") {
            Picker("smart_sort", selection: $configuration.sortOrder) {
                ForEach(SmartPlaylistConfiguration.SortOrder.allCases, id: \.self) { order in
                    Text(LocalizedStringKey(order.labelKey)).tag(order)
                }
            }
            if configuration.sortOrder == .random {
                Button("smart_reshuffle", systemImage: "shuffle") {
                    configuration.randomSeed = UUID().uuidString
                }
            }
            Picker("smart_limit", selection: $configuration.limit) {
                Text("smart_unlimited").tag(0)
                Text("25").tag(25)
                Text("50").tag(50)
                Text("100").tag(100)
            }
        }

        Section {
            if configuration.isValid {
                let preview = matchingSongs
                Text("smart_matches_count \(preview.count)")
                    .font(.headline)
                ForEach(Array(preview.prefix(5))) { song in
                    VStack(alignment: .leading) {
                        Text(song.title)
                        Text(song.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if preview.isEmpty {
                    Text("smart_empty_description").foregroundStyle(.secondary)
                }
            } else {
                Text("smart_invalid_rules").foregroundStyle(.secondary)
            }
        } header: {
            Text("smart_preview")
        } footer: {
            Text("smart_history_help")
        }
        .modifier(SmartPlaylistDateRefresh(now: $now))
    }
}

private struct SmartPlaylistRuleRow: View {
    @Binding var rule: SmartPlaylistRule

    var body: some View {
        Picker("smart_field", selection: $rule.field) {
            ForEach(SmartPlaylistRule.Field.allCases, id: \.self) { field in
                Text(LocalizedStringKey(field.labelKey)).tag(field)
            }
        }
        .onChange(of: rule.field) { _, field in
            if field.needsDays { rule.number = 30 }
            if field.needsCount { rule.number = 1 }
        }
        if rule.field.needsText {
            TextField("smart_contains", text: $rule.text)
                .autocorrectionDisabled()
        } else if rule.field == .favorite {
            Toggle("smart_is_favorite", isOn: $rule.favorite)
        } else if rule.field.needsDays {
            Stepper(value: $rule.number, in: 1...3650) {
                Text("smart_days_count \(rule.number)")
            }
        } else if rule.field.needsCount {
            Stepper(value: $rule.number, in: 0...100000) {
                Text("smart_plays_count \(rule.number)")
            }
        }
    }
}

/// Date rules also refresh when time passes or the app returns to the foreground.
struct SmartPlaylistDateRefresh: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var now: Date
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content
            .onAppear { now = Date() }
            .onReceive(timer) { now = $0 }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = Date() }
            }
    }
}
