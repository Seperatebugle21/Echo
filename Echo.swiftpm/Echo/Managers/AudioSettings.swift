import Foundation

enum AudioSettings {
    static let monoKey = "monoAudioEnabled"
    static let didChange = Notification.Name("EchoAudioSettingsDidChange")

    static var isMonoEnabled: Bool {
        UserDefaults.standard.bool(forKey: monoKey)
    }
    static let transitionKey = "audio.transition.v1"
    static let crossfadeKey = "audio.crossfadeSeconds"
    static var transition: AudioTransitionMode {
        AudioTransitionMode(rawValue: UserDefaults.standard.string(forKey: transitionKey) ?? "direct") ?? .direct
    }
    static var crossfadeSeconds: Double {
        let value = UserDefaults.standard.object(forKey: crossfadeKey) as? Double ?? 5
        return value.isFinite ? min(12, max(1, value)) : 5
    }
}
