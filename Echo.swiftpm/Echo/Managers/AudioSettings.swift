import Foundation

enum AudioSettings {
    static let monoKey = "monoAudioEnabled"
    static let didChange = Notification.Name("EchoAudioSettingsDidChange")

    static var isMonoEnabled: Bool {
        UserDefaults.standard.bool(forKey: monoKey)
    }
}
