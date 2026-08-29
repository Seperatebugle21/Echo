import Foundation
import UIKit


// MARK: - Encoding Gate
//
// Multiple tracks may resolve/download at once,
// but only one LAME encoder runs at a time.

private actor FetchEncodingGate {

    static let shared =
        FetchEncodingGate()


    private var busy =
        false


    private var waiters:
        [
            CheckedContinuation<
                Void,
                Never
            >
        ] = []


    func acquire()
        async {

        if !busy {

            busy =
                true

            return
        }


        await withCheckedContinuation {
            continuation in


            waiters.append(
                continuation
            )
        }
    }


    func release() {

        if waiters.isEmpty {

            busy =
                false

        } else {

            let next =
                waiters.removeFirst()


            next.resume()
        }
    }
}


// MARK: - Fetch Manager

@MainActor
@Observable
final class FetchManager {

    static let shared =
        FetchManager()


    private(set) var items:
        [FetchItem] = []


    private var running =
        false


    private var restoredBackgroundIDs:
        Set<UUID> = []


    private var backgroundRecoveryRunning =
        false


    private init() {

        FetchDownloadEngine.shared
            .progressObserver = {
                [weak self]
                id,
                progress in


                Task {
                    @MainActor in


                    self?
                        .updateRestoredBackgroundProgress(
                            id:
                                id,
                            progress:
                                progress
                        )
                }
            }


        FetchDownloadEngine.shared
            .completionObserver = {
                [weak self]
                record in


                Task {
                    @MainActor in


                    self?
                        .backgroundTransferFinished(
                            record
                        )
                }
            }
    }


    // MARK: - Spotify URL

    func addSpotifyURL(
        _ string: String
    ) {

        guard let reference =
            SpotifyURLParser.parse(
                string
            )
        else {

            return
        }


        let item =
            FetchItem(
                spotifyURL:
                    reference.url,
                title:
                    defaultTitle(
                        for:
                            reference.type
                    ),
                artist:
                    "Spotify"
            )


        items.append(
            item
        )


        startIfNeeded()
    }


    // MARK: - Authorized Apify Match

    func addAuthorizedMatch(
        track: SpotifyTrack,
        youtubeResult: YouTubeSearchResult
    ) {

        let item =
            FetchItem(
                spotifyURL:
                    track.spotifyURL,
                title:
                    track.name,
                artist:
                    track.artist,
                album:
                    track.album,
                artworkURL:
                    track.artworkURL,
                youtubeURL:
                    youtubeResult.videoURL,
                permissionConfirmed:
                    true
            )


        items.append(
            item
        )


        startIfNeeded()
    }


    // MARK: - Playlist

    func preparePlaylist(
        _ playlist: SpotifyPlaylist
    ) async throws {

        let tracks =
            try await
            SpotifyAPI.shared
                .getPlaylistTracks(
                    playlistID:
                        playlist.id
                )


        for track in tracks {

            await preparePlaylistTrack(
                track
            )
        }


        startIfNeeded()
    }


    private func preparePlaylistTrack(
        _ track: SpotifyTrack
    ) async {

        do {

            switch
                ApifySettings.shared
                    .downloadMethod {

            case .youtube:

                let results =
                    try await
                    YouTubeAPI.shared
                        .search(
                            title:
                                track.name,
                            artist:
                                track.artist,
                            maxResults:
                                1
                        )


                guard let result =
                    results.first
                else {

                    return
                }


                items.append(
                    FetchItem(
                        spotifyURL:
                            track.spotifyURL,
                        title:
                            track.name,
                        artist:
                            track.artist,
                        album:
                            track.album,
                        artworkURL:
                            track.artworkURL,
                        youtubeURL:
                            result.videoURL,
                        permissionConfirmed:
                            true
                    )
                )


            case .spotify:

                items.append(
                    FetchItem(
                        spotifyURL:
                            track.spotifyURL,
                        title:
                            track.name,
                        artist:
                            track.artist,
                        album:
                            track.album,
                        artworkURL:
                            track.artworkURL,
                        youtubeURL:
                            nil,
                        permissionConfirmed:
                            true
                    )
                )
            }

        } catch {

            print(
                "Playlist track failed:",
                track.name,
                error
            )
        }
    }


    // MARK: - Add Track

    func add(
        _ track: SpotifyTrack
    ) {

        items.append(
            FetchItem(
                spotifyURL:
                    track.spotifyURL,
                title:
                    track.name,
                artist:
                    track.artist,
                album:
                    track.album,
                artworkURL:
                    track.artworkURL
            )
        )


        startIfNeeded()
    }


