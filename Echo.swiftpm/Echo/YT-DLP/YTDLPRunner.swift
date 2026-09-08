import Foundation
import PythonKit
import YoutubeDL


// MARK: - Python Serial Executor

final class YTDLPPythonSerialExecutor:
    SerialExecutor,
    @unchecked Sendable {

    private let queue =
        DispatchQueue(
            label:
                "com.echomusic.python",
            qos:
                .utility
        )


    func enqueue(
        _ job: UnownedJob
    ) {

        let executor =
            asUnownedSerialExecutor()


        queue.async {

            job.runSynchronously(
                on:
                    executor
            )
        }
    }


    func asUnownedSerialExecutor()
        -> UnownedSerialExecutor {

        UnownedSerialExecutor(
            ordinary:
                self
        )
    }
}


// MARK: - YTDLP Runner

actor YTDLPRunner {

    static let shared =
        YTDLPRunner()


    private nonisolated let executor =
        YTDLPPythonSerialExecutor()


    nonisolated
    var unownedExecutor:
        UnownedSerialExecutor {

        executor
            .asUnownedSerialExecutor()
    }


    private typealias Job =
        @Sendable
        () async -> Void


    private var queue:
        [Job] = []


    private var isRunning =
        false


    private init() {}


    // MARK: - Module management

    func installedVersion()
        async throws -> String?
    {

        guard FileManager.default
            .fileExists(
                atPath:
                    YoutubeDL
                        .pythonModuleURL
                        .path
            )
        else {
            return nil
        }


        return try await runIsolated {

            let _ =
                try await
                YtDlp()


            let module =
                try Python.attemptImport(
                    "yt_dlp"
                )


            return String(
                module
                    .version
                    .__version__
            )
        }
    }


    func installLatestVersion()
        async throws
    {

        try await runIsolated {

            try await YoutubeDL
                .downloadPythonModule()
        }
    }


    // MARK: - Search YouTube

    func search(
        title: String,
        artist: String
    ) async throws -> SearchResult {

        let cleanedTitle =
            title
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        let cleanedArtist =
            artist
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        let query =
            "\(cleanedTitle) \(cleanedArtist) audio"


        return try await runIsolated {

            Self.stage(
                "PYTHON SEARCH 1 - started"
            )


            // Make sure embedded Python / yt-dlp
            // has been initialized.

            let _ =
                try await
                YtDlp()


            Self.stage(
                "PYTHON SEARCH 2 - YtDlp ready"
            )


            let module =
                try Python.attemptImport(
                    "yt_dlp"
                )


            Self.stage(
                "PYTHON SEARCH 3 - module imported"
            )


            // =====================================
            // Search options
            // =====================================

            let options =
                PythonObject(
                    [:]
                        as
                    [String: PythonObject]
                )


            options[
                "quiet"
            ] =
                true


            options[
                "no_warnings"
            ] =
                true


            options[
                "nocheckcertificate"
            ] =
                true


            options[
                "socket_timeout"
            ] =
                30.0


            // We only want the search result here.
            // The actual media extraction happens
            // afterwards in extract(url:).

            options[
                "extract_flat"
            ] =
                true


            options[
                "skip_download"
            ] =
                true


            options[
                "noplaylist"
            ] =
                false


            let ydl =
                module.YoutubeDL(
                    options
                )


            Self.stage(
                "PYTHON SEARCH 4 - YoutubeDL ready"
            )


            // =====================================
            // ytsearch1:
            //
            // Ask yt-dlp for only the first result.
            // =====================================

            let searchValue =
                "ytsearch1:\(query)"


            let info =
                try ydl
                    .extract_info
                    .throwing
                    .dynamicallyCall(
                        withArguments: [
                            searchValue,
                            false
                        ]
                    )


            Self.stage(
                "PYTHON SEARCH 5 - search returned"
            )


            // =====================================
            // Entries
            // =====================================

            guard let entriesObject =
                info.checking[
                    "entries"
                ]
            else {

                throw YTDLPRunnerError
                    .noSearchResult
            }


            let entries:
                [PythonObject] =
                Array(
                    entriesObject
                )


            guard let first =
                entries.first
            else {

                throw YTDLPRunnerError
                    .noSearchResult
            }


            // =====================================
            // Video ID
            // =====================================

            let videoID =
                first
                    .checking[
                        "id"
                    ]
                    .flatMap(
                        String.init
                    )


            // =====================================
            // Title
            // =====================================

            let resultTitle =
                first
                    .checking[
                        "title"
                    ]
                    .flatMap(
                        String.init
                    )
                ??
                cleanedTitle


            // =====================================
            // Uploader / channel
            // =====================================

            let uploader =
                first
                    .checking[
                        "uploader"
                    ]
                    .flatMap(
                        String.init
                    )
                ??
                first
                    .checking[
                        "channel"
                    ]
                    .flatMap(
                        String.init
                    )


            // =====================================
            // URL
            // =====================================

            var videoURL:
                URL?


            if let webpage =
                first
                    .checking[
                        "webpage_url"
                    ]
                    .flatMap(
                        String.init
                    ) {

                videoURL =
                    URL(
                        string:
                            webpage
                    )
            }


            if videoURL == nil,
               let originalURL =
                first
                    .checking[
                        "url"
                    ]
                    .flatMap(
                        String.init
                    ),
               originalURL.hasPrefix(
                    "http"
               ) {

                videoURL =
                    URL(
                        string:
                            originalURL
                    )
            }


            // extract_flat commonly gives us the
            // video ID instead of the complete URL.

            if videoURL == nil,
               let videoID,
               !videoID.isEmpty {

                videoURL =
                    URL(
                        string:
                            "https://www.youtube.com/watch?v=\(videoID)"
                    )
            }


            guard let videoURL else {

                throw YTDLPRunnerError
                    .invalidSearchResult
            }


            Self.stage(
                "PYTHON SEARCH 6 - COMPLETE"
            )


            return SearchResult(
                title:
                    resultTitle,

                uploader:
                    uploader,

                videoID:
                    videoID,

                videoURL:
                    videoURL
            )
        }
    }


    // MARK: - Extract

    func extract(
        url: URL
    ) async throws -> Result {

        try await runIsolated {

            Self.stage(
                "PYTHON 1 - job started"
            )


            // =====================================
            // Initialize YtDlp / Python
            // =====================================

            Self.stage(
                "PYTHON 2 - before YtDlp()"
            )


            let _ =
                try await
                YtDlp()


            Self.stage(
                "PYTHON 3 - YtDlp ready"
            )


            // =====================================
            // Import module
            // =====================================

            let module =
                try Python.attemptImport(
                    "yt_dlp"
                )


            Self.stage(
                "PYTHON 5 - yt_dlp imported"
            )


            // =====================================
            // Options
            // =====================================

            let options =
                PythonObject(
                    [:]
                        as
                    [String: PythonObject]
                )


            options[
                "noplaylist"
            ] =
                true


            options[
                "nocheckcertificate"
            ] =
                true


            options[
                "quiet"
            ] =
                true


            options[
                "no_warnings"
            ] =
                true


            options[
                "socket_timeout"
            ] =
                30.0


            // Do not spawn ffmpeg subprocess.

            options[
                "ffmpeg_location"
            ] =
                PythonObject(
                    "/dev/null/no-ffmpeg"
                )


            Self.stage(
                "PYTHON 6 - options created"
            )


            // =====================================
            // YoutubeDL object
            // =====================================

            let ydl =
                module.YoutubeDL(
                    options
                )


            Self.stage(
                "PYTHON 8 - YoutubeDL ready"
            )


            // =====================================
            // Extract
            // =====================================

            let info =
                try ydl
                    .extract_info
                    .throwing
                    .dynamicallyCall(

                        withArguments: [

                            url
                                .absoluteString,

                            false
                        ]
                    )


            Self.stage(
                "PYTHON 10 - extract_info returned"
            )


            // =====================================
            // Metadata
            // =====================================

            let title =
                info
                    .checking[
                        "title"
                    ]
                    .flatMap(
                        String.init
                    )
                ??
                "Onbekend"


            let uploader =
                info
                    .checking[
                        "uploader"
                    ]
                    .flatMap(
                        String.init
                    )
                ??
                info
                    .checking[
                        "channel"
                    ]
                    .flatMap(
                        String.init
                    )


            let duration =
                info
                    .checking[
                        "duration"
                    ]
                    .flatMap(
                        Double.init
                    )


            // =====================================
            // Formats
            // =====================================

            var formatCount =
                0


            var audioCount =
                0


            var bestFormatID:
                String?


            var bestURL:
                String?


            var bestExtension:
                String?


            var bestCodec:
                String?


            var bestBitrate:
                Double?


            var bestCompatibilityScore =
                -1


            if let formatsObject =
                info
                    .checking[
                        "formats"
                    ] {

                let formats:
                    [PythonObject] =
                    Array(
                        formatsObject
                    )


                formatCount =
                    formats.count


                for format
                    in formats {

                    let formatID =
                        format
                            .checking[
                                "format_id"
                            ]
                            .flatMap(
                                String.init
                            )


                    let directURL =
                        format
                            .checking[
                                "url"
                            ]
                            .flatMap(
                                String.init
                            )


                    let extensionName =
                        format
                            .checking[
                                "ext"
                            ]
                            .flatMap(
                                String.init
                            )?
                            .lowercased()


                    let audioCodec =
                        format
                            .checking[
                                "acodec"
                            ]
                            .flatMap(
                                String.init
                            )
                        ??
                        ""


                    let videoCodec =
                        format
                            .checking[
                                "vcodec"
                            ]
                            .flatMap(
                                String.init
                            )
                        ??
                        ""


                    let bitrate =
                        format
                            .checking[
                                "abr"
                            ]
                            .flatMap(
                                Double.init
                            )


                    let hasAudio =
                        !audioCodec
                            .isEmpty
                        &&
                        audioCodec !=
                        "none"


                    let hasVideo =
                        !videoCodec
                            .isEmpty
                        &&
                        videoCodec !=
                        "none"


                    guard
                        hasAudio,
                        !hasVideo,
                        directURL != nil
                    else {

                        continue
                    }


                    audioCount +=
                        1


                    // =================================
                    // Prefer formats AVFoundation
                    // handles well on iOS.
                    // =================================

                    let compatibilityScore:
                        Int


                    switch extensionName {

                    case "m4a",
                         "mp4":

                        compatibilityScore =
                            3


                    case "aac":

                        compatibilityScore =
                            2


                    case "webm",
                         "opus",
                         "ogg":

                        compatibilityScore =
                            1


                    default:

                        compatibilityScore =
                            0
                    }


                    let currentBitrate =
                        bitrate ??
                        0


                    let previousBitrate =
                        bestBitrate ??
                        -1


                    let shouldReplace:
                        Bool


                    if compatibilityScore >
                        bestCompatibilityScore {

                        shouldReplace =
                            true


                    } else if
                        compatibilityScore ==
                            bestCompatibilityScore,
                        currentBitrate >
                            previousBitrate {

                        shouldReplace =
                            true


                    } else {

                        shouldReplace =
                            false
                    }


                    if shouldReplace {

                        bestCompatibilityScore =
                            compatibilityScore


                        bestFormatID =
                            formatID


                        bestURL =
                            directURL


                        bestExtension =
                            extensionName


                        bestCodec =
                            audioCodec


                        bestBitrate =
                            bitrate
                    }
                }
            }


            Self.stage(
                "PYTHON 12 - formats converted"
            )


            guard bestURL !=
                    nil
            else {

                throw YTDLPRunnerError
                    .noAudioFormat
            }


            let version =
                String(
                    module
                        .version
                        .__version__
                )
                ??
                "unknown"


            Self.stage(
                "PYTHON 13 - COMPLETE"
            )


            return Result(

                title:
                    title,

                uploader:
                    uploader,

                duration:
                    duration,

                formatCount:
                    formatCount,

                audioFormatCount:
                    audioCount,

                formatID:
                    bestFormatID,

                fileExtension:
                    bestExtension,

                audioCodec:
                    bestCodec,

                bitrate:
                    bestBitrate,

                directURL:
                    bestURL,

                ytdlpVersion:
                    version
            )
        }
    }


    // MARK: - Run isolated

    func runIsolated<
        T: Sendable
    >(
        _ work:
            @Sendable
            @escaping
            () async throws -> T
    ) async throws -> T {

        try await
            withCheckedThrowingContinuation {

                (
                    continuation:
                    CheckedContinuation<
                        T,
                        Error
                    >
                ) in


                let job: Job = {

                    do {

                        let result =
                            try await
                            work()


                        continuation
                            .resume(
                                returning:
                                    result
                            )


                    } catch {

                        continuation
                            .resume(
                                throwing:
                                    error
                            )
                    }
                }


                queue.append(
                    job
                )


                Task {

                    await self
                        .pump()
                }
            }
    }


    // MARK: - Pump

    @_optimize(none)
    private func pump()
        async {

        guard !isRunning else {

            return
        }


        isRunning =
            true


        defer {

            isRunning =
                false
        }


        while !queue
            .isEmpty {

            let job =
                queue
                    .removeFirst()


            let task =
                Task.detached(
                    priority:
                        .utility
                ) {

                    await job()
                }


            _ =
                await task.value
        }
    }


    // MARK: - Diagnostics

    nonisolated
    private static func stage(
        _ value: String
    ) {

        UserDefaults.standard
            .set(
                value,
                forKey:
                    "ytdlpLastStage"
            )


        UserDefaults.standard
            .synchronize()
    }


    // MARK: - Search Result

    struct SearchResult:
        Sendable {

        let title:
            String

        let uploader:
            String?

        let videoID:
            String?

        let videoURL:
            URL
    }


    // MARK: - Extract Result

    struct Result:
        Sendable {

        let title:
            String

        let uploader:
            String?

        let duration:
            Double?

        let formatCount:
            Int

        let audioFormatCount:
            Int

        let formatID:
            String?

        let fileExtension:
            String?

        let audioCodec:
            String?

        let bitrate:
            Double?

        let directURL:
            String?

        let ytdlpVersion:
            String
    }
}


// MARK: - Errors

enum YTDLPRunnerError:
    LocalizedError {

    case noAudioFormat
    case noSearchResult
    case invalidSearchResult


    var errorDescription:
        String? {

        switch self {

        case .noAudioFormat:

            return
                "yt-dlp vond geen bruikbare audio-only stream."


        case .noSearchResult:

            return
                "yt-dlp kon geen overeenkomende YouTube-video vinden."


        case .invalidSearchResult:

            return
                "yt-dlp vond een resultaat, maar kon geen geldige YouTube-URL bepalen."
        }
    }
}
