import Foundation

@MainActor
@Observable
final class SpotifyManager {

    static let shared = SpotifyManager()

    private(set) var isConnected = false

    private init() {}

    func connect() {
        // Spotify OAuth komt hier.
    }

    func disconnect() {
        isConnected = false
    }
}