    // MARK: - Add Playlist

    func add(
        _ playlist: SpotifyPlaylist
    ) {

        items.append(
            FetchItem(
                spotifyURL:
                    playlist.spotifyURL,
                title:
                    playlist.name,
                artist:
                    "\(playlist.trackCount) songs",
                artworkURL:
                    playlist.artworkURL
            )
        )


        startIfNeeded()
    }


    // MARK: - Authorized yt-dlp Track

    func addAuthorizedSpotifyTrack(
        _ track: SpotifyTrack
    ) {

        items.append(
            FetchItem(
                spotifyURL:
                    track.spotifyURL,
                title:
                    track.name,
                artist:
                    track.artist,
                album:
                    track.album,
                artworkURL:
                    track.artworkURL,
                youtubeURL:
                    nil,
                permissionConfirmed:
                    true
            )
        )


        startIfNeeded()
    }


    // MARK: - Remove

func remove(
    _ item: FetchItem
) {

    switch item.status {

    case .failed,
         .completed:

        FetchDownloadEngine.shared
            .removeRecords(
                spotifyURL:
                    item.spotifyURL,
                title:
                    item.title
            )


    default:

        break
    }


    items.removeAll {

        $0.id ==
            item.id
    }
}


  func clearCompleted() {

    let removableItems =
        items.filter {
            item in


            switch item.status {

            case .completed,
                 .failed:

                return true


            default:

                return false
            }
        }


    for item in removableItems {

        FetchDownloadEngine.shared
            .removeRecords(
                spotifyURL:
                    item.spotifyURL,
                title:
                    item.title
            )
    }


    items.removeAll {
        item in


        switch item.status {

        case .completed,
             .failed:

            return true


        default:

            return false
        }
    }
}


    // MARK: - Queue

    private func startIfNeeded() {

        guard !running else {

            return
        }


        guard hasQueuedItems else {

            return
        }


        running =
            true


        Task {

            await processQueue()


            running =
                false


            if hasQueuedItems {

                startIfNeeded()
            }
        }
    }


    private var hasQueuedItems:
        Bool {

        items.contains {
            item in


            if case .queued =
                item.status {

                return true
            }


            return false
        }
    }


    // MARK: - Parallel Queue
    //
    // Two workers are allowed to resolve and
    // download simultaneously.

    private func processQueue()
        async {

        async let worker1:
            Void =
            processQueueWorker()


        async let worker2:
            Void =
            processQueueWorker()


        _ =
            await (
                worker1,
                worker2
            )
    }


    private func processQueueWorker()
        async {

        while let next =
            claimNextQueuedItem() {

            await process(
                next
            )
        }
    }


    // MainActor makes this operation atomic
    // with respect to the second worker.

    private func claimNextQueuedItem()
        -> FetchItem? {

        guard let next =
            items.first(
                where: {
                    item in


                    if case .queued =
                        item.status {

                        return true
                    }


                    return false
                }
            )
        else {

            return nil
        }


        // Claim immediately.

        next.status =
            .preparing(
                0.02
            )


        return next
    }


    // MARK: - Process

