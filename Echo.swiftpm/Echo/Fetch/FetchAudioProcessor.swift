import Foundation
import AVFoundation
import mp3lame


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
        // Temporary PCM WAV
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
            "Converting source to PCM WAV:",
            sourceURL.path
        )


        try await
            convertToWAV(
                input:
                    sourceURL,

                output:
                    wavURL
            )


        print(
            "PCM WAV ready:",
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


        let outputName =
            safeFileName(
                "\(item.title) - \(item.artist).mp3"
            )


        let mp3URL =
            uniqueURL(
                directory:
                    documents,

                filename:
                    outputName
            )


        // =========================================
        // Artwork
        // =========================================

        let artworkData: Data?


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
        // Encode MP3
        // =========================================

        print(
            "Encoding MP3:",
            quality.rawValue,
            "kbps"
        )


        do {

            try encodeMP3(
                wavURL:
                    wavURL,

                outputURL:
                    mp3URL,

                bitrate:
                    quality.rawValue,

                item:
                    item,

                artworkData:
                    artworkData
            )

        } catch {

            // Geen half MP3-bestand laten staan.

            try? fileManager
                .removeItem(
                    at:
                        mp3URL
                )


            throw error
        }


        print(
            "MP3 complete:",
            mp3URL.path
        )


        return FetchProcessedAudio(

            fileURL:
                mp3URL,

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


    // MARK: - Source -> PCM WAV

    private func convertToWAV(
        input: URL,
        output: URL
    ) async throws {

        let inputFile: AVAudioFile


        do {

            inputFile =
                try AVAudioFile(
                    forReading:
                        input
                )

        } catch {

            print(
                "AVAudioFile could not open input:",
                error
            )


            throw FetchProcessingError
                .unsupportedInput
        }


        let inputFormat =
            inputFile.processingFormat


        print(
            "Input format:",
            inputFormat
        )


        // MP3 encoder krijgt altijd:
        //
        // 44.1 kHz
        // stereo
        // signed 16-bit
        // interleaved PCM

        guard let pcmFormat =
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


        guard let converter =
            AVAudioConverter(

                from:
                    inputFormat,

                to:
                    pcmFormat
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
                    pcmFormat.settings,

                commonFormat:
                    .pcmFormatInt16,

                interleaved:
                    true
            )


        let inputCapacity:
            AVAudioFrameCount =
            8192


        guard let inputBuffer =
            AVAudioPCMBuffer(

                pcmFormat:
                    inputFormat,

                frameCapacity:
                    inputCapacity
            )
        else {

            throw FetchProcessingError
                .conversionFailed
        }


        let sampleRatio =
            pcmFormat.sampleRate /
            inputFormat.sampleRate


        let outputCapacity =
            AVAudioFrameCount(
                ceil(
                    Double(inputCapacity) *
                    max(
                        sampleRatio,
                        1
                    )
                )
            ) + 64


        var reachedEOF =
            false


        while !reachedEOF {

            try inputFile.read(
                into:
                    inputBuffer,

                frameCount:
                    inputCapacity
            )


            if inputBuffer.frameLength ==
                0 {

                reachedEOF =
                    true
            }


            var suppliedInput =
                false


            while true {

                guard let outputBuffer =
                    AVAudioPCMBuffer(

                        pcmFormat:
                            pcmFormat,

                        frameCapacity:
                            outputCapacity
                    )
                else {

                    throw FetchProcessingError
                        .conversionFailed
                }


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


                        if reachedEOF {

                            outStatus.pointee =
                                .endOfStream


                            return nil
                        }


                        if suppliedInput {

                            outStatus.pointee =
                                .noDataNow


                            return nil
                        }


                        suppliedInput =
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


                case .inputRanDry,
                     .endOfStream:

                    break


                case .error:

                    throw FetchProcessingError
                        .conversionFailed


                @unknown default:

                    break
                }


                break
            }
        }
    }


    // MARK: - PCM WAV -> MP3

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


        guard format.commonFormat ==
                .pcmFormatInt16
        else {

            throw FetchProcessingError
                .invalidAudio
        }


        guard format.channelCount ==
                2
        else {

            throw FetchProcessingError
                .invalidAudio
        }


        // =========================================
        // LAME
        // =========================================

        guard let lame =
            lame_init()
        else {

            throw FetchProcessingError
                .lameInitializationFailed
        }


        defer {

            lame_close(
                lame
            )
        }


        // =========================================
        // ID3
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
        // Encoder settings
        // =========================================

        lame_set_in_samplerate(
            lame,

            Int32(
                format.sampleRate
            )
        )


        lame_set_num_channels(
            lame,
            2
        )


        // Constant bitrate:
        //
        // 128
        // 192
        // 320

        lame_set_brate(
            lame,

            Int32(
                bitrate
            )
        )


        // 0 = slowest/highest
        // 9 = fastest/lowest
        //
        // 2 is een mooie quality/speed balans.

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

        guard FileManager.default
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


        let outputHandle =
            try FileHandle(
                forWritingTo:
                    outputURL
            )


        defer {

            try? outputHandle
                .close()
        }


        // =========================================
        // Encode buffers
        // =========================================

        let frameCapacity:
            AVAudioFrameCount =
            8192


        guard let pcmBuffer =
            AVAudioPCMBuffer(

                pcmFormat:
                    format,

                frameCapacity:
                    frameCapacity
            )
        else {

            throw FetchProcessingError
                .conversionFailed
        }


        while true {

            try audioFile.read(
                into:
                    pcmBuffer,

                frameCount:
                    frameCapacity
            )


            let frames =
                pcmBuffer.frameLength


            if frames ==
                0 {

                break
            }


            let audioBufferList =
                UnsafeMutableAudioBufferListPointer(
                    pcmBuffer
                        .mutableAudioBufferList
                )


            guard
                let rawData =
                    audioBufferList
                        .first?
                        .mData
            else {

                throw FetchProcessingError
                    .invalidAudio
            }


            let pcmPointer =
                rawData
                    .assumingMemoryBound(
                        to:
                            Int16.self
                    )


            // LAME recommended size:
            //
            // 1.25 * samples + 7200

            let mp3BufferSize =
                Int(
                    1.25 *
                    Double(frames)
                ) + 7200


            var mp3Buffer =
                [UInt8](
                    repeating:
                        0,

                    count:
                        mp3BufferSize
                )


            let encodedBytes:
                Int32 =
                mp3Buffer
                    .withUnsafeMutableBufferPointer {

                        buffer in


                        guard
                            let destination =
                                buffer
                                    .baseAddress
                        else {

                            return -1
                        }


                        return lame_encode_buffer_interleaved(

                            lame,

                            pcmPointer,

                            Int32(
                                frames
                            ),

                            destination,

                            Int32(
                                buffer.count
                            )
                        )
                    }


            guard encodedBytes >=
                    0
            else {

                throw FetchProcessingError
                    .lameEncodingFailed(
                        encodedBytes
                    )
            }


            if encodedBytes >
                0 {

                try outputHandle.write(
                    contentsOf:
                        Data(
                            mp3Buffer[
                                0..<Int(
                                    encodedBytes
                                )
                            ]
                        )
                )
            }
        }


        // =========================================
        // Flush encoder
        // =========================================

        var flushBuffer =
            [UInt8](
                repeating:
                    0,

                count:
                    7200
            )


        let flushedBytes:
            Int32 =
            flushBuffer
                .withUnsafeMutableBufferPointer {

                    buffer in


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


        guard flushedBytes >=
                0
        else {

            throw FetchProcessingError
                .lameEncodingFailed(
                    flushedBytes
                )
        }


        if flushedBytes >
            0 {

            try outputHandle.write(
                contentsOf:
                    Data(
                        flushBuffer[
                            0..<Int(
                                flushedBytes
                            )
                        ]
                    )
            )
        }
    }


    // MARK: - ID3 Metadata

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


        // Maak expliciet ID3v2 aan.

        id3tag_init(
            lame
        )


        id3tag_add_v2(
            lame
        )


        // =========================================
        // Title / Artist / Album
        // =========================================

        if settings.embedMetadata {

            item.title
                .withCString {

                    pointer in


                    id3tag_set_title(
                        lame,
                        pointer
                    )
                }


            item.artist
                .withCString {

                    pointer in


                    id3tag_set_artist(
                        lame,
                        pointer
                    )
                }


            if let album =
                item.album {

                album.withCString {

                    pointer in


                    id3tag_set_album(
                        lame,
                        pointer
                    )
                }
            }
        }


        // =========================================
        // Cover artwork
        // =========================================

        if
            settings.embedArtwork,
            let artworkData,
            !artworkData.isEmpty {

            artworkData
                .withUnsafeBytes {

                    rawBuffer in


                    guard
                        let baseAddress =
                            rawBuffer
                                .baseAddress
                    else {

                        return
                    }


                    let imagePointer =
                        baseAddress
                            .assumingMemoryBound(
                                to:
                                    CChar.self
                            )


                    let result =
                        id3tag_set_albumart(

                            lame,

                            imagePointer,

                            artworkData.count
                        )


                    if result !=
                        0 {

                        print(
                            "LAME artwork tag failed:",
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
                let http =
                    response
                        as? HTTPURLResponse,

                200..<300 ~=
                    http.statusCode
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


        var index =
            2


        while true {

            let candidate =
                directory
                    .appendingPathComponent(
                        "\(base) \(index).\(ext)"
                    )


            if !manager.fileExists(
                atPath:
                    candidate.path
            ) {

                return candidate
            }


            index += 1
        }
    }
}
