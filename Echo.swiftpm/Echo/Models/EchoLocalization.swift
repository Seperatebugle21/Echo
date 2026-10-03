import Foundation

enum EchoLocalization {
    static func string(_ key: String, language: String? = nil, fallback: String? = nil, bundle: Bundle = .main) -> String {
        let selected = language ?? UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en"
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