    private func process(
        _ item: FetchItem
    ) async {

        item.status =
            .preparing(
                0.02
            )


        do {

            let method =
                ApifySettings.shared
                    .downloadMethod


            let downloadResult:
                FetchAudioResult


            item.status =
                .preparing(
                    0.05
                )


            switch method {

            // MARK: Apify

            case .youtube:

                guard let youtubeURL =
                    item.youtubeURL
                else {

                    throw
                        ApifyDownloadError
                            .invalidURL
                }


                item.status =
                    .preparing(
                        0.07
                    )


                let result =
                    try await
                    ApifyAudioSource.shared
                        .resolveMP3(
                            youtubeURL:
                                youtubeURL,
                            permissionConfirmed:
                                item.permissionConfirmed
                        )


                downloadResult =
                    FetchAudioResult(
                        downloadURL:
                            result.downloadURL,
                        suggestedFileName:
                            makeTemporaryApifyName(
                                item:
                                    item
                            )
                    )


            // MARK: yt-dlp

            case .spotify:

                item.status =
                    .preparing(
                        0.07
                    )


                downloadResult =
                    try await
                    YTDLPAudioSource.shared
                        .resolve(
                            item:
                                item
                        )
            }


            item.status =
                .preparing(
                    0.10
                )


            // MARK: HTTP Download
            // 10 - 60%

            let downloadedFile =
                try await
                FetchDownloadEngine.shared
                    .download(
                        item:
                            item,
                        result:
                            downloadResult
                    ) {
                        localProgress in


                        let overall =
                            0.10
                            +
                            (
                                localProgress
                                *
                                0.50
                            )


                        item.status =
                            .downloading(
                                overall
                            )
                    }


            // File has arrived.
            // It may now have to wait briefly for
            // the single MP3 encoder.

            item.status =
                .processing(
                    0.60
                )


            // MARK: Single Encoder Gate

            await FetchEncodingGate.shared
                .acquire()


            let processedAudio:
                FetchProcessedAudio


            do {

                processedAudio =
                    try await
                    FetchAudioProcessor.shared
                        .process(
                            sourceURL:
                                downloadedFile,
                            item:
                                item,
                            quality:
                                FetchSettings.shared
                                    .quality
                        ) {
                            localProgress in


                            let overall =
                                0.60
                                +
                                (
                                    localProgress
                                    *
                                    0.35
                                )


                            item.status =
                                .processing(
                                    overall
                                )
                        }


                await FetchEncodingGate.shared
                    .release()


            } catch {

                await FetchEncodingGate.shared
                    .release()


                throw error
            }


            // MARK: Remove Temporary Source

            if downloadedFile !=
                processedAudio.fileURL {

                FetchDownloadEngine.shared
                    .markSourceConsumed(
                        downloadedFile
                    )
            }


            // MARK: Library
            // 95 - 100%

            item.status =
                .processing(
                    0.96
                )


            MusicLibraryManager.shared
                .addProcessedFetch(
                    fileURL:
                        processedAudio.fileURL,
                    title:
                        processedAudio.title,
                    artist:
                        processedAudio.artist,
                    album:
                        processedAudio.album,
                    coverData:
                        processedAudio.artworkData
                )


            item.status =
                .processing(
                    0.99
                )


            NotificationCenter.default
                .post(
                    name:
                        .echoFetchCompleted,
                    object:
                        nil
                )


            item.status =
                .completed


            print(
                "FETCH COMPLETE:",
                processedAudio.title
            )


        } catch {

            item.status =
                .failed(
                    error.localizedDescription
                )


            print(
                "FETCH FAILED:",
                item.title,
                error
            )
        }
    }


    // MARK: - Apify Temp Filename

    private func makeTemporaryApifyName(
        item: FetchItem
    ) -> String {

        let illegal =
            CharacterSet(
                charactersIn:
                    "/\\:*?\"<>|"
            )


        let base =
            "\(item.title) - \(item.artist)"


        let cleaned =
            base
                .components(
                    separatedBy:
                        illegal
                )
                .joined(
                    separator:
                        ""
                )


        return
            "\(cleaned)-apify-source.mp3"
    }


    // MARK: - Default Title

    private func defaultTitle(
        for type: SpotifyContentType
    ) -> String {

        switch type {

        case .track:

            return "Spotify Track"


        case .album:

            return "Spotify Album"


        case .playlist:

            return "Spotify Playlist"
        }
    }


    // MARK: - Background Recovery

    func restoreBackgroundDownloads()
        async {

        guard !backgroundRecoveryRunning
        else {

            return
        }


        backgroundRecoveryRunning =
            true


        defer {

            backgroundRecoveryRunning =
                false
        }


        let records =
            FetchDownloadEngine.shared
                .recoveryRecords()


        for record in records {

            if restoredBackgroundIDs
                .contains(
                    record.id
                ) {

                continue
            }


            guard let item =
                makeRecoveredItem(
                    from:
                        record
                )
            else {

                continue
            }


            restoredBackgroundIDs.insert(
                record.id
            )


            items.append(
                item
            )


            if let error =
                record.errorMessage {

                item.status =
                    .failed(
                        error
                    )


                continue
            }


            if
                record.completed,
                let path =
                    record.localFilePath {

                let source =
                    URL(
                        fileURLWithPath:
                            path
                    )


                guard FileManager.default
                    .fileExists(
                        atPath:
                            source.path
                    )
                else {

                    item.status =
                        .failed(
                            "Downloaded source file is missing."
                        )


                    continue
                }


                item.status =
                    .processing(
                        0.60
                    )


                await processRecoveredSource(
                    source,
                    item:
                        item,
                    recordID:
                        record.id
                )


            } else {

                item.status =
                    .downloading(
                        0.10
                    )
            }
        }
    }


    // MARK: - Restored Progress

