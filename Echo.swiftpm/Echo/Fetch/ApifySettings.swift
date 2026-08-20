import Foundation
import Observation

@MainActor
@Observable
final class ApifySettings {

    static let shared = ApifySettings()

    private let tokenKey = "echo.apify.apiToken"

    var apiToken: String = ""

    private init() {
        apiToken =
            KeychainHelper.read(tokenKey) ?? ""
    }

    var isConfigured: Bool {
        !apiToken
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
    }

    func save() {

        let cleaned =
            apiToken.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        apiToken = cleaned

        if cleaned.isEmpty {
            KeychainHelper.delete(tokenKey)
        } else {
            KeychainHelper.save(
                cleaned,
                for: tokenKey
            )
        }
    }

    func removeToken() {
        apiToken = ""
        KeychainHelper.delete(tokenKey)
    }
}
