import SwiftUI
import PhotosUI

struct SmartPlaylistEditor: View {
    @Environment(MusicLibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let playlist: Playlist?
    @State private var smartMode: Bool
    @State private var automaticNameKey: String?
    @State private var builtinCoverID: String?
    @State private var name: String
    @State private var definition: SmartPlaylistDefinition
    @State private var preset: SmartPreset = .custom
    @State private var imageData: Data?
    @State private var now = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    init(playlist: Playlist? = nil, startSmart: Bool = true) {
        self.playlist = playlist
        _smartMode = State(initialValue: playlist?.smartDefinition != nil || (playlist == nil && startSmart))
        _automaticNameKey = State(initialValue: playlist?.automaticNameKey ?? (playlist == nil && startSmart ? SmartPreset.mostPlayed.key : nil))
        _builtinCoverID = State(initialValue: playlist?.builtinCoverID)
        _preset = State(initialValue: playlist == nil ? .mostPlayed : SmartPreset.allCases.first { $0.key == playlist?.automaticNameKey } ?? .custom)
        _name = State(initialValue: playlist?.name ?? "")
        _definition = State(initialValue: playlist?.smartDefinition ?? SmartPreset.mostPlayed.definition)
        _imageData = State(initialValue: playlist?.imageData)
    }
    private var matches: [Song] {
        let overrides = playlist.flatMap { original in library.playlists.first { $0.id == original.id }?.smartOverrides } ?? [:]
        return SmartPlaylistEvaluator.songs(definition, from: library.songs, favorites: Set(library.favoriteSongIDs), listening: RecommendationManager.shared.smartSnapshot, now: now, overrides: overrides)
    }
    private var effectiveName: String {
        automaticNameKey.map { EchoLocalization.string($0, fallback: name) } ?? name
    }
    private var nameBinding: Binding<String> {
        Binding(get: { effectiveName }, set: { value in
            name = value
            automaticNameKey = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && smartMode ? preset.key : nil
        })
    }
    private var valid: Bool {
        !effectiveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!smartMode || definition.rules.allSatisfy {
            $0.value.isFinite && $0.upper.isFinite && abs($0.value) <= 1_000_000 && abs($0.upper) <= 1_000_000 &&
            (!$0.field.text || $0.comparison == .missing || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        })
    }
    var body: some View {
        let result = smartMode ? matches : []
        NavigationStack {
            Form {
                Section {
                    if playlist == nil {
                        Picker("playlist_kind", selection: $smartMode) {
                            Text("playlist_kind_regular").tag(false)
                            Text("playlist_kind_smart").tag(true)
                        }.pickerStyle(.segmented).onChange(of: smartMode) {
                            if smartMode && name.isEmpty && automaticNameKey == nil { automaticNameKey = preset.key }
                        }
                    }
                    PlaylistCoverSelector(imageData: $imageData, builtinCoverID: $builtinCoverID)
                    TextField("playlist_name_placeholder", text: nameBinding)
                    if smartMode {
                    Picker("smart_presets", selection: $preset) {
                        ForEach(SmartPreset.allCases) { Text(LocalizedStringKey($0.key)).tag($0) }
                    }.onChange(of: preset) {
                        definition = preset.definition
                        if automaticNameKey != nil || name.isEmpty { automaticNameKey = preset.key }
                    }
                    }
                }
                if smartMode {
                Section("smart_rules") {
                    Picker("smart_match", selection: $definition.matchAll) {
                        Text("smart_all").tag(true); Text("smart_any").tag(false)
                    }.pickerStyle(.segmented)
                    ForEach($definition.rules) { $rule in
                        SmartRuleEditor(rule: $rule)
                    }.onDelete { definition.rules.remove(atOffsets: $0) }
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { definition.rules.append(SmartRule()) }
                    } label: { Label("smart_add_rule", systemImage: "plus.circle") }
                }
                Section("smart_order") {
                    Picker("smart_order", selection: $definition.sort) {
                        ForEach(SmartSort.allCases) { Text(LocalizedStringKey($0.key)).tag($0) }
                    }
                    if [.mostPlayed, .leastPlayed].contains(definition.sort) {
                        SmartPeriodPicker(days: $definition.periodDays)
                    }
                    Toggle("smart_limit", isOn: Binding(get: { definition.limit != nil }, set: { definition.limit = $0 ? 50 : nil }))
                    if definition.limit != nil {
                        Stepper(value: Binding(get: { definition.limit ?? 50 }, set: { definition.limit = $0 }), in: 1...1000) { Text("smart_limit_count \(definition.limit ?? 50)") }
                    }
                }
                Section {
                    if result.isEmpty { Text("smart_empty").foregroundStyle(.secondary) }
                    ForEach(Array(result.prefix(8))) { song in
                        Label { VStack(alignment: .leading) { Text(song.title); Text(song.artist).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "music.note") }
                    }
                } header: { Text("smart_matches \(result.count)") } footer: { Text("smart_automatic_detail") }
                }
            }.echoBackground().navigationTitle(LocalizedStringKey(smartMode ? "smart_editor_title" : "create_playlist_navigation_title")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("action_cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("action_save", action: save).disabled(!valid) }
                }
                .onReceive(clock) { now = $0 }

        }
    }
    private func save() {
        let title = effectiveName
        if let playlist, let index = library.playlists.firstIndex(where: { $0.id == playlist.id }) {
            var updated = library.playlists[index]
            updated.name = title; updated.imageData = imageData; updated.builtinCoverID = builtinCoverID
            updated.automaticNameKey = smartMode ? automaticNameKey : nil
            updated.smartDefinition = smartMode ? definition : nil
            library.playlists[index] = updated
        } else {
            var created = library.createPlaylist(name: title, imageData: imageData)
            created.smartDefinition = smartMode ? definition : nil
            created.builtinCoverID = builtinCoverID
            created.automaticNameKey = smartMode ? automaticNameKey : nil
            if let index = library.playlists.firstIndex(where: { $0.id == created.id }) { library.playlists[index] = created }
        }
        dismiss()
    }
}

private struct SmartPeriodPicker: View {
    @Binding var days: Int?
    var body: some View {
        Picker("smart_period", selection: $days) {
            Text("smart_all_time").tag(Int?.none)
            ForEach([7, 30, 90, 365], id: \.self) { Text("smart_days \($0)").tag(Optional($0)) }
        }
    }
}
private struct SmartRuleEditor: View {
    @Binding var rule: SmartRule
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("smart_field", selection: $rule.field) {
                ForEach(SmartField.allCases) { Text(LocalizedStringKey($0.key)).tag($0) }
            }.onChange(of: rule.field) {
                rule.comparison = rule.comparisons.first ?? .equals
                rule.value = rule.field.date ? 30 : rule.field == .releaseYear ? 2000 : 1
                rule.upper = rule.field == .releaseYear ? 2009 : 10
            }
            if rule.field != .favorite {
                Picker("smart_condition", selection: $rule.comparison) {
                    ForEach(rule.comparisons) { Text(LocalizedStringKey($0.key)).tag($0) }
                }
            }
            if rule.comparison != .missing {
                if rule.field.text { TextField("smart_value", text: $rule.text) }
                else if rule.field == .favorite {
                    Toggle("favorites_title", isOn: Binding(get: { rule.value != 0 }, set: { rule.value = $0 ? 1 : 0 }))
                } else {
                    HStack {
                        TextField("smart_value", value: $rule.value, format: .number.precision(.fractionLength(0))).keyboardType(.numberPad)
                        if rule.comparison == .range {
                            TextField("smart_upper", value: $rule.upper, format: .number.precision(.fractionLength(0))).keyboardType(.numberPad)
                        }
                    }
                    if rule.field == .playCount { SmartPeriodPicker(days: $rule.periodDays) }
                }
            }
        }.padding(.vertical, 6)
    }
}
