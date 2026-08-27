import Foundation
import YoutubeDL

final class YTDLPRunner {

    static let shared = YTDLPRunner()

    private let queue = DispatchQueue(
        label: "com.echomusic.ytdlp.python",
        qos: .userInitiated
    )

    private let ytdlp = YoutubeDL()

    private init() {}

    struct Result: Sendable {
        let title: String
        let uploader: String
        let duration: Double?
        let formatsCount: Int

        let formatID: String?
        let ext: String?
        let audioCodec: String?
        let bitrate: Double?
        let directURL: String?
    }

    func extractInfo(
        from url: URL
    ) async throws -> Result {

        try await withCheckedThrowingContinuation { continuation in

            queue.async {

                Task {

                    do {

                        let result =
                            try await self.ytdlp.extractInfo(
                                url: url
                            )

                        let formats = result.0
                        let info = result.1

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

                        let output = Result(
                            title: info.title,
                            uploader:
                                info.uploader ?? "",
                            duration:
                                info.duration,
                            formatsCount:
                                formats.count,
                            formatID:
                                bestAudio?.format_id,
                            ext:
                                bestAudio?.ext,
                            audioCodec:
                                bestAudio?.acodec,
                            bitrate:
                                bestAudio?.abr,
                            directURL:
                                bestAudio?.url
                        )

                        continuation.resume(
                            returning: output
                        )

                    } catch {

                        continuation.resume(
                            throwing: error
                        )
                    }
                }
            }
        }
    }
}
