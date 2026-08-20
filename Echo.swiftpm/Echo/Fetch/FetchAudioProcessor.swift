import Foundation
import AVFoundation


enum FetchProcessingError: LocalizedError {
    case unsupportedInput
    case conversionFailed
    case invalidAudio

    var errorDescription: String? {
        switch self {
        case .unsupportedInput:
            return "Dit audioformaat kan niet verwerkt worden."
        case .conversionFailed:
            return "MP3-conversie is mislukt."
        case .invalidAudio:
            return "Het audiobestand is ongeldig."
        }
    }
}

@MainActor
final class FetchAudioProcessor {

    static let shared = FetchAudioProcessor()

    private init() {}

    func process(
        sourceURL: URL,
        item: FetchItem,
        quality: FetchQuality
    ) async throws -> FetchProcessedAudio {

        let fileManager = FileManager.default

        let tempDirectory =
            fileManager.temporaryDirectory
                .appendingPathComponent(
                    "EchoFetch",
                    isDirectory: true
                )

        try? fileManager.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )

        // Eerst altijd naar PCM WAV.
        let wavURL = tempDirectory
            .appendingPathComponent(
                "\(UUID().uuidString).wav"
            )

        try await convertToWAV(
            input: sourceURL,
            output: wavURL
        )

        let outputName = safeFileName(
            "\(item.title) - \(item.artist).mp3"
        )

        let documents =
            fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]

        let mp3URL =
            uniqueURL(
                directory: documents,
                filename: outputName
            )

        try await encodeMP3(
            wavURL: wavURL,
            outputURL: mp3URL,
            bitrate: quality.rawValue
        )

        try? fileManager.removeItem(
            at: wavURL
        )

        let artworkData =
            await downloadArtwork(
                item.artworkURL
            )

        return FetchProcessedAudio(
            fileURL: mp3URL,
            title: item.title,
            artist: item.artist,
            album: item.album,
            artworkData: artworkData
        )
    }


    // MARK: - Audio -> WAV

    private func convertToWAV(
        input: URL,
        output: URL
    ) async throws {

        let inputFile =
            try AVAudioFile(
                forReading: input
            )

        let inputFormat =
            inputFile.processingFormat

        guard let pcmFormat =
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 44_100,
                channels: min(
                    inputFormat.channelCount,
                    2
                ),
                interleaved: true
            )
        else {
            throw FetchProcessingError.invalidAudio
        }

        guard let converter =
            AVAudioConverter(
                from: inputFormat,
                to: pcmFormat
            )
        else {
            throw FetchProcessingError.conversionFailed
        }

        let outputFile =
            try AVAudioFile(
                forWriting: output,
                settings: pcmFormat.settings
            )

        let capacity:
            AVAudioFrameCount = 4096

        guard let inputBuffer =
            AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: capacity
            )
        else {
            throw FetchProcessingError.conversionFailed
        }

        guard let outputBuffer =
            AVAudioPCMBuffer(
                pcmFormat: pcmFormat,
                frameCapacity: capacity
            )
        else {
            throw FetchProcessingError.conversionFailed
        }

        while true {

            try inputFile.read(
                into: inputBuffer,
                frameCount: capacity
            )

            if inputBuffer.frameLength == 0 {
                break
            }

            var supplied = false

            var conversionError:
                NSError?

            let status =
                converter.convert(
                    to: outputBuffer,
                    error: &conversionError
                ) { _, outStatus in

                    if supplied {
                        outStatus.pointee =
                            .noDataNow
                        return nil
                    }

                    supplied = true

                    outStatus.pointee =
                        .haveData

                    return inputBuffer
                }

            if let conversionError {
                throw conversionError
            }

            switch status {

            case .haveData:

                try outputFile.write(
                    from: outputBuffer
                )

                outputBuffer.frameLength = 0

            case .inputRanDry,
                 .endOfStream:
                break

            case .error:
                throw FetchProcessingError
                    .conversionFailed

            @unknown default:
                break
            }
        }
    }


   private func encodeMP3(
    wavURL: URL,
    outputURL: URL,
    bitrate: Int
) async throws {
    throw FetchProcessingError.conversionFailed
}

    // MARK: - Artwork

    private func downloadArtwork(
        _ url: URL?
    ) async -> Data? {

        guard let url else {
            return nil
        }

        do {
            let (data, response) =
                try await URLSession.shared
                    .data(from: url)

            guard
                let http =
                    response as?
                    HTTPURLResponse,
                200..<300 ~= http.statusCode
            else {
                return nil
            }

            return data

        } catch {
            return nil
        }
    }


    // MARK: - File Names

    private func safeFileName(
        _ string: String
    ) -> String {

        let illegal =
            CharacterSet(
                charactersIn:
                    "/\\:*?\"<>|"
            )

        return string
            .components(
                separatedBy: illegal
            )
            .joined(separator: "")
    }


    private func uniqueURL(
        directory: URL,
        filename: String
    ) -> URL {

        let manager =
            FileManager.default

        let original =
            directory
                .appendingPathComponent(
                    filename
                )

        if !manager.fileExists(
            atPath: original.path
        ) {
            return original
        }

        let base =
            original
                .deletingPathExtension()
                .lastPathComponent

        let ext =
            original.pathExtension

        var index = 2

        while true {

            let candidate =
                directory
                    .appendingPathComponent(
                        "\(base) \(index).\(ext)"
                    )

            if !manager.fileExists(
                atPath: candidate.path
            ) {
                return candidate
            }

            index += 1
        }
    }
}
