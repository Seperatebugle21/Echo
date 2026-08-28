import Foundation
import AVFoundation
import CLame


enum FetchProcessingError:
    LocalizedError {

    case unsupportedInput
    case conversionFailed
    case invalidAudio
    case cannotCreateMP3
    case lameInitializationFailed
    case lameEncodingFailed(Int32)


    var errorDescription: String? {

        switch self {

        case .unsupportedInput:
            return "Dit audioformaat kan niet verwerkt worden."

        case .conversionFailed:
            return "Audio converteren naar PCM is mislukt."

        case .invalidAudio:
            return "Het audiobestand is ongeldig."

        case .cannotCreateMP3:
            return "Echo kon het MP3-bestand niet aanmaken."

        case .lameInitializationFailed:
            return "De MP3-encoder kon niet gestart worden."

        case .lameEncodingFailed(let code):
            return "MP3 encoding is mislukt. LAME code: \(code)"
        }
    }
}


@MainActor
final class FetchAudioProcessor {

    static let shared =
        FetchAudioProcessor()


    private init() {}


    // MARK: - Process

    func process(
        sourceURL: URL,
        item: FetchItem,
        quality: FetchQuality
    ) async throws -> FetchProcessedAudio {

        let fileManager =
            FileManager.default


        // =========================================
        // Temporary directory
        // =========================================

        let tempDirectory =
            fileManager
                .temporaryDirectory
                .appendingPathComponent(
                    "EchoFetch",
                    isDirectory:
                        true
                )


        try fileManager
            .createDirectory(
                at:
                    tempDirectory,

                withIntermediateDirectories:
                    true
            )


        // =========================================
        // Temporary WAV
        // =========================================

        let wavURL =
            tempDirectory
                .appendingPathComponent(
                    "\(UUID().uuidString).wav"
                )


        defer {

            try? fileManager
                .removeItem(
                    at:
                        wavURL
                )
        }


        print(
            "Converting source to WAV:",
            sourceURL.path
        )


        try convertToWAV(
            input:
                sourceURL,

            output:
                wavURL
        )


        print(
            "WAV ready:",
            wavURL.path
        )


        // =========================================
        // Output MP3
        // =========================================

        let documents =
            fileManager.urls(
                for:
                    .documentDirectory,

                in:
                    .userDomainMask
            )[0]


        let fileName =
            safeFileName(
                "\(item.title) - \(item.artist).mp3"
            )


        let outputURL =
            uniqueURL(

                directory:
                    documents,

                filename:
                    fileName
            )


        // =========================================
        // Artwork
        // =========================================

        let artworkData:
            Data?


        if FetchSettings.shared
            .embedArtwork {

            artworkData =
                await downloadArtwork(
                    item.artworkURL
                )

        } else {

            artworkData =
                nil
        }


        // =========================================
        // LAME encode
        // =========================================

        do {

            try encodeMP3(

                wavURL:
                    wavURL,

                outputURL:
                    outputURL,

                bitrate:
                    quality.rawValue,

                item:
                    item,

                artworkData:
                    artworkData
            )


        } catch {

            try? fileManager
                .removeItem(
                    at:
                        outputURL
                )


            throw error
        }


        print(
            "Final MP3:",
            outputURL.path
        )


        return FetchProcessedAudio(

            fileURL:
                outputURL,

            title:
                item.title,

            artist:
                item.artist,

            album:
                item.album,

            artworkData:
                artworkData
        )
    }


    // MARK: - Source -> WAV

