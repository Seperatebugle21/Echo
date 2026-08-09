import SwiftUI

struct SettingsView: View {
    
    @Environment(MusicLibraryManager.self) private var library
    
@AppStorage("appearanceMode") private var appearanceMode = "system"
 
    
    @State private var showDeleteConfirmation = false
    @State private var showFirstDeleteAlert = false
    @State private var showFinalDeleteAlert = false
    @State private var showDeleteLyricsAlert = false
    
    
    var body: some View {
        
        NavigationStack {
            
            Form {
                
                Section("Weergave") {
                    
                    Picker(
                        "Weergave",
                        selection: $appearanceMode
                    ) {
                        
                        Text("Systeem")
                            .tag("system")
                        
                        Text("Licht")
                            .tag("light")
                        
                        Text("Donker")
                            .tag("dark")
                    }
                    
                    
                }
                
                
                Section("Bibliotheek") {
                    
                    HStack {
                        
                        Text("Nummers")
                        
                        Spacer()
                        
                        Text("\(library.songs.count)")
                            .foregroundStyle(.secondary)
                    }
                    
                    
                    HStack {
                        
                        Text("Playlists")
                        
                        Spacer()
                        
                        Text("\(library.playlists.count)")
                            .foregroundStyle(.secondary)
                    }
                    
                    
                    Button {
                        
                        // Later: opnieuw scannen van bestanden
                        
                    } label: {
                        
                        Label(
                            "Bibliotheek vernieuwen",
                            systemImage: "arrow.clockwise"
                        )
                    }
                }
                
                
                Section("Gevaarzone") {
                    
                    Button {
                        
                        library.clearCache()
                        
                        
                        
                    } label: {
                        
                        
                        
                        Label(
                            
                            "Cache wissen",
                            
                            systemImage: "arrow.clockwise"
                            
                        )
                        
                    }
                    
             //       Button(role: .destructive) {
                        
                //        showDeleteLyricsAlert = true
                        
        //            } label: {
                        
            //            Label(
                            
          //                  "Verwijder opgeslagen lyrics",
                            
          //                  systemImage: "trash"
                            
         //               )
                        
       //             }
                    
                    
                    Button(role: .destructive) {
                        
                        showFirstDeleteAlert = true
                        
                    } label: {
                        
                        Label(
                            "Verwijder alle muziek",
                            systemImage: "trash"
                        )
                    }
                }
                
                
                Section("Over Echo") {
                    
                    HStack {
                        
                        Text("Versie")
                        
                        Spacer()
                        
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("Gemaakt met SwiftUI")
                        .foregroundStyle(.secondary)
                }
            }
            
            .navigationTitle("Instellingen")
            
            .alert(
                "Opgeslagen lyrics verwijderen?",
                isPresented: $showDeleteLyricsAlert
            ) {
                
                Button("Annuleren", role: .cancel) {}
                
                Button("Verwijderen", role: .destructive) {
                    MusicLibraryManager.shared.removeAllLyrics()
                }
                
            } message: {
                Text("Alle opgeslagen lyrics worden verwijderd. De nummers zelf blijven behouden.")
            }
            
            .alert(
                "Alle muziek verwijderen?",
                isPresented: $showFirstDeleteAlert
            ) {
                
                Button(
                    "Annuleer",
                    role: .cancel
                ) {}
                
                
                Button(
                    "Doorgaan",
                    role: .destructive
                ) {
                    
                    showFinalDeleteAlert = true
                    
                }
                
            } message: {
                
                Text(
                    "Alle geïmporteerde nummers worden verwijderd."
                )
            }
            
            
            
            .alert(
                "Dit kan niet ongedaan worden",
                isPresented: $showFinalDeleteAlert
            ) {
                
                Button(
                    "Annuleer",
                    role: .cancel
                ) {}
                
                
                Button(
                    "Verwijder alles",
                    role: .destructive
                ) {
                    
                    library.songs.removeAll()
                    
                }
                
            } message: {
                
                Text(
                    "Je muziekbestanden en bibliotheekgegevens worden definitief verwijderd."
                )
            }
            
            .alert(
                "Alle muziek verwijderen?",
                isPresented: $showDeleteConfirmation
            ) {
                
                Button(
                    "Annuleer",
                    role: .cancel
                ) {}
                
                
                Button(
                    "Verwijder",
                    role: .destructive
                ) {
                    
                  library.deleteAllSongs()
                }
                
            } message: {
                
                Text(
                    "Dit verwijdert alle geïmporteerde nummers uit Echo."
                )
            }
        }
    }
}


#Preview {
    
    SettingsView()
        .environment(MusicLibraryManager())
}
