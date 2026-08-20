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


    var downloadMethod: ApifyDownloadMethod {
        didSet {

            UserDefaults.standard.set(
                downloadMethod.rawValue,
                forKey: methodKey
            )

            print(
                "Apify method saved:",
                downloadMethod.rawValue
            )
        }
    }


    private init() {

        apiToken =
            KeychainHelper.read(
                tokenKey
            ) ?? ""

        if
            let saved =
                UserDefaults.standard.string(
                    forKey: methodKey
                ),
            let method =
                ApifyDownloadMethod(
                    rawValue: saved
                )
        {
            downloadMethod = method

        } else {

            downloadMethod = .youtube
        }

        print(
            "Apify method restored:",
            downloadMethod.rawValue
        )
    }


    var isConfigured: Bool {

        !apiToken
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
    }


    func saveToken() {

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
    }


    func removeToken() {

        apiToken = ""

        KeychainHelper.delete(
            tokenKey
        )
    }
}
