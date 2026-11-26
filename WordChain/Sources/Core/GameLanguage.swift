import Foundation

/// The two languages Schakel is played in. The language picks both the
/// interface text and the word list.
enum GameLanguage: String, CaseIterable, Codable, Identifiable {
    case dutch = "nl"
    case english = "en"

    var id: String { rawValue }

    /// Name of the language in that language.
    var nativeName: String {
        switch self {
        case .dutch: return "Nederlands"
        case .english: return "English"
        }
    }

    var flag: String {
        switch self {
        case .dutch: return "🇳🇱"
        case .english: return "🇬🇧"
        }
    }

    /// File name (without extension) of the bundled link list.
    var resourceName: String { "pairs_\(rawValue)" }

    /// The language that matches the device, falling back to English.
    static var deviceDefault: GameLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("nl") ? .dutch : .english
    }
}
