import Foundation


// MARK: - Download Delegate

private final class FetchURLSessionDownloadDelegate:
    NSObject,
    URLSessionDownloadDelegate {

    var progressHandler:
        (@Sendable (Double) -> Void)?

    var continuation:
        CheckedContinuation<
            (URL, URLResponse),
            Error
        >?

    private var downloadedURL:
        URL?

    private var response:
        URLResponse?


    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {

        guard totalBytesExpectedToWrite >
                0
        else {
            return
        }


        let progress =
            Double(
                totalBytesWritten
            )
            /
            Double(
                totalBytesExpectedToWrite
            )


        progressHandler?(
            min(
                max(progress, 0),
                1
            )
        )
    }


    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {

        do {

            // URLSession's supplied location is temporary.
            // Copy it somewhere we control before the delegate
            // method finishes.

            let temporary =
                FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent(
                        "\(UUID().uuidString).download"
                    )


            if FileManager.default
                .fileExists(
                    atPath:
                        temporary.path
                ) {

                try FileManager.default
                    .removeItem(
                        at:
                            temporary
                    )
            }


            try FileManager.default
                .copyItem(
                    at:
                        location,
                    to:
                        temporary
                )


            downloadedURL =
                temporary

            response =
                downloadTask.response

        } catch {

            continuation?
                .resume(
                    throwing:
                        error
                )

            continuation =
                nil
        }
    }


    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {

        guard let continuation else {
            return
        }


        self.continuation =
            nil


        if let error {

            continuation.resume(
                throwing:
                    error
            )

            return
        }


        guard
            let downloadedURL,
            let response
        else {

            continuation.resume(
                throwing:
                    FetchAudioSourceError
                        .invalidResponse
            )

            return
        }


        continuation.resume(
            returning:
                (
                    downloadedURL,
                    response
                )
        )
    }
}


// MARK: - Download Engine

@MainActor
final class FetchDownloadEngine {

    static let shared =
        FetchDownloadEngine()


    private init() {}


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
            180


        let delegate =
            FetchURLSessionDownloadDelegate()


        delegate.progressHandler = {
            value in

            Task {
                @MainActor in

                progress(
                    value
                )
            }
        }


        let configuration =
            URLSessionConfiguration
                .default


        configuration.timeoutIntervalForRequest =
            180

        configuration.timeoutIntervalForResource =
            600


        let session =
            URLSession(
                configuration:
                    configuration,
                delegate:
                    delegate,
                delegateQueue:
                    nil
            )


        defer {
            session.finishTasksAndInvalidate()
        }


        let (
            temporaryURL,
            response
        ) =
            try await
            withCheckedThrowingContinuation {
                continuation in


                delegate.continuation =
                    continuation


                let task =
                    session.downloadTask(
                        with:
                            request
                    )


                task.resume()
            }


        guard let httpResponse =
            response
                as?
                HTTPURLResponse
        else {

            try? FileManager.default
                .removeItem(
                    at:
                        temporaryURL
                )

            throw FetchAudioSourceError
                .invalidResponse
        }


        guard 200..<300 ~=
                httpResponse.statusCode
        else {

            try? FileManager.default
                .removeItem(
                    at:
                        temporaryURL
                )


            throw FetchAudioSourceError
                .invalidResponse
        }


        let fileManager =
            FileManager.default


        // Source files are temporary processing files.
        // Don't put them in Documents, otherwise the
        // library can discover them.

        let temporaryDirectory =
            fileManager
                .temporaryDirectory
                .appendingPathComponent(
                    "EchoFetchSources",
                    isDirectory:
                        true
                )


        try fileManager
            .createDirectory(
                at:
                    temporaryDirectory,
                withIntermediateDirectories:
                    true
            )


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
                    temporaryDirectory,
                fileName:
                    fileName
            )


        try fileManager
            .moveItem(
                at:
                    temporaryURL,
                to:
                    destination
            )


        progress(
            1
        )


        print(
            "Downloaded source:",
            destination.path
        )


        return destination
    }


    // MARK: - Filename

    private func makeFileName(
        item: FetchItem,
        suggested: String?,
        response: HTTPURLResponse
    ) -> String {

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


                if !URL(
                    fileURLWithPath:
                        sanitized
                )
                .pathExtension
                .isEmpty {

                    return sanitized
                }


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


    // MARK: - MIME

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

        case "audio/webm",
             "video/webm":

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
                separator:
                    ""
            )
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
    }


    private func uniqueDestination(
        directory: URL,
        fileName: String
    ) -> URL {

        let manager =
            FileManager.default


        let original =
            directory
                .appendingPathComponent(
                    fileName
                )


        if !manager.fileExists(
            atPath:
                original.path
        ) {

            return original
        }


        let fileURL =
            URL(
                fileURLWithPath:
                    fileName
            )


        let name =
            fileURL
                .deletingPathExtension()
                .lastPathComponent


        let ext =
            fileURL
                .pathExtension


        var number =
            2


        while true {

            let candidateName =
                ext.isEmpty
                ?
                "\(name) \(number)"
                :
                "\(name) \(number).\(ext)"


            let candidate =
                directory
                    .appendingPathComponent(
                        candidateName
                    )


            if !manager.fileExists(
                atPath:
                    candidate.path
            ) {

                return candidate
            }


            number +=
                1
        }
    }
}