    private func updateRestoredBackgroundProgress(
        id: UUID,
        progress: Double
    ) {

        guard
            let record =
                FetchDownloadEngine.shared
                    .recoveryRecords()
                    .first(
                        where: {

                            $0.id ==
                                id
                        }
                    )
        else {

            return
        }


        guard
            let item =
                findRecoveredItem(
                    record:
                        record
                )
        else {

            return
        }


        let overall =
            0.10
            +
            (
                progress
                *
                0.50
            )


        item.status =
            .downloading(
                overall
            )
    }


    // MARK: - Background Transfer Finished

    private func backgroundTransferFinished(
        _ record: BackgroundFetchRecord
    ) {

        guard UIApplication.shared
            .applicationState ==
            .active
        else {

            return
        }


        guard let path =
            record.localFilePath
        else {

            return
        }


        let source =
            URL(
                fileURLWithPath:
                    path
            )


        let item:
            FetchItem


        if let existing =
            findRecoveredItem(
                record:
                    record
            ) {

            item =
                existing

        } else {

            guard let created =
                makeRecoveredItem(
                    from:
                        record
                )
            else {

                return
            }


            restoredBackgroundIDs.insert(
                record.id
            )


            items.append(
                created
            )


            item =
                created
        }


        item.status =
            .processing(
                0.60
            )


        Task {

            await processRecoveredSource(
                source,
                item:
                    item,
                recordID:
                    record.id
            )
        }
    }


    // MARK: - Recovered Source Processing

    private func processRecoveredSource(
        _ sourceURL: URL,
        item: FetchItem,
        recordID: UUID
    ) async {

        do {

            // Recovered downloads use the exact same
            // single-encoder gate as normal downloads.

            await FetchEncodingGate.shared
                .acquire()


            let processed:
                FetchProcessedAudio


            do {

                processed =
                    try await
                    FetchAudioProcessor.shared
                        .process(
                            sourceURL:
                                sourceURL,
                            item:
                                item,
                            quality:
                                FetchSettings.shared
                                    .quality
                        ) {
                            progress in


                            item.status =
                                .processing(
                                    0.60
                                    +
                                    (
                                        progress
                                        *
                                        0.35
                                    )
                                )
                        }


                await FetchEncodingGate.shared
                    .release()


            } catch {

                await FetchEncodingGate.shared
                    .release()


                throw error
            }


            item.status =
                .processing(
                    0.96
                )


            MusicLibraryManager.shared
                .addProcessedFetch(
                    fileURL:
                        processed.fileURL,
                    title:
                        processed.title,
                    artist:
                        processed.artist,
                    album:
                        processed.album,
                    coverData:
                        processed.artworkData
                )


            item.status =
                .processing(
                    0.99
                )


            FetchDownloadEngine.shared
                .markRecordConsumed(
                    id:
                        recordID
                )


            item.status =
                .completed


            NotificationCenter.default
                .post(
                    name:
                        .echoFetchCompleted,
                    object:
                        nil
                )


            print(
                "RECOVERED FETCH COMPLETE:",
                processed.title
            )


        } catch {

            item.status =
                .failed(
                    error.localizedDescription
                )


            print(
                "RECOVERED FETCH FAILED:",
                item.title,
                error
            )
        }
    }


    // MARK: - Make Recovered Item

    private func makeRecoveredItem(
        from record: BackgroundFetchRecord
    ) -> FetchItem? {

        guard let spotifyURL =
            URL(
                string:
                    record.spotifyURL
            )
        else {

            return nil
        }


        let artworkURL:
            URL?


        if let string =
            record.artworkURL {

            artworkURL =
                URL(
                    string:
                        string
                )

        } else {

            artworkURL =
                nil
        }


        let youtubeURL:
            URL?


        if let string =
            record.youtubeURL {

            youtubeURL =
                URL(
                    string:
                        string
                )

        } else {

            youtubeURL =
                nil
        }


        return FetchItem(
            spotifyURL:
                spotifyURL,
            title:
                record.title,
            artist:
                record.artist,
            album:
                record.album,
            artworkURL:
                artworkURL,
            youtubeURL:
                youtubeURL,
            permissionConfirmed:
                record.permissionConfirmed
        )
    }


    // MARK: - Find Recovered Item

    private func findRecoveredItem(
        record: BackgroundFetchRecord
    ) -> FetchItem? {

        items.first {

            $0.spotifyURL.absoluteString ==
                record.spotifyURL
            &&
            $0.title ==
                record.title
        }
    }
}
