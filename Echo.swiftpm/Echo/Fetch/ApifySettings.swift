import Foundation
import Observation

enum ApifyDownloadMethod: String, CaseIterable, Identifiable {
    case youtube
    case spotify

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .youtube:
            return "YouTube"

        case .spotify:
            return "Spotify"
        }
    }
}

@MainActor
@Observable
final class ApifySettings {

    static let shared = ApifySettings()

    private let tokenKey =
        "echo.apify.apiToken"

    private let methodKey =
        "echo.apify.downloadMethod"

    var apiToken: String = ""

    var downloadMethod:
        ApifyDownloadMethod = .youtube

    private init() {

        apiToken =
            KeychainHelper.read(
                tokenKey
            ) ?? ""

        if
            let savedMethod =
                UserDefaults.standard.string(
                    forKey: methodKey
                ),
            let method =
                ApifyDownloadMethod(
                    rawValue: savedMethod
                )
        {
            downloadMethod = method
        }
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

            KeychainHelper.delete(
                tokenKey
            )

        } else {

            KeychainHelper.save(
                cleaned,
                for: tokenKey
            )
        }

        UserDefaults.standard.set(
            downloadMethod.rawValue,
            forKey: methodKey
        )
    }

    func removeToken() {

        apiToken = ""

        KeychainHelper.delete(
            tokenKey
        )
    }
}
