import SwiftUI

@main
struct EchoApp: App {

    @AppStorage("selectedLanguage") private var selectedLanguage: String = "en"
    
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    
   
    @State private var library = MusicLibraryManager()
    @State private var audioPlayer = AudioPlayerManager()
    
    var body: some Scene {
        
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: selectedLanguage))
                .environment(library)
                .environment(audioPlayer)
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
