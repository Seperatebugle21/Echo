import Foundation
import UIKit


// MARK: - Persistent Background Record

struct BackgroundFetchRecord:
    Codable,
    Identifiable,
    Sendable {

    let id: UUID

    let spotifyURL: String

    let title: String
    let artist: String
    let album: String?

    let artworkURL: String?
    let youtubeURL: String?

    let permissionConfirmed: Bool

    let suggestedFileName: String?

    var localFilePath: String?

    var completed: Bool

    var errorMessage: String?
}


// MARK: - Parallel Download Helpers

private struct ParallelDownloadProbe:
    Sendable {

    let totalBytes: Int64
    let response: HTTPURLResponse
}


private struct ParallelChunkResult:
    Sendable {

    let index: Int
    let fileURL: URL
}


private enum ParallelDownloadError:
    Error {

    case invalidProbe
    case invalidRangeResponse
    case invalidChunkLength
}


// MARK: - Background Download Engine

final class FetchDownloadEngine:
    NSObject,
    URLSessionDownloadDelegate,
    URLSessionDelegate,
    @unchecked Sendable {

    static let shared =
        FetchDownloadEngine()


    static let backgroundSessionIdentifier =
        "Echo.Fetch.BackgroundDownloads"


    private let recordsKey =
        "echo.fetch.background.records"


    // Six simultaneous byte ranges.

    private let parallelChunkCount =
        6


    // Tiny files don't benefit much.

    private let minimumParallelFileSize:
        Int64 =
        1_000_000


    private let stateLock =
        NSLock()


    private var continuations:
        [
            UUID:
                CheckedContinuation<
                    URL,
                    Error
                >
        ] = [:]


    private var progressHandlers:
        [
            UUID:
                @Sendable
                (Double) -> Void
        ] = [:]


    private var claimedRecords:
        Set<UUID> = []


    private var backgroundCompletionHandler:
        (() -> Void)?


    var progressObserver:
        (@Sendable (UUID, Double) -> Void)?


    var completionObserver:
        (@Sendable (BackgroundFetchRecord) -> Void)?


    // MARK: - Background Session

    private lazy var session:
        URLSession = {

        let configuration =
            URLSessionConfiguration
                .background(
                    withIdentifier:
                        Self.backgroundSessionIdentifier
                )


        configuration.isDiscretionary =
            false


        configuration.sessionSendsLaunchEvents =
            true


        configuration.waitsForConnectivity =
            true


        configuration.allowsCellularAccess =
            true


        configuration.timeoutIntervalForRequest =
            180


        configuration.timeoutIntervalForResource =
            24 * 60 * 60


        let queue =
            OperationQueue()


        queue.maxConcurrentOperationCount =
            1


        queue.name =
            "Echo.BackgroundDownloads"


        return URLSession(
            configuration:
                configuration,

            delegate:
                self,

            delegateQueue:
                queue
        )
    }()


    // MARK: - Foreground Parallel Session

    private lazy var parallelSession:
        URLSession = {

        let configuration =
            URLSessionConfiguration.default


        configuration.waitsForConnectivity =
            true


        configuration.allowsCellularAccess =
            true


        configuration.timeoutIntervalForRequest =
            180


        configuration.timeoutIntervalForResource =
            60 * 60


        configuration.httpMaximumConnectionsPerHost =
            parallelChunkCount


        return URLSession(
            configuration:
                configuration
        )
    }()


    private override init() {

        super.init()
    }


    // MARK: - Prepare

    func prepare() {

        _ = session
    }


    // MARK: - Download

    @MainActor
    func download(
        item: FetchItem,
        result: FetchAudioResult,
        progress:
            @escaping
            @MainActor
            (Double) -> Void
    ) async throws -> URL {

        prepare()


        let record =
            BackgroundFetchRecord(

                id:
                    UUID(),

                spotifyURL:
                    item.spotifyURL
                        .absoluteString,

                title:
                    item.title,

                artist:
                    item.artist,

                album:
                    item.album,

                artworkURL:
                    item.artworkURL?
                        .absoluteString,

                youtubeURL:
                    item.youtubeURL?
                        .absoluteString,

                permissionConfirmed:
                    item.permissionConfirmed,

                suggestedFileName:
                    result.suggestedFileName,

                localFilePath:
                    nil,

                completed:
                    false,

                errorMessage:
                    nil
            )


        saveOrUpdate(
            record
        )


        // Try accelerated mode only while app is active.

        if UIApplication.shared
            .applicationState ==
            .active {

            do {

                if let probe =
                    try await probeParallelDownload(
                        url:
                            result.downloadURL
                    ),

                   probe.totalBytes >=
                    minimumParallelFileSize {

                    print(
                        "Echo parallel download:",
                        parallelChunkCount,
                        "chunks,",
                        probe.totalBytes,
                        "bytes"
                    )


                    return try await
                        downloadInParallel(
                            record:
                                record,

                            downloadURL:
                                result.downloadURL,

                            probe:
                                probe,

                            progress:
                                progress
                        )
                }


            } catch {

                print(
                    "Parallel download fallback:",
                    error.localizedDescription
                )
            }
        }


        // Fall back to old reliable background downloader.

        return try await
            startBackgroundDownload(
                record:
                    record,

                downloadURL:
                    result.downloadURL,

                progress:
                    progress
            )
    }


    // MARK: - Probe Range Support

    private func probeParallelDownload(
        url: URL
    ) async throws
        -> ParallelDownloadProbe? {

        var request =
            URLRequest(
                url:
                    url
            )


        request.timeoutInterval =
            30


        request.setValue(
            "bytes=0-0",
            forHTTPHeaderField:
                "Range"
        )


        let (_, response) =
            try await parallelSession
                .data(
                    for:
                        request
                )


        guard let http =
            response as?
                HTTPURLResponse
        else {

            return nil
        }


        guard http.statusCode ==
            206
        else {

            return nil
        }


        guard let contentRange =
            http.value(
                forHTTPHeaderField:
                    "Content-Range"
            ),

              let slashIndex =
            contentRange.lastIndex(
                of:
                    "/"
            )
        else {

            return nil
        }


        let totalString =
            contentRange[
                contentRange.index(
                    after:
                        slashIndex
                )...
            ]


        guard let totalBytes =
            Int64(
                totalString
            ),

              totalBytes >
            0
        else {

            return nil
        }


        return ParallelDownloadProbe(
            totalBytes:
                totalBytes,

            response:
                http
        )
    }


    // MARK: - Six-Part Download

    @MainActor
    private func downloadInParallel(
        record originalRecord: BackgroundFetchRecord,
        downloadURL: URL,
        probe: ParallelDownloadProbe,
        progress:
            @escaping
            @MainActor
            (Double) -> Void
    ) async throws -> URL {

        let directory =
            try backgroundSourceDirectory()


        let partsDirectory =
            directory
                .appendingPathComponent(
                    "\(originalRecord.id.uuidString).parts",
                    isDirectory:
                        true
                )


        try? FileManager.default
            .removeItem(
                at:
                    partsDirectory
            )


        try FileManager.default
            .createDirectory(
                at:
                    partsDirectory,

                withIntermediateDirectories:
                    true
            )


        let extensionName =
            fileExtension(
                record:
                    originalRecord,

                response:
                    probe.response
            )


        let destination =
            directory
                .appendingPathComponent(
                    "\(originalRecord.id.uuidString).\(extensionName)"
                )


        try? FileManager.default
            .removeItem(
                at:
                    destination
            )


        let totalBytes =
            probe.totalBytes


        let chunkCount =
            min(
                parallelChunkCount,
                max(
                    1,
                    Int(
                        totalBytes
                    )
                )
            )


        let baseChunkSize =
            totalBytes
            /
            Int64(
                chunkCount
            )


        var ranges:
            [
                (
                    index: Int,
                    start: Int64,
                    end: Int64,
                    expected: Int64
                )
            ] = []


        for index in
            0..<chunkCount {

            let start =
                Int64(
                    index
                )
                *
                baseChunkSize


            let end:
                Int64


            if index ==
                chunkCount - 1 {

                end =
                    totalBytes - 1


            } else {

                end =
                    start
                    +
                    baseChunkSize
                    -
                    1
            }


            ranges.append(
                (
                    index:
                        index,

                    start:
                        start,

                    end:
                        end,

                    expected:
                        end - start + 1
                )
            )
        }


        do {

            var completedBytes:
                Int64 =
                0


            var chunkResults:
                [ParallelChunkResult] =
                []


            try await withThrowingTaskGroup(
                of:
                    (
                        ParallelChunkResult,
                        Int64
                    ).self
            ) {
                group in


                for range in
                    ranges {

                    let partURL =
                        partsDirectory
                            .appendingPathComponent(
                                "\(range.index).part"
                            )


                    group.addTask {
                        [parallelSession]
                        in


                        var request =
                            URLRequest(
                                url:
                                    downloadURL
                            )


                        request.timeoutInterval =
                            180


                        request.setValue(
                            "bytes=\(range.start)-\(range.end)",
                            forHTTPHeaderField:
                                "Range"
                        )


                        let (data, response) =
                            try await parallelSession
                                .data(
                                    for:
                                        request
                                )


                        guard let http =
                            response as?
                                HTTPURLResponse,

                              http.statusCode ==
                            206
                        else {

                            throw ParallelDownloadError
                                .invalidRangeResponse
                        }


                        guard Int64(
                            data.count
                        ) ==
                            range.expected
                        else {

                            throw ParallelDownloadError
                                .invalidChunkLength
                        }


                        try data.write(
                            to:
                                partURL,

                            options:
                                .atomic
                        )


                        return (
                            ParallelChunkResult(
                                index:
                                    range.index,

                                fileURL:
                                    partURL
                            ),
                            range.expected
                        )
                    }
                }


                for try await result in
                    group {

                    chunkResults.append(
                        result.0
                    )


                    completedBytes +=
                        result.1


                    let value =
                        min(
                            max(
                                Double(
                                    completedBytes
                                )
                                /
                                Double(
                                    totalBytes
                                ),
                                0
                            ),
                            1
                        )


                    emitParallelProgress(
                        id:
                            originalRecord.id,

                        value:
                            value,

                        progress:
                            progress
                    )
                }
            }


            guard chunkResults.count ==
                chunkCount
            else {

                throw ParallelDownloadError
                    .invalidChunkLength
            }


            chunkResults.sort {

                $0.index <
                    $1.index
            }


            FileManager.default
                .createFile(
                    atPath:
                        destination.path,

                    contents:
                        nil
                )


            let output =
                try FileHandle(
                    forWritingTo:
                        destination
                )


            defer {

                try? output.close()
            }


            // Merge chunks in correct order.

            for chunk in
                chunkResults {

                let input =
                    try FileHandle(
                        forReadingFrom:
                            chunk.fileURL
                    )


                defer {

                    try? input.close()
                }


                while true {

                    let data =
                        try input.read(
                            upToCount:
                                512 * 1024
                        )
                        ??
                        Data()


                    if data.isEmpty {

                        break
                    }


                    try output.write(
                        contentsOf:
                            data
                    )
                }
            }


            let attributes =
                try FileManager.default
                    .attributesOfItem(
                        atPath:
                            destination.path
                    )


            let finalSize =
                (
                    attributes[
                        .size
                    ] as?
                        NSNumber
                )?
                .int64Value
                ??
                -1


            guard finalSize ==
                totalBytes
            else {

                throw ParallelDownloadError
                    .invalidChunkLength
            }


            try? FileManager.default
                .removeItem(
                    at:
                        partsDirectory
                )


            var record =
                originalRecord


            record.localFilePath =
                destination.path


            record.completed =
                true


            record.errorMessage =
                nil


            saveOrUpdate(
                record
            )


            stateLock.lock()


            claimedRecords.insert(
                record.id
            )


            stateLock.unlock()


            emitParallelProgress(
                id:
                    record.id,

                value:
                    1,

                progress:
                    progress
            )


            return destination


        } catch {

            try? FileManager.default
                .removeItem(
                    at:
                        partsDirectory
                )


            try? FileManager.default
                .removeItem(
                    at:
                        destination
                )


            throw error
        }
    }


    // MARK: - Parallel Progress

    @MainActor
    private func emitParallelProgress(
        id: UUID,
        value: Double,
        progress:
            @escaping
            @MainActor
            (Double) -> Void
    ) {

        let clamped =
            min(
                max(
                    value,
                    0
                ),
                1
            )


        progress(
            clamped
        )


        stateLock.lock()


        let observer =
            progressObserver


        stateLock.unlock()


        observer?(
            id,
            clamped
        )
    }


    // MARK: - Existing Background Download

    @MainActor
    private func startBackgroundDownload(
        record: BackgroundFetchRecord,
        downloadURL: URL,
        progress:
            @escaping
            @MainActor
            (Double) -> Void
    ) async throws -> URL {

        var request =
            URLRequest(
                url:
                    downloadURL
            )


        request.timeoutInterval =
            180


        return try await
            withCheckedThrowingContinuation {
                continuation in


                stateLock.lock()


                continuations[
                    record.id
                ] =
                    continuation


                progressHandlers[
                    record.id
                ] = {
                    value in


                    Task {
                        @MainActor in


                        progress(
                            value
                        )
                    }
                }


                stateLock.unlock()


                let task =
                    session.downloadTask(
                        with:
                            request
                    )


                task.taskDescription =
                    record.id.uuidString


                task.resume()
            }
    }


    // MARK: - Background Progress

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {

        guard
            totalBytesExpectedToWrite > 0,

            let id =
                recordID(
                    for:
                        downloadTask
                )

        else {

            return
        }


        let progress =
            min(
                max(
                    Double(
                        totalBytesWritten
                    )
                    /
                    Double(
                        totalBytesExpectedToWrite
                    ),
                    0
                ),
                1
            )


        stateLock.lock()


        let handler =
            progressHandlers[
                id
            ]


        let observer =
            progressObserver


        stateLock.unlock()


        handler?(
            progress
        )


        observer?(
            id,
            progress
        )
    }


    // MARK: - Background Download Finished

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {

        guard
            let id =
                recordID(
                    for:
                        downloadTask
                ),

            var record =
                record(
                    id:
                        id
                )

        else {

            return
        }


        do {

            guard
                let response =
                    downloadTask.response
                        as?
                        HTTPURLResponse,

                200..<300 ~=
                    response.statusCode

            else {

                throw FetchAudioSourceError
                    .invalidResponse
            }


            let directory =
                try backgroundSourceDirectory()


            let extensionName =
                fileExtension(
                    record:
                        record,

                    response:
                        response
                )


            let destination =
                directory
                    .appendingPathComponent(
                        "\(record.id.uuidString).\(extensionName)"
                    )


            if FileManager.default
                .fileExists(
                    atPath:
                        destination.path
                ) {

                try FileManager.default
                    .removeItem(
                        at:
                            destination
                    )
            }


            try FileManager.default
                .moveItem(
                    at:
                        location,

                    to:
                        destination
                )


            record.localFilePath =
                destination.path


            record.completed =
                true


            record.errorMessage =
                nil


            saveOrUpdate(
                record
            )


            let hasLiveDownload =
                hasLiveContinuation(
                    id:
                        record.id
                )


            if hasLiveDownload {

                if UIApplication.shared
                    .applicationState ==
                    .active {

                    resumeLiveContinuation(
                        record:
                            record
                    )
                }


            } else {

                completionObserver?(
                    record
                )
            }


        } catch {

            record.errorMessage =
                error.localizedDescription


            saveOrUpdate(
                record
            )


            failLiveContinuation(
                id:
                    id,

                error:
                    error
            )
        }
    }


    // MARK: - Background Task Failed

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {

        guard
            let error,

            let id =
                recordID(
                    for:
                        task
                )

        else {

            return
        }


        if var record =
            record(
                id:
                    id
            ) {

            record.errorMessage =
                error.localizedDescription


            saveOrUpdate(
                record
            )
        }


        failLiveContinuation(
            id:
                id,

            error:
                error
        )
    }


    // MARK: - Background Events

    func handleBackgroundEvents(
        identifier: String,
        completionHandler:
            @escaping
            () -> Void
    ) {

        guard identifier ==
            Self.backgroundSessionIdentifier

        else {

            completionHandler()

            return
        }


        prepare()


        stateLock.lock()


        backgroundCompletionHandler =
            completionHandler


        stateLock.unlock()
    }


    func urlSessionDidFinishEvents(
        forBackgroundURLSession session: URLSession
    ) {

        stateLock.lock()


        let handler =
            backgroundCompletionHandler


        backgroundCompletionHandler =
            nil


        stateLock.unlock()


        guard let handler else {

            return
        }


        DispatchQueue.main.async {

            handler()
        }
    }


    // MARK: - Foreground Resume

    func resumeLiveCompletedTransfers() {

        let completed =
            records()
                .filter {

                    $0.completed
                    &&
                    $0.localFilePath != nil
                    &&
                    $0.errorMessage == nil
                }


        for record in completed {

            if hasLiveContinuation(
                id:
                    record.id
            ) {

                resumeLiveContinuation(
                    record:
                        record
                )
            }
        }
    }


    // MARK: - Recovery After Relaunch

    func recoveryRecords()
        -> [BackgroundFetchRecord] {

        stateLock.lock()


        let liveIDs =
            Set(
                continuations.keys
            )


        let claimed =
            claimedRecords


        stateLock.unlock()


        return records()
            .filter {

                !liveIDs.contains(
                    $0.id
                )
                &&
                !claimed.contains(
                    $0.id
                )
            }
    }


    // MARK: - Remove Records

    func removeRecords(
        spotifyURL: URL,
        title: String
    ) {

        let matchingRecords =
            records()
                .filter {

                    $0.spotifyURL ==
                        spotifyURL.absoluteString
                    &&
                    $0.title ==
                        title
                }


        for record in matchingRecords {

            if let path =
                record.localFilePath {

                try? FileManager.default
                    .removeItem(
                        atPath:
                            path
                    )
            }


            removeRecord(
                id:
                    record.id
            )
        }
    }


    // MARK: - Consumed Source

    func markSourceConsumed(
        _ sourceURL: URL
    ) {

        let match =
            records()
                .first {

                    $0.localFilePath ==
                        sourceURL.path
                }


        guard let match else {

            return
        }


        if let path =
            match.localFilePath {

            try? FileManager.default
                .removeItem(
                    atPath:
                        path
                )
        }


        removeRecord(
            id:
                match.id
        )
    }


    func markRecordConsumed(
        id: UUID
    ) {

        if
            let existing =
                record(
                    id:
                        id
                ),

            let path =
                existing.localFilePath {

            try? FileManager.default
                .removeItem(
                    atPath:
                        path
                )
        }


        removeRecord(
            id:
                id
        )
    }


    // MARK: - Live Continuation Check

    private func hasLiveContinuation(
        id: UUID
    ) -> Bool {

        stateLock.lock()


        defer {

            stateLock.unlock()
        }


        return continuations[
            id
        ] != nil
    }


    // MARK: - Resume Continuation

    private func resumeLiveContinuation(
        record: BackgroundFetchRecord
    ) {

        guard let path =
            record.localFilePath

        else {

            return
        }


        let url =
            URL(
                fileURLWithPath:
                    path
            )


        guard FileManager.default
            .fileExists(
                atPath:
                    url.path
            )

        else {

            return
        }


        stateLock.lock()


        guard
            !claimedRecords
                .contains(
                    record.id
                ),

            let continuation =
                continuations
                    .removeValue(
                        forKey:
                            record.id
                    )

        else {

            stateLock.unlock()

            return
        }


        claimedRecords.insert(
            record.id
        )


        progressHandlers
            .removeValue(
                forKey:
                    record.id
            )


        stateLock.unlock()


        continuation.resume(
            returning:
                url
        )
    }


    // MARK: - Fail Continuation

    private func failLiveContinuation(
        id: UUID,
        error: Error
    ) {

        stateLock.lock()


        let continuation =
            continuations
                .removeValue(
                    forKey:
                        id
                )


        progressHandlers
            .removeValue(
                forKey:
                    id
            )


        claimedRecords
            .remove(
                id
            )


        stateLock.unlock()


        continuation?
            .resume(
                throwing:
                    error
            )
    }


    // MARK: - Task Record ID

    private func recordID(
        for task: URLSessionTask
    ) -> UUID? {

        guard let description =
            task.taskDescription

        else {

            return nil
        }


        return UUID(
            uuidString:
                description
        )
    }


    // MARK: - Storage

    private func records()
        -> [BackgroundFetchRecord] {

        stateLock.lock()


        defer {

            stateLock.unlock()
        }


        guard
            let data =
                UserDefaults.standard
                    .data(
                        forKey:
                            recordsKey
                    ),

            let values =
                try? JSONDecoder()
                    .decode(
                        [BackgroundFetchRecord].self,

                        from:
                            data
                    )

        else {

            return []
        }


        return values
    }


    private func record(
        id: UUID
    ) -> BackgroundFetchRecord? {

        records()
            .first {

                $0.id ==
                    id
            }
    }


    private func saveOrUpdate(
        _ record: BackgroundFetchRecord
    ) {

        stateLock.lock()


        var values:
            [BackgroundFetchRecord]


        if
            let data =
                UserDefaults.standard
                    .data(
                        forKey:
                            recordsKey
                    ),

            let decoded =
                try? JSONDecoder()
                    .decode(
                        [BackgroundFetchRecord].self,

                        from:
                            data
                    ) {

            values =
                decoded


        } else {

            values =
                []
        }


        if let index =
            values.firstIndex(
                where: {

                    $0.id ==
                        record.id
                }
            ) {

            values[
                index
            ] =
                record


        } else {

            values.append(
                record
            )
        }


        if let data =
            try? JSONEncoder()
                .encode(
                    values
                ) {

            UserDefaults.standard
                .set(
                    data,

                    forKey:
                        recordsKey
                )
        }


        stateLock.unlock()
    }


    private func removeRecord(
        id: UUID
    ) {

        stateLock.lock()


        var values:
            [BackgroundFetchRecord] =
            []


        if
            let data =
                UserDefaults.standard
                    .data(
                        forKey:
                            recordsKey
                    ),

            let decoded =
                try? JSONDecoder()
                    .decode(
                        [BackgroundFetchRecord].self,

                        from:
                            data
                    ) {

            values =
                decoded
        }


        values.removeAll {

            $0.id ==
                id
        }


        if let data =
            try? JSONEncoder()
                .encode(
                    values
                ) {

            UserDefaults.standard
                .set(
                    data,

                    forKey:
                        recordsKey
                )
        }


        continuations
            .removeValue(
                forKey:
                    id
            )


        progressHandlers
            .removeValue(
                forKey:
                    id
            )


        claimedRecords
            .remove(
                id
            )


        stateLock.unlock()
    }


    // MARK: - Background Source Directory

    private func backgroundSourceDirectory()
        throws -> URL {

        let root =
            FileManager.default
                .urls(
                    for:
                        .applicationSupportDirectory,

                    in:
                        .userDomainMask
                )[0]


        let directory =
            root
                .appendingPathComponent(
                    "EchoBackgroundSources",

                    isDirectory:
                        true
                )


        try FileManager.default
            .createDirectory(
                at:
                    directory,

                withIntermediateDirectories:
                    true
            )


        return directory
    }


    // MARK: - File Extension

    private func fileExtension(
        record: BackgroundFetchRecord,
        response: HTTPURLResponse
    ) -> String {

        if let suggested =
            record.suggestedFileName {

            let ext =
                URL(
                    fileURLWithPath:
                        suggested
                )
                .pathExtension


            if !ext.isEmpty {

                return ext
            }
        }


        switch response.mimeType?
            .lowercased() {

        case "audio/mp4":

            return "m4a"


        case "video/mp4":

            return "mp4"


        case "audio/webm",
             "video/webm":

            return "webm"


        case "audio/mpeg":

            return "mp3"


        case "audio/aac":

            return "aac"


        case "audio/ogg":

            return "ogg"


        case "audio/opus":

            return "opus"


        default:

            return "audio"
        }
    }
}
