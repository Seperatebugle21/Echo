import SwiftUI

struct SettingsView: View {
    
    @Environment(MusicLibraryManager.self) private var library

    @AppStorage("geniusAccessToken") private var geniusToken: String = ""
    @AppStorage("musixmatchApiKey") private var musixmatchApiKey: String = ""

    @AppStorage("selectedLanguage") private var selectedLanguage: String = "en"
    
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    
    @State private var showDeleteConfirmation = false
    @State private var showFirstDeleteAlert = false
    @State private var showFinalDeleteAlert = false
    @State private var showDeleteLyricsAlert = false

    @State private var apifySettings =
    ApifySettings.shared

    @State private var showApifyToken = false
    
    var body: some View {
        
        NavigationStack {
            
            Form {
                
                Section(LocalizedStringKey("settings_section_appearance")) {
                    
                    Picker(
                        LocalizedStringKey("settings_appearance_title"),
                        selection: $appearanceMode
                    ) {
                        
                        Text(LocalizedStringKey("appearance_system"))
                            .tag("system")
                        
                        Text(LocalizedStringKey("appearance_light"))
                            .tag("light")
                        
                        Text(LocalizedStringKey("appearance_dark"))
                            .tag("dark")
                    }

                    
                }
                
                Section(header: Text(LocalizedStringKey("settings_language_section"))) {
                    Picker(selection: $selectedLanguage) {
                        Text("English").tag("en")
                        Text("Nederlands").tag("nl")
                        Text("Français").tag("fr")
                        Text("Deutsch").tag("de")
                    } label: {
                        Label(
                            LocalizedStringKey("settings_language_label"),
                            systemImage: "globe"
                        )
                    }
                    .pickerStyle(.menu)
                }


                Section(
                    header: Text("settings.api.header"),
                    footer: Text("settings.genius.footer")
                ) {
                    SecureField("GENIUS API TOKEN", text: $geniusToken)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    SecureField("MUSIXMATCH API KEY", text: $musixmatchApiKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

              Section("Apify") {

    Picker(
        "Method",
        selection:
            $apifySettings.downloadMethod
    ) {

        ForEach(
            ApifyDownloadMethod.allCases
        ) { method in

            Text(method.title)
                .tag(method)
        }
    }

    HStack {

        if showApifyToken {

            TextField(
                "Apify API token",
                text:
                    $apifySettings.apiToken
            )
            .textInputAutocapitalization(
                .never
            )
            .autocorrectionDisabled()

        } else {

            SecureField(
                "Apify API token",
                text:
                    $apifySettings.apiToken
            )
            .textInputAutocapitalization(
                .never
            )
            .autocorrectionDisabled()
        }

        Button {

            showApifyToken.toggle()

        } label: {

            Image(
                systemName:
                    showApifyToken
                    ? "eye.slash"
                    : "eye"
            )
        }
        .buttonStyle(.plain)
    }

    Button("Save API Token") {
    apifySettings.saveToken()
}

    if apifySettings.isConfigured {

        Label(
            "Apify is configured",
            systemImage:
                "checkmark.circle.fill"
        )
        .foregroundStyle(.green)

    } else {

        Label(
            "No Apify API token configured",
            systemImage:
                "exclamationmark.triangle"
        )
        .foregroundStyle(.secondary)
    }

    Button(
        "Remove API Token",
        role: .destructive
    ) {

        apifySettings.removeToken()
    }
}

                
                Section(LocalizedStringKey("settings_section_library")) {
                    
                    HStack {
                        
                        Text(LocalizedStringKey("tab_songs"))
                        
                        Spacer()
                        
                        Text("\(library.songs.count)")
                            .foregroundStyle(.secondary)
                    }
                    
                    
                    HStack {
                        
                        Text(LocalizedStringKey("tab_playlists"))
                        
                        Spacer()
                        
                        Text("\(library.playlists.count)")
                            .foregroundStyle(.secondary)
                    }
                    
                    
                    Button {
                        
                        // Later: opnieuw scannen van bestanden
                        
                    } label: {
                        
                        Label(
                            LocalizedStringKey("settings_refresh_library"),
                            systemImage: "arrow.clockwise"
                        )
                    }
                }
                
                
                Section(LocalizedStringKey("settings_section_danger")) {
                    
                    Button {
                        
                        library.clearCache()
                        
                    } label: {
                        
                        Label(
                            LocalizedStringKey("settings_clear_cache"),
                            systemImage: "arrow.clockwise"
                        )
                    }
                    
                    Button(role: .destructive) {
                        
                        showFirstDeleteAlert = true
                        
                    } label: {
                        
                        Label(
                            LocalizedStringKey("settings_delete_all_music"),
                            systemImage: "trash"
                        )
                    }
                }
                
                
                Section(LocalizedStringKey("settings_section_about")) {
                    
                    HStack {
                        
                        Text(LocalizedStringKey("settings_version"))
                        
                        Spacer()
                        
                        Text("3.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(LocalizedStringKey("settings_made_with"))
                        .foregroundStyle(.secondary)
                }
            }
            
            .navigationTitle(LocalizedStringKey("tab_settings"))
            
            .alert(
                LocalizedStringKey("alert_delete_lyrics_title"),
                isPresented: $showDeleteLyricsAlert
            ) {
                
                Button(LocalizedStringKey("action_cancel"), role: .cancel) {}
                
                Button(LocalizedStringKey("action_delete"), role: .destructive) {
                    MusicLibraryManager.shared.removeAllLyrics()
                }
                
            } message: {
                Text(LocalizedStringKey("alert_delete_lyrics_message"))
            }
            
            .alert(
                LocalizedStringKey("alert_delete_all_music_title"),
                isPresented: $showFirstDeleteAlert
            ) {
                
                Button(
                    LocalizedStringKey("action_cancel"),
                    role: .cancel
                ) {}
                
                Button(
                    LocalizedStringKey("action_continue"),
                    role: .destructive
                ) {
                    showFinalDeleteAlert = true
                }
                
            } message: {
                
                Text(LocalizedStringKey("alert_delete_all_music_message"))
            }
            
            .alert(
                LocalizedStringKey("alert_cannot_be_undone_title"),
                isPresented: $showFinalDeleteAlert
            ) {
                
                Button(
                    LocalizedStringKey("action_cancel"),
                    role: .cancel
                ) {}
                
                Button(
                    LocalizedStringKey("action_delete_everything"),
                    role: .destructive
                ) {
                    library.songs.removeAll()
                }
                
            } message: {
                
                Text(LocalizedStringKey("alert_cannot_be_undone_message"))
            }
            
            .alert(
                LocalizedStringKey("alert_delete_all_music_title"),
                isPresented: $showDeleteConfirmation
            ) {
                
                Button(
                    LocalizedStringKey("action_cancel"),
                    role: .cancel
                ) {}
                
                Button(
                    LocalizedStringKey("action_delete"),
                    role: .destructive
                ) {
                    library.deleteAllSongs()
                }
                
            } message: {
                
                Text(LocalizedStringKey("alert_delete_confirmation_message"))
            }
        }
    }
}


#Preview {
    
    SettingsView()
        .environment(MusicLibraryManager())
}
