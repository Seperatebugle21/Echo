import Foundation
import PythonKit
import YoutubeDL


// MARK: - Python serial executor

final class YTDLPPythonSerialExecutor:
    SerialExecutor,
    @unchecked Sendable {

    private let queue =
        DispatchQueue(
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


// MARK: - Python Runner

actor YTDLPRunner {

    static let shared =
        YTDLPRunner()


    // MARK: Executor

    private nonisolated let executor =
        YTDLPPythonSerialExecutor()

    nonisolated
    var unownedExecutor:
        UnownedSerialExecutor {

        executor
            .asUnownedSerialExecutor()
    }


    // MARK: Queue

    private typealias Job =
        @Sendable () async -> Void

    private var queue: [Job] = []

    private var isRunning =
        false


    private init() {}


    // MARK: - Public extract

    func extract(
        url: URL
    ) async throws -> Result {

        try await runIsolated {

            Self.stage(
                "PYTHON 1 - job started"
            )


            // -----------------------------------------------------
            // IMPORTANT
            //
            // Do NOT call PythonSupport.initialize().
            //
            // YtDlp() does the initialization internally,
            // exactly like FreeTube.
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
            // First PythonKit access
            //
            // This is the point that crashed before.
            // But now it happens inside the same queued Python job
            // after YtDlp initialized the runtime.
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
            // yt-dlp options
            // -----------------------------------------------------

            var options =
                PythonObject(
                    [:]
                        as
                    [String: PythonObject]
                )


            options["noplaylist"] =
                true

            options["nocheckcertificate"] =
                true

            options["quiet"] =
                true

            options["no_warnings"] =
                true

            options["socket_timeout"] =
                30.0


            // Critical on iOS:
            //
            // Don't let yt-dlp try to start a real ffmpeg
            // subprocess during its format probe.

            options["ffmpeg_location"] =
                PythonObject(
                    "/dev/null/no-ffmpeg"
                )


            Self.stage(
                "PYTHON 6 - options created"
            )


            // -----------------------------------------------------
            // Create yt_dlp.YoutubeDL
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
            // IMPORTANT:
            //
            // Every PythonObject must be converted HERE.
            //
            // Never return PythonObject outside the Python job.
            //
            // FreeTube explicitly does the same thing.
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

                    let formatID =
                        format
                            .checking["format_id"]
                            .flatMap(
                                String.init
                            )


                    let directURL =
                        format
                            .checking["url"]
                            .flatMap(
                                String.init
                            )


                    let extensionName =
                        format
                            .checking["ext"]
                            .flatMap(
                                String.init
                            )


                    let audioCodecRaw =
                        format
                            .checking["acodec"]
                            .flatMap(
                                String.init
                            )
                        ?? ""


                    let videoCodecRaw =
                        format
                            .checking["vcodec"]
                            .flatMap(
                                String.init
                            )
                        ?? ""


                    let bitrate =
                        format
                            .checking["abr"]
                            .flatMap(
                                Double.init
                            )


                    let hasAudio =
                        !audioCodecRaw.isEmpty
                        &&
                        audioCodecRaw != "none"


                    let hasVideo =
                        !videoCodecRaw.isEmpty
                        &&
                        videoCodecRaw != "none"


                    // audio-only

                    guard
                        hasAudio,
                        !hasVideo
                    else {

                        continue
                    }


                    audioCount += 1


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


            let version =
                String(
                    module
                        .version
                        .__version__
                )


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


    // MARK: - Isolated Python job

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


            // Exact FreeTube principle:
            //
            // Python job is detached from caller/main actor
            // and all jobs execute strictly one-by-one.

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


    // MARK: - Persistent diagnostics

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
