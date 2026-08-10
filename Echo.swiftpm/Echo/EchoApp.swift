import SwiftUI

@main
struct EchoApp: App {
    
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    
    @State private var languageManager = LanguageManager.shared
    @State private var library = MusicLibraryManager()
    @State private var audioPlayer = AudioPlayerManager()
    
    var body: some Scene {
        
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(audioPlayer)
                .environment(\.locale, Locale(identifier: languageManager.currentLanguage))
                .environment(languageManager)
                .preferredColorScheme(colorScheme)
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