    private func convertToWAV(
        input: URL,
        output: URL
    ) throws {

        let inputFile:
            AVAudioFile


        do {

            inputFile =
                try AVAudioFile(
                    forReading:
                        input
                )


        } catch {

            print(
                "AVAudioFile input failed:",
                error
            )


            throw FetchProcessingError
                .unsupportedInput
        }


        let inputFormat =
            inputFile
                .processingFormat


        print(
            "Input format:",
            inputFormat
        )


        guard
            let outputFormat =
                AVAudioFormat(

                    commonFormat:
                        .pcmFormatInt16,

                    sampleRate:
                        44_100,

                    channels:
                        2,

                    interleaved:
                        true
                )
        else {

            throw FetchProcessingError
                .invalidAudio
        }


        guard
            let converter =
                AVAudioConverter(

                    from:
                        inputFormat,

                    to:
                        outputFormat
                )
        else {

            throw FetchProcessingError
                .conversionFailed
        }


        let outputFile =
            try AVAudioFile(

                forWriting:
                    output,

                settings:
                    outputFormat.settings,

                commonFormat:
                    .pcmFormatInt16,

                interleaved:
                    true
            )


        let inputFrameCapacity:
            AVAudioFrameCount =
            8192


        guard
            let inputBuffer =
                AVAudioPCMBuffer(

                    pcmFormat:
                        inputFormat,

                    frameCapacity:
                        inputFrameCapacity
                )
        else {

            throw FetchProcessingError
                .conversionFailed
        }


        let ratio =
            outputFormat.sampleRate /
            inputFormat.sampleRate


        let outputFrameCapacity =
            AVAudioFrameCount(

                ceil(
                    Double(
                        inputFrameCapacity
                    )
                    *
                    max(
                        ratio,
                        1.0
                    )
                )
            )
            +
            128


        var inputEnded =
            false


        while true {

            if !inputEnded {

                inputBuffer.frameLength =
                    0


                try inputFile.read(

                    into:
                        inputBuffer,

                    frameCount:
                        inputFrameCapacity
                )


                if inputBuffer.frameLength ==
                    0 {

                    inputEnded =
                        true
                }
            }


            guard
                let outputBuffer =
                    AVAudioPCMBuffer(

                        pcmFormat:
                            outputFormat,

                        frameCapacity:
                            outputFrameCapacity
                    )
            else {

                throw FetchProcessingError
                    .conversionFailed
            }


            var supplied =
                false


            var conversionError:
                NSError?


            let status =
                converter.convert(

                    to:
                        outputBuffer,

                    error:
                        &conversionError

                ) {

                    _,
                    outStatus in


                    if inputEnded {

                        outStatus.pointee =
                            .endOfStream


                        return nil
                    }


                    if supplied {

                        outStatus.pointee =
                            .noDataNow


                        return nil
                    }


                    supplied =
                        true


                    outStatus.pointee =
                        .haveData


                    return inputBuffer
                }


            if let conversionError {

                throw conversionError
            }


            if outputBuffer.frameLength >
                0 {

                try outputFile.write(
                    from:
                        outputBuffer
                )
            }


            switch status {

            case .haveData:

                continue


            case .inputRanDry:

                if inputEnded {

                    return
                }


                continue


            case .endOfStream:

                return


            case .error:

                throw FetchProcessingError
                    .conversionFailed


            @unknown default:

                throw FetchProcessingError
                    .conversionFailed
            }
        }
    }


    // MARK: - WAV -> MP3

    private func encodeMP3(
        wavURL: URL,
        outputURL: URL,
        bitrate: Int,
        item: FetchItem,
        artworkData: Data?
    ) throws {

        let audioFile =
            try AVAudioFile(
                forReading:
                    wavURL
            )


        let format =
            audioFile
                .processingFormat


        guard
            format.commonFormat ==
                .pcmFormatInt16,

            format.channelCount ==
                2
        else {

            throw FetchProcessingError
                .invalidAudio
        }


        // =========================================
        // LAME init
        // =========================================

        guard let lame =
            lame_init()
        else {

            throw FetchProcessingError
                .lameInitializationFailed
        }


        defer {

            _ =
                lame_close(
                    lame
                )
        }


        // =========================================
        // Metadata
        // =========================================

        configureMetadata(

            lame:
                lame,

            item:
                item,

            artworkData:
                artworkData
        )


        // =========================================
        // Encoder configuration
        // =========================================

        _ =
            lame_set_in_samplerate(

                lame,

                Int32(
                    format.sampleRate
                )
            )


        _ =
            lame_set_num_channels(
                lame,
                2
            )


        _ =
            lame_set_brate(

                lame,

                Int32(
                    bitrate
                )
            )


        _ =
            lame_set_quality(
                lame,
                2
            )


        let initResult =
            lame_init_params(
                lame
            )


        guard initResult >=
                0
        else {

            throw FetchProcessingError
                .lameEncodingFailed(
                    initResult
                )
        }


        // =========================================
        // Output file
        // =========================================

        guard
            FileManager.default
                .createFile(

                    atPath:
                        outputURL.path,

                    contents:
                        nil
                )
        else {

            throw FetchProcessingError
                .cannotCreateMP3
        }


        let output =
            try FileHandle(
                forWritingTo:
                    outputURL
            )


        defer {

            try? output
                .close()
        }


        // =========================================
        // PCM buffer
        // =========================================

        let frameCapacity:
            AVAudioFrameCount =
            8192


        guard
            let pcmBuffer =
                AVAudioPCMBuffer(

                    pcmFormat:
                        format,

                    frameCapacity:
                        frameCapacity
                )
        else {

            throw FetchProcessingError
                .invalidAudio
        }


        while true {

            pcmBuffer.frameLength =
                0


            try audioFile.read(

                into:
                    pcmBuffer,

                frameCount:
                    frameCapacity
            )


            let frames =
                pcmBuffer
                    .frameLength


            if frames ==
                0 {

                break
            }


            let buffers =
                UnsafeMutableAudioBufferListPointer(
                    pcmBuffer
                        .mutableAudioBufferList
                )


            guard
                let rawPointer =
                    buffers
                        .first?
                        .mData
            else {

                throw FetchProcessingError
                    .invalidAudio
            }


            let pcm =
                rawPointer
                    .assumingMemoryBound(
                        to:
                            Int16.self
                    )


            let mp3BufferSize =
                Int(
                    1.25 *
                    Double(
                        frames
                    )
                )
                +
                7200


            var mp3Buffer =
                [UInt8](
                    repeating:
                        0,

                    count:
                        mp3BufferSize
                )


            let encoded =
                mp3Buffer
                    .withUnsafeMutableBufferPointer {

                        buffer -> Int32 in


                        guard
                            let destination =
                                buffer
                                    .baseAddress
                        else {

                            return -1
                        }


                        return lame_encode_buffer_interleaved(

                            lame,

                            pcm,

                            Int32(
                                frames
                            ),

                            destination,

                            Int32(
                                buffer.count
                            )
                        )
                    }


            guard encoded >=
                    0
            else {

                throw FetchProcessingError
                    .lameEncodingFailed(
                        encoded
                    )
            }


            if encoded >
                0 {

                try output.write(

                    contentsOf:
                        Data(
                            mp3Buffer[
                                0..<Int(
                                    encoded
                                )
                            ]
                        )
                )
            }
        }


        // =========================================
        // Flush
        // =========================================

        var flushBuffer =
            [UInt8](
                repeating:
                    0,

                count:
                    7200
            )


        let flushed =
            flushBuffer
                .withUnsafeMutableBufferPointer {

                    buffer -> Int32 in


                    guard
                        let destination =
                            buffer
                                .baseAddress
                    else {

                        return -1
                    }


                    return lame_encode_flush(

                        lame,

                        destination,

                        Int32(
                            buffer.count
                        )
                    )
                }


        guard flushed >=
                0
        else {

            throw FetchProcessingError
                .lameEncodingFailed(
                    flushed
                )
        }


        if flushed >
            0 {

            try output.write(

                contentsOf:
                    Data(
                        flushBuffer[
                            0..<Int(
                                flushed
                            )
                        ]
                    )
            )
        }
    }


