import Foundation
import UIKit


// MARK: - Persistent Background Record

struct BackgroundFetchRecord: Codable, Identifiable, Sendable {

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


    // A claimed download is already owned by
    // the current FetchManager pipeline.
    private var claimedRecords:
        Set<UUID> = []


    private var backgroundCompletionHandler:
        (() -> Void)?


    // Used after an app relaunch.

    var progressObserver:
        (@Sendable (UUID, Double) -> Void)?

    var completionObserver:
        (@Sendable (BackgroundFetchRecord) -> Void)?


    // MARK: - Session

    private lazy var session:
        URLSession = {

        let configuration =
            URLSessionConfiguration
                .background(
                    withIdentifier:
                        Self.backgroundSessionIdentifier
                )


        // Start immediately.
        configuration.isDiscretionary =
            false


        // Let iOS relaunch/wake Echo
        // when transfers finish.
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


    private override init() {

        super.init()
    }


    // Force creation of the background session.

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


        var request =
            URLRequest(
                url:
                    result.downloadURL
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


                // The task can survive Echo being suspended.
                // Store only the persistent UUID here.

                task.taskDescription =
                    record.id.uuidString


                task.resume()
            }
    }


    // MARK: - Progress

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


    // MARK: - Download Finished

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


            // IMPORTANT:
            //
            // The URL supplied by iOS is temporary and
            // disappears after this delegate callback.
            //
            // Move it immediately to Application Support.

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


            completionObserver?(
                record
            )


            // Only continue into LAME immediately when
            // Echo is actually in the foreground.
            //
            // Otherwise the source remains safely stored
            // until Echo becomes active again.

            if UIApplication.shared
                .applicationState ==
                .active {

                resumeLiveContinuation(
                    record:
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


    // MARK: - Task Failed

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

    /// Call whenever Echo becomes active.
    ///
    /// This resumes downloads that finished while
    /// the device was locked/backgrounded but whose
    /// original async FetchManager call still exists.

    func resumeLiveCompletedTransfers() {

        let completed =
            records()
                .filter {
                    $0.completed &&
                    $0.localFilePath != nil &&
                    $0.errorMessage == nil
                }


        for record in completed {

            resumeLiveContinuation(
                record:
                    record
            )
        }
    }


    // MARK: - Recovery After Relaunch

    /// Returns records that are no longer attached
    /// to an in-memory continuation.
    ///
    /// This happens after iOS terminated/relaunched Echo.

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


    // MARK: - Consumed

    func markSourceConsumed(
        _ sourceURL: URL
    ) {

        let match =
            records().first {

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

        if let existing =
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


    // MARK: - Continuation

    private func resumeLiveContinuation(
        record: BackgroundFetchRecord
    ) {

        guard
            let path =
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


    // MARK: - IDs

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

        records().first {

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

            values[index] =
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
            [BackgroundFetchRecord] = []


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


    // MARK: - File Location

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
