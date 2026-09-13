import SwiftUI

struct SettingsView: View {
    @Environment(MusicLibraryManager.self) private var library
    @AppStorage("selectedLanguage") private var selectedLanguage = "en"
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var apifySettings = ApifySettings.shared
    @State private var showFirstDeleteAlert = false
    @State private var showFinalDeleteAlert = false
    @State private var showDeleteLyricsAlert = false
    @State private var showClearCacheAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 18) {
                        Image(systemName: "waveform")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 68, height: 68)
                            .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 22))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("settingsview_intro_title").font(.title2.bold())
                            Text("settingsview_intro_subtitle").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }
                personalization
                connections
                Section("settings_section_library") {
                    HStack {
                        SettingsRow(title: "tab_songs", symbol: "music.note", color: .pink)
                        Spacer()
                        Text(library.songs.count, format: .number).foregroundStyle(.secondary).monospacedDigit()
                    }
                    HStack {
                        SettingsRow(title: "tab_playlists", symbol: "music.note.list", color: .purple)
                        Spacer()
                        Text(library.playlists.count, format: .number).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Section("settings_section_about") {
                    HStack {
                        SettingsRow(title: "settings_version", symbol: "info.circle.fill", color: .gray)
                        Spacer()
                        Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink { DeveloperView() } label: {
                        SettingsRow(title: "settingsview_developer_settings", symbol: "hammer.fill", color: .gray)
                    }
                    Text("settings_made_with").font(.footnote).foregroundStyle(.secondary)
                }
                dangerZone
            }
            .formStyle(.grouped)
            .navigationTitle("tab_settings")
            .navigationBarTitleDisplayMode(.large)
            .alert("alert_cannot_be_undone_title", isPresented: $showFinalDeleteAlert) {
                Button("action_cancel", role: .cancel) {}
                Button("action_delete_everything", role: .destructive) { library.deleteAllSongs() }
            } message: { Text("alert_cannot_be_undone_message") }
            .alert("settingsview_clear_cache_title", isPresented: $showClearCacheAlert) {
                Button("action_cancel", role: .cancel) {}
                Button("settings_clear_cache", role: .destructive) { library.clearCache() }
            } message: { Text("settingsview_clear_cache_message") }
            .alert(
                LocalizedStringKey(
                    "alert_delete_lyrics_title"
                ),
                isPresented:
                    $showDeleteLyricsAlert
            ) {

                Button(
                    LocalizedStringKey(
                        "action_cancel"
                    ),
                    role: .cancel
                ) {}

                Button(
                    LocalizedStringKey(
                        "action_delete"
                    ),
                    role: .destructive
                ) {
                    library.removeAllLyrics()
                }

            } message: {

                Text(
                    LocalizedStringKey(
                        "alert_delete_lyrics_message"
                    )
                )
            }

            .alert(
                LocalizedStringKey(
                    "alert_delete_all_music_title"
                ),
                isPresented:
                    $showFirstDeleteAlert
            ) {

                Button(
                    LocalizedStringKey(
                        "action_cancel"
                    ),
                    role: .cancel
                ) {}

                Button(
                    LocalizedStringKey(
                        "action_continue"
                    ),
                    role: .destructive
                ) {
                    showFinalDeleteAlert = true
                }

            } message: {

                Text(
                    LocalizedStringKey(
                        "alert_delete_all_music_message"
                    )
                )
            }


        }
    }

    private var personalization: some View {
        Section("settingsview_personalization") {
            NavigationLink { EqualizerView() } label: {
                SettingsRow(title: "settingsview_equalizer", subtitle: "settingsview_equalizer_detail", symbol: "slider.vertical.3", color: .pink)
            }
            NavigationLink { TabBarSettingsView() } label: {
                SettingsRow(title: "settingsview_tab_bar", subtitle: "settingsview_tab_bar_detail", symbol: "rectangle.bottomthird.inset.filled", color: .purple)
            }
            Picker(selection: $appearanceMode) {
                Text("appearance_system").tag("system")
                Text("appearance_light").tag("light")
                Text("appearance_dark").tag("dark")
            } label: {
                SettingsRow(title: "settings_appearance_title", symbol: "circle.lefthalf.filled", color: .indigo)
            }
            .pickerStyle(.menu)
            Picker(selection: $selectedLanguage) {
                Text("settingsview_language_english").tag("en")
                Text("settingsview_language_dutch").tag("nl")
                Text("settingsview_language_french").tag("fr")
                Text("settingsview_language_german").tag("de")
            } label: {
                SettingsRow(title: "settings_language_label", symbol: "globe", color: .blue)
            }
            .pickerStyle(.menu)
        }
    }

    private var connections: some View {
        Section("settingsview_connections") {
            NavigationLink { ApifyAccountsView() } label: {
                HStack {
                    SettingsRow(title: "settingsview_apify_accounts", symbol: "person.2.fill", color: .orange)
                    Spacer(minLength: 8)
                    Group {
                        if let account = apifySettings.activeAccount { Text(verbatim: account.name) }
                        else { Text("settingsview_none") }
                    }
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            NavigationLink { SettingsLyricsServicesView() } label: {
                SettingsRow(title: "settingsview_lyrics_services", subtitle: "settingsview_lyrics_services_detail", symbol: "text.quote", color: .teal)
            }
        }
    }

    private var dangerZone: some View {
        Section {
            Button(role: .destructive) { showClearCacheAlert = true } label: {
                SettingsRow(title: "settings_clear_cache", symbol: "arrow.clockwise", color: .red)
            }
            Button(role: .destructive) { showDeleteLyricsAlert = true } label: {
                SettingsRow(title: "settingsview_delete_lyrics", symbol: "text.badge.minus", color: .red)
            }
            Button(role: .destructive) { showFirstDeleteAlert = true } label: {
                SettingsRow(title: "settings_delete_all_music", symbol: "trash.fill", color: .red)
            }
        } header: {
            Label("settings_section_danger", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        } footer: { Text("settingsview_danger_detail") }
    }
}

private struct SettingsRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    let symbol: String
    let color: Color
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.vertical, 5)
        }
    }
}

private struct SettingsLyricsServicesView: View {
    @AppStorage("geniusAccessToken") private var geniusToken = ""
    @AppStorage("musixmatchApiKey") private var musixmatchApiKey = ""
    var body: some View {
        Form {
            Section {
                SecureField("settingsview_genius_token", text: $geniusToken)
                SecureField("settingsview_musixmatch_key", text: $musixmatchApiKey)
            } header: { Text("settings.api.header") }
              footer: { Text("settings.genius.footer") }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .navigationTitle("settingsview_lyrics_services")
        .navigationBarTitleDisplayMode(.inline)
    }
}
