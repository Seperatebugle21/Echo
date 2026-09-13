import Foundation
import Observation

enum EqualizerBand: Int, CaseIterable, Identifiable {
    case bass, lowMid, mid, upperMid, presence, treble
    var id: Int { rawValue }
    var frequency: Float { [60, 150, 400, 1_000, 2_400, 15_000][rawValue] }
}

enum EqualizerPreset: String, CaseIterable, Codable, Identifiable {
    case flat, bassBoost, bassReducer, trebleBoost, vocal, acoustic, pop, rock, electronic, custom
    var id: String { rawValue }
    // Echo presets inspired by common listening profiles, not Spotify's proprietary curves.
    var gains: [Float] {
        switch self {
        case .flat, .custom: [0, 0, 0, 0, 0, 0]
        case .bassBoost: [6, 4, 2, 0, 0, 0]
        case .bassReducer: [-6, -4, -2, 0, 0, 0]
        case .trebleBoost: [0, 0, 0, 1, 4, 6]
        case .vocal: [-3, -2, 1, 4, 3, -1]
        case .acoustic: [3, 2, 1, 2, 3, 3]
        case .pop: [-1, 2, 4, 3, 1, -1]
        case .rock: [4, 3, -2, -1, 3, 4]
        case .electronic: [5, 3, 0, -2, 2, 4]
        }
    }
}

struct EqualizerConfiguration: Codable {
    var enabled = false
    var gains: [Float] = Array(repeating: 0, count: 6)
    var preset: EqualizerPreset = .flat

    static func decode(_ data: Data?) -> Self {
        guard let data, var value = try? JSONDecoder().decode(Self.self, from: data),
              value.gains.count == EqualizerBand.allCases.count,
              value.gains.allSatisfy(\.isFinite) else { return Self() }
        value.gains = value.gains.map { min(12, max(-12, $0)) }
        if value.preset != .custom, value.gains != value.preset.gains { value.preset = .custom }
        return value
    }
}

@Observable
final class EqualizerSettings {
    static let shared = EqualizerSettings()
    static let storageKey = "equalizerConfiguration.v1"
    static let didChange = Notification.Name("EchoEqualizerSettingsDidChange")
    private(set) var configuration: EqualizerConfiguration

    private init() {
        configuration = .decode(UserDefaults.standard.data(forKey: Self.storageKey))
    }

    func setEnabled(_ enabled: Bool) {
        configuration.enabled = enabled
        save()
    }

    func setGain(_ gain: Float, for band: EqualizerBand) {
        guard gain.isFinite else { return }
        configuration.gains[band.rawValue] = min(12, max(-12, gain))
        configuration.preset = .custom
        save()
    }

    func select(_ preset: EqualizerPreset) {
        guard preset != .custom else { return }
        configuration.preset = preset
        configuration.gains = preset.gains
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
