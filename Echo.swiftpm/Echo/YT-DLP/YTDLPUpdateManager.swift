import Foundation
import Observation
import YoutubeDL


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


        // The target is a pinned version, not "newest". Offer the
        // install whenever the installed version differs, so a newer
        // release that this Python runtime can't run (2026.10.26+)
        // is replaced by the pinned one.
        return Self.compareVersions(
            installedVersion,
            latestVersion
        ) != .orderedSame
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

        // yt-dlp 2026.10.26 requires Python 3.11+, but the embedded
        // runtime is Python 3.10, so the target is the pinned release
        // that the YoutubeDL package downloads, not GitHub's newest.
        // Remove the pin once the Python runtime is upgraded.
        YoutubeDL.pinnedVersion
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
