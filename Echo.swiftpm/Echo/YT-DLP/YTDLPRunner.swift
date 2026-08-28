import Foundation
import PythonKit
import YoutubeDL


// MARK: - Python Serial Executor

final class YTDLPPythonSerialExecutor:
    SerialExecutor,
    @unchecked Sendable {

    private let queue = DispatchQueue(
        label: "com.echomusic.python",
        qos: .utility
    )

    func enqueue(
        _ job: UnownedJob
    ) {

        let executor =
            asUnownedSerialExecutor()

        queue.async {

            job.runSynchronously(
                on: executor
            )
        }
    }

    func asUnownedSerialExecutor()
        -> UnownedSerialExecutor {

        UnownedSerialExecutor(
            ordinary: self
        )
    }
}


// MARK: - YTDLP Runner

actor YTDLPRunner {

    static let shared =
        YTDLPRunner()


    // MARK: - Executor

    private nonisolated let executor =
        YTDLPPythonSerialExecutor()

    nonisolated
    var unownedExecutor:
        UnownedSerialExecutor {

        executor
            .asUnownedSerialExecutor()
    }


    // MARK: - Queue

    private typealias Job =
        @Sendable () async -> Void

    private var queue: [Job] = []

    private var isRunning =
        false


    private init() {}


    // MARK: - Extract

    func extract(
        url: URL
    ) async throws -> Result {

        try await runIsolated {

            Self.stage(
                "PYTHON 1 - job started"
            )


            // -----------------------------------------------------
            // YtDlp initialization
            //
            // IMPORTANT:
            // Do NOT call PythonSupport.initialize() ourselves.
            //
            // YtDlp() initializes the embedded Python environment.
            // -----------------------------------------------------

            Self.stage(
                "PYTHON 2 - before YtDlp()"
            )

            let _ =
                try await YtDlp()

            Self.stage(
                "PYTHON 3 - YtDlp ready"
            )


            // -----------------------------------------------------
            // Import yt-dlp
            // -----------------------------------------------------

            Self.stage(
                "PYTHON 4 - before import yt_dlp"
            )

            let module =
                try Python.attemptImport(
                    "yt_dlp"
                )

            Self.stage(
                "PYTHON 5 - yt_dlp imported"
            )


            // -----------------------------------------------------
            // Options
            // -----------------------------------------------------

            var options =
                PythonObject(
                    [:]
                        as
                    [String: PythonObject]
                )


            // Single video only

            options["noplaylist"] =
                true


            // Certificate handling

            options["nocheckcertificate"] =
                true


            // Keep Python output quiet for now

            options["quiet"] =
                true

            options["no_warnings"] =
                true


            // Prevent endless network waits

            options["socket_timeout"] =
                30.0


            // IMPORTANT:
            //
            // Do not allow yt-dlp to attempt to spawn a normal
            // ffmpeg subprocess on iOS.
            //
            // We will handle audio conversion ourselves later.

            options["ffmpeg_location"] =
                PythonObject(
                    "/dev/null/no-ffmpeg"
                )


            Self.stage(
                "PYTHON 6 - options created"
            )


            // -----------------------------------------------------
            // Create Python yt_dlp.YoutubeDL
            // -----------------------------------------------------

            Self.stage(
                "PYTHON 7 - before YoutubeDL()"
            )

            let ydl =
                module.YoutubeDL(
                    options
                )

            Self.stage(
                "PYTHON 8 - YoutubeDL ready"
            )


            // -----------------------------------------------------
            // extract_info
            // -----------------------------------------------------

            Self.stage(
                "PYTHON 9 - before extract_info"
            )

            let info =
                try ydl
                    .extract_info
                    .throwing
                    .dynamicallyCall(
                        withArguments: [
                            url.absoluteString,
                            false
                        ]
                    )

            Self.stage(
                "PYTHON 10 - extract_info returned"
            )


            // -----------------------------------------------------
            // Metadata
            //
            // IMPORTANT:
            // Convert every PythonObject to a native Swift type
            // while we're still inside this Python job.
            // -----------------------------------------------------

            let title =
                info
                    .checking["title"]
                    .flatMap(
                        String.init
                    )
                ?? "Onbekend"


            let uploader =
                info
                    .checking["uploader"]
                    .flatMap(
                        String.init
                    )
                ??
                info
                    .checking["channel"]
                    .flatMap(
                        String.init
                    )


            let duration =
                info
                    .checking["duration"]
                    .flatMap(
                        Double.init
                    )


            Self.stage(
                "PYTHON 11 - metadata converted"
            )


            // -----------------------------------------------------
            // Formats
            // -----------------------------------------------------

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


            if let formatsObject =
                info.checking["formats"] {

                let formats:
                    [PythonObject] =
                    Array(
                        formatsObject
                    )


                formatCount =
                    formats.count


                for format in formats {

                    // ---------------------------------------------
                    // Format ID
                    // ---------------------------------------------

                    let formatID =
                        format
                            .checking["format_id"]
                            .flatMap(
                                String.init
                            )


                    // ---------------------------------------------
                    // Direct media URL
                    // ---------------------------------------------

                    let directURL =
                        format
                            .checking["url"]
                            .flatMap(
                                String.init
                            )


                    // ---------------------------------------------
                    // File extension
                    // ---------------------------------------------

                    let extensionName =
                        format
                            .checking["ext"]
                            .flatMap(
                                String.init
                            )


                    // ---------------------------------------------
                    // Audio codec
                    // ---------------------------------------------

                    let audioCodecRaw =
                        format
                            .checking["acodec"]
                            .flatMap(
                                String.init
                            )
                        ?? ""


                    // ---------------------------------------------
                    // Video codec
                    // ---------------------------------------------

                    let videoCodecRaw =
                        format
                            .checking["vcodec"]
                            .flatMap(
                                String.init
                            )
                        ?? ""


                    // ---------------------------------------------
                    // Audio bitrate
                    // ---------------------------------------------

                    let bitrate =
                        format
                            .checking["abr"]
                            .flatMap(
                                Double.init
                            )


                    // ---------------------------------------------
                    // Determine audio/video
                    // ---------------------------------------------

                    let hasAudio =
                        !audioCodecRaw.isEmpty
                        &&
                        audioCodecRaw != "none"


                    let hasVideo =
                        !videoCodecRaw.isEmpty
                        &&
                        videoCodecRaw != "none"


                    // We only want audio-only formats.

                    guard
                        hasAudio,
                        !hasVideo
                    else {

                        continue
                    }


                    audioCount += 1


                    // ---------------------------------------------
                    // Pick highest bitrate
                    // ---------------------------------------------

                    let currentBitrate =
                        bitrate ?? 0

                    let previousBitrate =
                        bestBitrate ?? -1


                    if currentBitrate
                        >
                        previousBitrate {

                        bestBitrate =
                            bitrate

                        bestFormatID =
                            formatID

                        bestURL =
                            directURL

                        bestExtension =
                            extensionName

                        bestCodec =
                            audioCodecRaw
                    }
                }
            }


            Self.stage(
                "PYTHON 12 - formats converted"
            )


            // -----------------------------------------------------
            // yt-dlp version
            // -----------------------------------------------------

            let version =
                String(
                    module
                        .version
                        .__version__
                )
                ?? "unknown"


            Self.stage(
                "PYTHON 13 - COMPLETE"
            )


            // -----------------------------------------------------
            // Return ONLY native Swift values.
            //
            // No PythonObject leaves this closure.
            // -----------------------------------------------------

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


    // MARK: - Run Isolated

    func runIsolated<T: Sendable>(
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
                            try await work()

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

                    await self.pump()
                }
            }
    }


    // MARK: - Pump

    @_optimize(none)
    private func pump() async {

        guard !isRunning else {

            return
        }


        isRunning =
            true


        defer {

            isRunning =
                false
        }


        while !queue.isEmpty {

            let job =
                queue.removeFirst()


            // Run the complete Python operation detached
            // from the caller / MainActor.
            //
            // We wait for it to COMPLETELY finish before
            // allowing the next Python job to start.

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


    // MARK: - Persistent Diagnostics

    nonisolated
    private static func stage(
        _ value: String
    ) {

        UserDefaults.standard.set(
            value,
            forKey:
                "ytdlpLastStage"
        )

        UserDefaults.standard
            .synchronize()
    }


    // MARK: - Result

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
