import Foundation

@MainActor
final class FetchDownloadEngine {

    static let shared = FetchDownloadEngine()

    private init() {}

    func download(
        item: FetchItem,
        result: FetchAudioResult,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> URL {

        var request = URLRequest(
            url: result.downloadURL
        )

        request.timeoutInterval = 120

        let (temporaryURL, response) =
            try await URLSession.shared.download(
                for: request
            )

        guard let httpResponse =
            response as? HTTPURLResponse
        else {
            throw FetchAudioSourceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw FetchAudioSourceError.invalidResponse
        }

        await progress(0.8)

        let fileManager = FileManager.default

        let documents =
            fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]

        let fileName =
            makeFileName(
                item: item,
                suggested:
                    result.suggestedFileName
            )

        let destination =
            uniqueDestination(
                directory: documents,
                fileName: fileName
            )

        try fileManager.moveItem(
            at: temporaryURL,
            to: destination
        )

        await progress(1.0)

        return destination
    }


    private func makeFileName(
        item: FetchItem,
        suggested: String?
    ) -> String {

        if let suggested,
           !suggested.isEmpty {

            if suggested
                .lowercased()
                .hasSuffix(".mp3") {

                return sanitize(
                    suggested
                )
            }

            return sanitize(
                suggested + ".mp3"
            )
        }

        let base =
            "\(item.title) - \(item.artist)"

        return sanitize(base) + ".mp3"
    }


    private func sanitize(
        _ value: String
    ) -> String {

        let illegal =
            CharacterSet(
                charactersIn:
                    "/\\:*?\"<>|"
            )

        return value
            .components(
                separatedBy: illegal
            )
            .joined(separator: "")
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }


    private func uniqueDestination(
        directory: URL,
        fileName: String
    ) -> URL {

        let fileManager =
            FileManager.default

        let original =
            directory
                .appendingPathComponent(
                    fileName
                )

        guard fileManager.fileExists(
            atPath: original.path
        ) else {
            return original
        }

        let url =
            URL(
                fileURLWithPath: fileName
            )

        let name =
            url
                .deletingPathExtension()
                .lastPathComponent

        let ext =
            url.pathExtension

        var number = 2

        while true {

            let candidateName =
                "\(name) \(number).\(ext)"

            let candidate =
                directory
                    .appendingPathComponent(
                        candidateName
                    )

            if !fileManager.fileExists(
                atPath: candidate.path
            ) {
                return candidate
            }

            number += 1
        }
    }
}
