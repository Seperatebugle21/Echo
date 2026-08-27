import Foundation
import PythonKit
import PythonSupport
import YoutubeDL

final class YTDLPSerialExecutor:
    SerialExecutor,
    @unchecked Sendable {

    static let shared =
        YTDLPSerialExecutor()

    private let queue =
        DispatchQueue(
            label:
                "com.echomusic.python",
            qos:
                .userInitiated
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

    func asUnownedSerialExecutor()
        -> UnownedSerialExecutor {

        UnownedSerialExecutor(
            ordinary: self
        )
    }
}



actor YTDLPRunner {

    static let shared =
        YTDLPRunner()

    nonisolated
    var unownedExecutor:
        UnownedSerialExecutor {

        YTDLPSerialExecutor
            .shared
            .asUnownedSerialExecutor()
    }


    private var pythonStarted =
        false


    private var ytdlp:
        YoutubeDL?


    private init() {}


    // MARK: - Python only test

    func startPython()
        throws
        -> String {

        UserDefaults.standard.set(
            "PYTHON 1 - initialize()",
            forKey:
                "ytdlpLastStage"
        )


        PythonSupport.initialize()


        UserDefaults.standard.set(
            "PYTHON 2 - initialize OK",
            forKey:
                "ytdlpLastStage"
        )


        let sys =
            Python.import("sys")


        UserDefaults.standard.set(
            "PYTHON 3 - sys imported",
            forKey:
                "ytdlpLastStage"
        )


        let version =
            String(
                sys.version
            )


        UserDefaults.standard.set(
            "PYTHON 4 - volledig OK",
            forKey:
                "ytdlpLastStage"
        )


        pythonStarted =
            true


        return version
    }


    // MARK: - yt-dlp object

    func prepareYTDLP() {

        if ytdlp == nil {

            ytdlp =
                YoutubeDL()
        }
    }


    // MARK: - Extract

    func extract(
        url: URL
    ) async throws
        -> YTDLPResult {

        if !pythonStarted {

            _ =
                try startPython()
        }


        if ytdlp == nil {

            prepareYTDLP()
        }


        guard let ytdlp else {

            throw RunnerError
                .engineUnavailable
        }


        UserDefaults.standard.set(
            "YTDLP 1 - extractInfo starten",
            forKey:
                "ytdlpLastStage"
        )


        let (
            formats,
            info
        ) =
            try await ytdlp
                .extractInfo(
                    url: url
                )


        UserDefaults.standard.set(
            "YTDLP 2 - extractInfo OK",
            forKey:
                "ytdlpLastStage"
        )


        let audioFormats =
            formats.filter {

                $0.isAudioOnly
            }


        let bestAudio =
            audioFormats.max {

                ($0.abr ?? 0)
                <
                ($1.abr ?? 0)
            }


        return YTDLPResult(

            title:
                info.title,

            uploader:
                info.uploader,

            duration:
                info.duration,

            formatsCount:
                formats.count,

            audioFormatsCount:
                audioFormats.count,

            formatID:
                bestAudio?.format_id,

            ext:
                bestAudio?.ext,

            codec:
                bestAudio?.acodec,

            bitrate:
                bestAudio?.abr,

            directURL:
                bestAudio?.url
        )
    }


    enum RunnerError:
        LocalizedError {

        case engineUnavailable

        var errorDescription:
            String? {

            switch self {

            case .engineUnavailable:

                return
                    "YoutubeDL engine unavailable"
            }
        }
    }
}



struct YTDLPResult:
    Sendable {

    let title: String

    let uploader: String?

    let duration: Double?

    let formatsCount: Int

    let audioFormatsCount: Int

    let formatID: String?

    let ext: String?

    let codec: String?

    let bitrate: Double?

    let directURL: String?
}
