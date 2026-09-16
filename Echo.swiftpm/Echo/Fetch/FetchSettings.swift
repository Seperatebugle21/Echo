import Foundation
import Observation

enum FetchQuality: Int, CaseIterable, Identifiable {
    case kbps128 = 128
    case kbps192 = 192
    case kbps320 = 320

    var id: Int {
        rawValue
    }

    var title: String {
        "\(rawValue) kbps"
    }
}

@Observable
final class FetchSettings {

    static let shared = FetchSettings()

    private static let qualityKey = "fetchAudioQuality"
    @ObservationIgnored private let defaults: UserDefaults

    var quality: FetchQuality {
        didSet { defaults.set(quality.rawValue, forKey: Self.qualityKey) }
    }

    var embedArtwork = true
    var embedMetadata = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        quality = FetchQuality(rawValue: defaults.integer(forKey: Self.qualityKey)) ?? .kbps320
    }
}