    // MARK: - ID3 metadata

    private func configureMetadata(
        lame: OpaquePointer,
        item: FetchItem,
        artworkData: Data?
    ) {

        let settings =
            FetchSettings.shared


        guard
            settings.embedMetadata ||
            settings.embedArtwork
        else {

            return
        }


        id3tag_init(
            lame
        )


        id3tag_add_v2(
            lame
        )


        // =========================================
        // Spotify metadata
        // =========================================

        if settings.embedMetadata {

            item.title
                .withCString {

                    id3tag_set_title(
                        lame,
                        $0
                    )
                }


            item.artist
                .withCString {

                    id3tag_set_artist(
                        lame,
                        $0
                    )
                }


            if let album =
                item.album {

                album.withCString {

                    id3tag_set_album(
                        lame,
                        $0
                    )
                }
            }
        }


        // =========================================
        // Spotify artwork
        // =========================================

        if
            settings.embedArtwork,

            let artworkData,

            !artworkData.isEmpty {

            artworkData
                .withUnsafeBytes {

                    rawBuffer in


                    guard
                        let address =
                            rawBuffer
                                .baseAddress
                    else {

                        return
                    }


                    let pointer =
                        address
                            .assumingMemoryBound(
                                to:
                                    CChar.self
                            )


                    let result =
                        id3tag_set_albumart(

                            lame,

                            pointer,

                            artworkData.count
                        )


                    if result !=
                        0 {

                        print(
                            "Album artwork tag failed:",
                            result
                        )
                    }
                }
        }
    }


    // MARK: - Artwork

    private func downloadArtwork(
        _ url: URL?
    ) async -> Data? {

        guard let url else {

            return nil
        }


        do {

            let (
                data,
                response
            ) =
                try await
                URLSession.shared
                    .data(
                        from:
                            url
                    )


            guard
                let response =
                    response
                        as? HTTPURLResponse,

                200..<300 ~=
                    response.statusCode
            else {

                return nil
            }


            return data


        } catch {

            print(
                "Artwork download failed:",
                error
            )


            return nil
        }
    }


    // MARK: - Filename

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
                separatedBy:
                    illegal
            )
            .joined(
                separator:
                    ""
            )
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
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
            atPath:
                original.path
        ) {

            return original
        }


        let base =
            original
                .deletingPathExtension()
                .lastPathComponent


        let ext =
            original
                .pathExtension


        var counter =
            2


        while true {

            let candidate =
                directory
                    .appendingPathComponent(
                        "\(base) \(counter).\(ext)"
                    )


            if !manager.fileExists(
                atPath:
                    candidate.path
            ) {

                return candidate
            }


            counter += 1
        }
    }
}
