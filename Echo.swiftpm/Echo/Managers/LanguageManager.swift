import SwiftUI

@Observable
class LanguageManager {
    static let shared = LanguageManager()
    
    // Slaat de taalcode op (bijv. "nl" of "en")
    var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "app_language")
        }
    }
    
    init() {
        // Laad de opgeslagen taal, of gebruik 'nl' als standaard
        self.currentLanguage = UserDefaults.standard.string(forKey: "app_language") ?? "nl"
    }
}
