import Foundation
import YoutubeDL


// MARK: - Python Serial Executor

final class YTDLPSerialExecutor:
    SerialExecutor,
    @unchecked Sendable {

    static let shared =
        YTDLPSerialExecutor()

    private let queue =
        DispatchQueue(
            label:
                "com.echomusic.ytdlp.python",
            qos:
                .utility
        )

    private init() {}

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
}


// MARK: - YTDLP Runner

actor YTDLPRunner {

    static let shared =
        YTDLPRunner()


    // Everything inside this actor runs through
    // our serial Python executor.

    nonisolated
    var unownedExecutor:
        UnownedSerialExecutor {

        YTDLPSerialExecutor
            .shared
            .asUnownedSerialExecutor()
    }


    private let engine =
        YoutubeDL()


    private init() {}


    // MARK: - Extraction

    func extract(
        url: URL
    ) throws -> Result {

        // IMPORTANT:
        //
        // This is synchronous.
        //
        // There is NO await between:
        //
        // Python initialize
        // -> import yt_dlp
        // -> YoutubeDL()
        // -> extract_info()
        // -> decode result

        let (
            formats,
            info
        ) =
            try engine
                .extractInfoPinned(
                    url: url
                )


        // Audio-only formats

        let audioFormats =
            formats.filter {

                $0.isAudioOnly
            }


        // Highest audio bitrate

        let bestAudio =
            audioFormats.max {

                ($0.abr ?? 0)
                <
                ($1.abr ?? 0)
            }


        return Result(

            title:
                info.title,

            uploader:
                info.uploader
                ?? info.channel,

            duration:
                info.duration,

            formatsCount:
                formats.count,

            audioFormatsCount:
                audioFormats.count,

            formatID:
                bestAudio?.format_id,

            fileExtension:
                bestAudio?.ext,

            audioCodec:
                bestAudio?.acodec,

            bitrate:
                bestAudio?.abr,

            directURL:
                bestAudio?.url,

            ytdlpVersion:
                engine.version
        )
    }


    // MARK: - Result

    struct Result: Sendable {

        let title: String

        let uploader: String?

        let duration: Double?

        let formatsCount: Int

        let audioFormatsCount: Int

        let formatID: String?

        let fileExtension: String?

        let audioCodec: String?

        let bitrate: Double?

        let directURL: String?

        let ytdlpVersion: String?
    }
}
