import Foundation

struct FetchAudioResult {
    let downloadURL: URL
    let suggestedFileName: String?
}

protocol FetchAudioSource {
    func resolveAudio(
        for item: FetchItem,
        quality: FetchQuality
    ) async throws -> FetchAudioResult
}

enum FetchAudioSourceError: LocalizedError {
    case noSourceAvailable
    case invalidResponse
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .noSourceAvailable:
            return "Geen toegestane audiobron gevonden."
        case .invalidResponse:
            return "Ongeldige reactie van de audiobron."
        case .unsupportedFormat:
            return "Dit audioformaat wordt nog niet ondersteund."
        }
    }
}
