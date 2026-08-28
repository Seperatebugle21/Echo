import Foundation


@MainActor
final class FetchDownloadEngine {

    static let shared =
        FetchDownloadEngine()

    private init() {}


    // MARK: - Download

    func download(
        item: FetchItem,
        result: FetchAudioResult,
        progress:
            @escaping
            @MainActor
            (Double) -> Void
    ) async throws -> URL {

        var request =
            URLRequest(
                url:
                    result.downloadURL
            )


        request.timeoutInterval =
            120


        // Googlevideo URLs kunnen tijdelijk zijn.
        // Daarom downloaden we ze onmiddellijk.

        await progress(
            0.05
        )


        let (
            temporaryURL,
            response
        ) =
            try await
            URLSession.shared.download(
                for:
                    request
            )


        guard let httpResponse =
            response as? HTTPURLResponse
        else {

            throw FetchAudioSourceError
                .invalidResponse
        }


        guard
            200..<300 ~=
            httpResponse.statusCode
        else {

            print(
                "Download HTTP error:",
                httpResponse.statusCode
            )

            throw FetchAudioSourceError
                .invalidResponse
        }


        await progress(
            0.8
        )


        let fileManager =
            FileManager.default


        let documents =
            fileManager.urls(
                for:
                    .documentDirectory,

                in:
                    .userDomainMask
            )[0]


        let fileName =
            makeFileName(
                item:
                    item,

                suggested:
                    result
                        .suggestedFileName,

                response:
                    httpResponse
            )


        let destination =
            uniqueDestination(
                directory:
                    documents,

                fileName:
                    fileName
            )


        print(
            "Moving downloaded source to:",
            destination.path
        )


        try fileManager.moveItem(
            at:
                temporaryURL,

            to:
                destination
        )


        await progress(
            1.0
        )


        return destination
    }


    // MARK: - Filename

    private func makeFileName(
        item: FetchItem,
        suggested: String?,
        response: HTTPURLResponse
    ) -> String {

        // =========================================
        // 1. Use source-provided filename
        // =========================================

        if let suggested {

            let trimmed =
                suggested
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )


            if !trimmed.isEmpty {

                let sanitized =
                    sanitize(
                        trimmed
                    )


                // Als er al een echte extensie is:
                // gewoon behouden.

                if !URL(
                    fileURLWithPath:
                        sanitized
                )
                .pathExtension
                .isEmpty {

                    return sanitized
                }


                // Geen extensie?
                // Probeer Content-Type.

                if let ext =
                    extensionFromResponse(
                        response
                    ) {

                    return
                        "\(sanitized).\(ext)"
                }


                return
                    "\(sanitized).bin"
            }
        }


        // =========================================
        // 2. Fallback
        // =========================================

        let base =
            sanitize(
                "\(item.title) - \(item.artist)"
            )


        if let ext =
            extensionFromResponse(
                response
            ) {

            return
                "\(base).\(ext)"
        }


        return
            "\(base).bin"
    }


    // MARK: - Content Type

    private func extensionFromResponse(
        _ response: HTTPURLResponse
    ) -> String? {

        guard let mime =
            response.mimeType?
                .lowercased()
        else {

            return nil
        }


        switch mime {

        case "audio/webm":
            return "webm"

        case "video/webm":
            return "webm"

        case "audio/mp4":
            return "m4a"

        case "video/mp4":
            return "mp4"

        case "audio/mpeg":
            return "mp3"

        case "audio/ogg":
            return "ogg"

        case "audio/opus":
            return "opus"

        case "audio/aac":
            return "aac"

        default:
            return nil
        }
    }


    // MARK: - Sanitize

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
                separatedBy:
                    illegal
            )
            .joined(
                separator: ""
            )
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
    }


    // MARK: - Unique destination

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


        guard
            fileManager.fileExists(
                atPath:
                    original.path
            )
        else {

            return original
        }


        let url =
            URL(
                fileURLWithPath:
                    fileName
            )


        let name =
            url
                .deletingPathExtension()
                .lastPathComponent


        let ext =
            url
                .pathExtension


        var number =
            2


        while true {

            let candidateName:
                String


            if ext.isEmpty {

                candidateName =
                    "\(name) \(number)"

            } else {

                candidateName =
                    "\(name) \(number).\(ext)"
            }


            let candidate =
                directory
                    .appendingPathComponent(
                        candidateName
                    )


            if !fileManager.fileExists(
                atPath:
                    candidate.path
            ) {

                return candidate
            }


            number += 1
        }
    }
}
