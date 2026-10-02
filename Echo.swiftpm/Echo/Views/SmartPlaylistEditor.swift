import SwiftUI
import PhotosUI

struct SmartPlaylistEditor: View {
    @Environment(MusicLibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let playlist: Playlist?
    @State private var name: String
    @State private var definition: SmartPlaylistDefinition
    @State private var preset: SmartPreset = .custom
    @State private var photo: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var now = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    init(playlist: Playlist? = nil) {
        self.playlist = playlist
        _name = State(initialValue: playlist?.name ?? "")
        _definition = State(initialValue: playlist?.smartDefinition ?? SmartPreset.mostPlayed.definition)
        _imageData = State(initialValue: playlist?.imageData)
    }
    private var matches: [Song] {
        SmartPlaylistEvaluator.songs(definition, from: library.songs, favorites: Set(library.favoriteSongIDs), listening: RecommendationManager.shared.smartSnapshot, now: now)
    }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && definition.rules.allSatisfy {
            $0.value.isFinite && $0.upper.isFinite && abs($0.value) <= 1_000_000 && abs($0.upper) <= 1_000_000 &&
            (!$0.field.text || $0.comparison == .missing || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photo, matching: .images) {
                        HStack {
                            if let imageData, let image = UIImage(data: imageData) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 16))
                            } else { Image(systemName: "sparkles").font(.title).frame(width: 64, height: 64).background(.thinMaterial, in: .rect(cornerRadius: 16)) }
                            Text("select_cover_image_accessibility")
                        }
                    }
                    TextField("playlist_name_placeholder", text: $name)
                    Picker("smart_presets", selection: $preset) {
                        ForEach(SmartPreset.allCases) { Text(LocalizedStringKey($0.key)).tag($0) }
                    }.onChange(of: preset) {
                        definition = preset.definition
                        if name.isEmpty { name = String(localized: String.LocalizationValue(preset.key), locale: locale) }
                    }
                }
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
                    if matches.isEmpty { Text("smart_empty").foregroundStyle(.secondary) }
                    ForEach(Array(matches.prefix(8))) { song in
                        Label { VStack(alignment: .leading) { Text(song.title); Text(song.artist).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "music.note") }
                    }
                } header: { Text("smart_matches \(matches.count)") } footer: { Text("smart_automatic_detail") }
            }.echoBackground().navigationTitle("smart_editor_title").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("action_cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("action_save", action: save).disabled(!valid) }
                }
                .onReceive(clock) { now = $0 }
                .onChange(of: photo) { Task { imageData = try? await photo?.loadTransferable(type: Data.self) } }
        }
    }
    private func save() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let playlist, let index = library.playlists.firstIndex(where: { $0.id == playlist.id }) {
            library.playlists[index].name = title
            library.playlists[index].imageData = imageData
            library.playlists[index].smartDefinition = definition
        } else {
            var created = library.createPlaylist(name: title, imageData: imageData)
            created.smartDefinition = definition
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
