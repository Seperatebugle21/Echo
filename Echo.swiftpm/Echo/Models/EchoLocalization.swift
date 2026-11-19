import Foundation

/// Every language Echo ships. The raw value is the `.lproj` name in the string catalogs.
enum EchoLanguage: String, CaseIterable, Identifiable {
    case en, nl, fr, de, es, it, pt, pl, tr, ja, ko
    case zhHans = "zh-Hans"

    static let preferenceKey = "selectedLanguage"

    var id: String { rawValue }

    /// The language's own name, so people can find it whatever language is selected.
    var nativeName: String {
        switch self {
        case .en: "English"
        case .nl: "Nederlands"
        case .fr: "Français"
        case .de: "Deutsch"
        case .es: "Español"
        case .it: "Italiano"
        case .pt: "Português"
        case .pl: "Polski"
        case .tr: "Türkçe"
        case .ja: "日本語"
        case .ko: "한국어"
        case .zhHans: "简体中文"
        }
    }

    /// BCP 47 identifier for speech recognition and synthesis, which need a region.
    var speechIdentifier: String {
        switch self {
        case .en: "en-US"
        case .nl: "nl-NL"
        case .fr: "fr-FR"
        case .de: "de-DE"
        case .es: "es-ES"
        case .it: "it-IT"
        case .pt: "pt-PT"
        case .pl: "pl-PL"
        case .tr: "tr-TR"
        case .ja: "ja-JP"
        case .ko: "ko-KR"
        case .zhHans: "zh-CN"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    /// Maps a stored or system identifier such as "pt-BR", "zh-Hans-CN" or "de_AT" to a shipped language.
    init?(identifier: String) {
        if let exact = EchoLanguage(rawValue: identifier) { self = exact; return }
        let parts = Locale(identifier: identifier).language
        guard let code = parts.languageCode?.identifier else { return nil }
        if code == "zh" {
            // Only Simplified Chinese ships; Traditional scripts fall back to English.
            let script = parts.script?.identifier
            let region = parts.region?.identifier
            guard script == "Hans" || (script == nil && ["CN", "SG", nil].contains(region)) else { return nil }
            self = .zhHans
            return
        }
        guard let match = EchoLanguage(rawValue: code) else { return nil }
        self = match
    }

    /// The first of the person's iOS languages that Echo ships, else English.
    static func systemDefault(preferred: [String] = Locale.preferredLanguages) -> EchoLanguage {
        preferred.lazy.compactMap(EchoLanguage.init(identifier:)).first ?? .en
    }

    /// The language chosen in Settings (or the system default when nothing was chosen yet).
    static var current: EchoLanguage {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(EchoLanguage.init(identifier:)) ?? systemDefault()
    }

    /// Makes `@AppStorage("selectedLanguage")` and direct reads agree before the user picks a language.
    static func registerDefault(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [preferenceKey: systemDefault().rawValue])
    }
}

enum EchoLocalization {
    static func string(_ key: String, language: String? = nil, fallback: String? = nil, bundle: Bundle = .main) -> String {
        let selected = language ?? EchoLanguage.current.rawValue
        #if SWIFT_PACKAGE
        let resources = Bundle.module
        #else
        let resources = bundle
        #endif
        let path = resources.path(forResource: selected, ofType: "lproj") ?? resources.path(forResource: "en", ofType: "lproj")
        let localized = path.flatMap(Bundle.init(path:)) ?? resources
        return localized.localizedString(forKey: key, value: fallback, table: "Localizable")
    }
}
