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


        // Treat every other version as an update candidate. In particular,
        // this lets Echo roll back an incompatible newer yt-dlp release. 
        return installedVersion != latestVersion
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


        // Do not follow yt-dlp's moving "latest" release while Echo uses
        // Python 3.10. The supported version is deliberately pinned.
        latestVersion = YTDLPCompatibility.supportedVersion


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

            let resolvedLatestVersion =
                YTDLPCompatibility.supportedVersion

            latestVersion = resolvedLatestVersion

            try await YTDLPRunner
                .shared
                .installCompatibleVersion()

            let verifiedVersion = try await YTDLPRunner
                .shared
                .installedVersion()

            guard verifiedVersion == resolvedLatestVersion else {
                throw YTDLPUpdateError.versionMismatch(
                    expected: resolvedLatestVersion,
                    actual: verifiedVersion
                )
            }

            installedVersion = verifiedVersion

            hasLoadedVersions = true
            didInstallUpdate = true

        } catch {

            errorMessage =
                error.localizedDescription
        }
    }



}


private enum YTDLPUpdateError: LocalizedError {
    case versionMismatch(expected: String, actual: String?)

    var errorDescription: String? {
        switch self {
        case let .versionMismatch(expected, actual):
            return "yt-dlp install verification failed. Expected \(expected), got \(actual ?? "no installed version")."
        }
    }
}
