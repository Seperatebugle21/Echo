import Foundation
import Observation


@MainActor
@Observable
final class YTDLPUpdateManager {

    private(set) var installedVersion:
        String?

    private(set) var latestVersion:
        String?

    private(set) var hasLoadedVersions =
        false

    private(set) var isChecking =
        false

    private(set) var isInstalling =
        false

    private(set) var didInstallUpdate =
        false

    private(set) var errorMessage:
        String?


    var isBusy: Bool {

        isChecking ||
        isInstalling
    }


    var updateAvailable: Bool? {

        guard
            hasLoadedVersions,
            let latestVersion
        else {
            return nil
        }


        guard let installedVersion
        else {
            return true
        }


        return Self.compareVersions(
            installedVersion,
            latestVersion
        ) == .orderedAscending
    }


    func refresh()
        async
    {

        guard !isBusy
        else {
            return
        }


        isChecking = true
        errorMessage = nil
        didInstallUpdate = false


        defer {
            isChecking = false
            hasLoadedVersions = true
        }


        var errors:
            [String] = []


        do {

            installedVersion =
                try await YTDLPRunner
                    .shared
                    .installedVersion()

        } catch {

            errors.append(
                error.localizedDescription
            )
        }


        do {

            latestVersion =
                try await Self
                    .fetchLatestVersion()

        } catch {

            errors.append(
                error.localizedDescription
            )
        }


        if !errors.isEmpty {

            errorMessage =
                errors.joined(
                    separator: "\n"
                )
        }
    }


    func installUpdate()
        async
    {

        guard !isBusy
        else {
            return
        }


        isInstalling = true
        errorMessage = nil
        didInstallUpdate = false


        defer {
            isInstalling = false
        }


        do {

            let resolvedLatestVersion:
                String


            if let latestVersion {

                resolvedLatestVersion =
                    latestVersion

            } else {

                resolvedLatestVersion =
                    try await Self
                        .fetchLatestVersion()

                latestVersion =
                    resolvedLatestVersion
            }


            try await YTDLPRunner
                .shared
                .installLatestVersion()


            installedVersion =
                resolvedLatestVersion

            hasLoadedVersions = true
            didInstallUpdate = true

        } catch {

            errorMessage =
                error.localizedDescription
        }
    }


    private nonisolated static func fetchLatestVersion()
        async throws -> String
    {

        let url =
            URL(
                string:
                    "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
            )!


        var request =
            URLRequest(
                url: url
            )


        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField:
                "Accept"
        )

        request.setValue(
            "2022-11-28",
            forHTTPHeaderField:
                "X-GitHub-Api-Version"
        )

        request.setValue(
            "Echo-iOS",
            forHTTPHeaderField:
                "User-Agent"
        )


        let (
            data,
            response
        ) = try await URLSession
            .shared
            .data(
                for: request
            )


        guard
            let httpResponse =
                response as?
                HTTPURLResponse,
            (200..<300)
                .contains(
                    httpResponse
                        .statusCode
                )
        else {
            throw YTDLPUpdateError
                .invalidResponse
        }


        let release =
            try JSONDecoder()
                .decode(
                    LatestRelease.self,
                    from: data
                )


        guard !release.tagName
            .isEmpty
        else {
            throw YTDLPUpdateError
                .missingVersion
        }


        return release.tagName
    }


    private nonisolated static func compareVersions(
        _ left: String,
        _ right: String
    ) -> ComparisonResult {

        let leftParts =
            versionComponents(left)

        let rightParts =
            versionComponents(right)

        let count =
            max(
                leftParts.count,
                rightParts.count
            )


        for index in 0..<count {

            let leftPart =
                index < leftParts.count
                ? leftParts[index]
                : 0

            let rightPart =
                index < rightParts.count
                ? rightParts[index]
                : 0


            if leftPart < rightPart {
                return .orderedAscending
            }


            if leftPart > rightPart {
                return .orderedDescending
            }
        }


        return .orderedSame
    }


    private nonisolated static func versionComponents(
        _ version: String
    ) -> [Int] {

        version
            .split(
                separator: "."
            )
            .map { component in

                let digits =
                    component
                        .prefix {
                            $0.isNumber
                        }


                return Int(digits)
                    ?? 0
            }
    }
}


private struct LatestRelease:
    Decodable,
    Sendable {

    let tagName: String


    private enum CodingKeys:
        String,
        CodingKey {

        case tagName =
            "tag_name"
    }
}


private enum YTDLPUpdateError:
    LocalizedError {

    case invalidResponse
    case missingVersion


    var errorDescription:
        String? {

        switch self {

        case .invalidResponse:

            return String(
                localized:
                    "developerview_ytdlp_error_response"
            )

        case .missingVersion:

            return String(
                localized:
                    "developerview_ytdlp_error_version"
            )
        }
    }
}
