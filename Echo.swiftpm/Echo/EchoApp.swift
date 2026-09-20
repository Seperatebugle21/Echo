import SwiftUI

@main
struct EchoApp: App {

    @AppStorage("selectedLanguage") private var selectedLanguage: String = "en"
    
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    @Environment(\.scenePhase) private var scenePhase
    
   
    @State private var library = MusicLibraryManager.shared
    @State private var audioPlayer = AudioPlayerManager.shared
    
    var body: some Scene {
        
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: selectedLanguage))
                .id(selectedLanguage)
                .environment(library)
                .environment(audioPlayer)
                .preferredColorScheme(colorScheme)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                library.syncDocumentsFolder()
            }
        }
    }
    
    
    var colorScheme: ColorScheme? {
        
        switch appearanceMode {
            
        case "dark":
            return .dark
            
        case "light":
            return .light
            
        default:
            return nil
        }
    }
}
