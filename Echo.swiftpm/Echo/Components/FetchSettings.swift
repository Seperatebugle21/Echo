import Foundation

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

    var quality: FetchQuality = .kbps320

    var embedArtwork = true
    var embedMetadata = true

    private init() {}
}
