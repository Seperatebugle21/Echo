import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox
import CLame


enum FetchProcessingError: LocalizedError {

    case unsupportedInput
    case noAudioTrack
    case cannotCreateReader
    case cannotAddReaderOutput
    case readerFailed(String)

    case cannotCreateMP3

    case lameInitializationFailed
    case lameConfigurationFailed(String)
    case lameEncodingFailed(Int32)


    var errorDescription: String? {

        switch self {

        case .unsupportedInput:
            return "Dit audioformaat kan niet verwerkt worden."

        case .noAudioTrack:
            return "Het gedownloade bestand bevat geen audiotrack."

        case .cannotCreateReader:
            return "Echo kon de audiodecoder niet starten."

        case .cannotAddReaderOutput:
            return "Echo kon de PCM-audio-uitvoer niet instellen."

        case .readerFailed(let message):
            return "Audio decoderen is mislukt: \(message)"

        case .cannotCreateMP3:
            return "Echo kon het MP3-bestand niet aanmaken."

        case .lameInitializationFailed:
            return "De MP3-encoder kon niet gestart worden."

        case .lameConfigurationFailed(let setting):
            return "De MP3-encoder kon '\(setting)' niet instellen."

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
        // Final destination
        // =========================================

        let documents =
            fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]


        let fileName =
            safeFileName(
                "\(item.title) - \(item.artist).mp3"
            )


        let outputURL =
            uniqueURL(
                directory: documents,
                filename: fileName
            )


        // =========================================
        // Artwork
        // =========================================

        let artworkData: Data?


        if FetchSettings.shared.embedArtwork {

            artworkData =
                await downloadArtwork(
                    item.artworkURL
                )

        } else {

            artworkData =
                nil
        }


        // =========================================
        // Source -> PCM -> LAME -> MP3
        // =========================================

        do {

            try await encodeDirectlyToMP3(
                sourceURL: sourceURL,
                outputURL: outputURL,
                bitrate: quality.rawValue,
                item: item,
                artworkData: artworkData
            )

        } catch {

            try? fileManager.removeItem(
                at: outputURL
            )

            throw error
        }


        print(
            "Final MP3:",
            outputURL.path
        )


        return FetchProcessedAudio(
            fileURL: outputURL,
            title: item.title,
            artist: item.artist,
            album: item.album,
            artworkData: artworkData
        )
    }


    // MARK: - Direct Decode + Encode

    private func encodeDirectlyToMP3(
        sourceURL: URL,
        outputURL: URL,
        bitrate: Int,
        item: FetchItem,
        artworkData: Data?
    ) async throws {

        print(
            "Opening audio source:",
            sourceURL.path
        )


        // =========================================
        // Asset
        // =========================================

        let asset =
            AVURLAsset(
                url: sourceURL
            )


        let audioTracks =
            try await asset.loadTracks(
                withMediaType: .audio
            )


        guard let audioTrack =
            audioTracks.first
        else {

            throw FetchProcessingError
                .noAudioTrack
        }


        // =========================================
        // AVAssetReader
        //
        // Decode compressed AAC/M4A directly into:
        //
        // - 44.1 kHz
        // - stereo
        // - signed 16-bit
        // - interleaved
        //
        // Exactly what LAME wants.
        // =========================================

        let reader: AVAssetReader


        do {

            reader =
                try AVAssetReader(
                    asset: asset
                )

        } catch {

            throw FetchProcessingError
                .cannotCreateReader
        }


        let pcmSettings: [String: Any] = [

            AVFormatIDKey:
                kAudioFormatLinearPCM,

            AVSampleRateKey:
                44_100,

            AVNumberOfChannelsKey:
                2,

            AVLinearPCMBitDepthKey:
                16,

            AVLinearPCMIsFloatKey:
                false,

            AVLinearPCMIsBigEndianKey:
                false,

            AVLinearPCMIsNonInterleaved:
                false
        ]


        let readerOutput =
            AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: pcmSettings
            )


        readerOutput.alwaysCopiesSampleData =
            false


        guard reader.canAdd(
            readerOutput
        ) else {

            throw FetchProcessingError
                .cannotAddReaderOutput
        }


        reader.add(
            readerOutput
        )


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

            _ =
                lame_close(
                    lame
                )
        }


        configureMetadata(
            lame: lame,
            item: item,
            artworkData: artworkData
        )


        // =========================================
        // LAME settings
        // =========================================

        guard
            lame_set_in_samplerate(
                lame,
                44_100
            ) >= 0
        else {

            throw FetchProcessingError
                .lameConfigurationFailed(
                    "sample rate"
                )
        }


        guard
            lame_set_num_channels(
                lame,
                2
            ) >= 0
        else {

            throw FetchProcessingError
                .lameConfigurationFailed(
                    "channels"
                )
        }


        guard
            lame_set_brate(
                lame,
                Int32(bitrate)
            ) >= 0
        else {

            throw FetchProcessingError
                .lameConfigurationFailed(
                    "bitrate"
                )
        }


        guard
            lame_set_quality(
                lame,
                2
            ) >= 0
        else {

            throw FetchProcessingError
                .lameConfigurationFailed(
                    "quality"
                )
        }


        let initResult =
            lame_init_params(
                lame
            )


        guard initResult >= 0 else {

            throw FetchProcessingError
                .lameEncodingFailed(
                    initResult
                )
        }


        // =========================================
        // Create MP3
        // =========================================

        guard FileManager.default.createFile(
            atPath: outputURL.path,
            contents: nil
        ) else {

            throw FetchProcessingError
                .cannotCreateMP3
        }


        let outputFile =
            try FileHandle(
                forWritingTo: outputURL
            )


        defer {

            try? outputFile.close()
        }


        // =========================================
        // Start decoder
        // =========================================

        guard reader.startReading() else {

            throw FetchProcessingError
                .readerFailed(
                    reader.error?
                        .localizedDescription
                    ?? "AVAssetReader kon niet starten."
                )
        }


        print(
            "PCM decoder started"
        )


        // =========================================
        // Read PCM sample buffers
        // =========================================

        while reader.status == .reading {

            guard let sampleBuffer =
                readerOutput.copyNextSampleBuffer()
            else {

                break
            }


            try encodeSampleBuffer(
                sampleBuffer,
                lame: lame,
                outputFile: outputFile
            )
        }


        // =========================================
        // Reader result
        // =========================================

        switch reader.status {

        case .completed:

            print(
                "PCM decoding completed"
            )


        case .failed:

            throw FetchProcessingError
                .readerFailed(
                    reader.error?
                        .localizedDescription
                    ?? "Onbekende decoderfout."
                )


        case .cancelled:

            throw FetchProcessingError
                .readerFailed(
                    "Audio-decoding werd geannuleerd."
                )


        default:

            break
        }


        // =========================================
        // Flush LAME
        // =========================================

        var flushBuffer =
            [UInt8](
                repeating: 0,
                count: 7200
            )


        let flushed =
            flushBuffer.withUnsafeMutableBufferPointer {

                buffer -> Int32 in


                guard let destination =
                    buffer.baseAddress
                else {

                    return -1
                }


                return lame_encode_flush(
                    lame,
                    destination,
                    Int32(buffer.count)
                )
            }


        guard flushed >= 0 else {

            throw FetchProcessingError
                .lameEncodingFailed(
                    flushed
                )
        }


        if flushed > 0 {

            let data =
                Data(
                    flushBuffer[
                        0..<Int(flushed)
                    ]
                )


            try outputFile.write(
                contentsOf: data
            )
        }


        print(
            "LAME encoding completed"
        )
    }


    // MARK: - Encode PCM Sample Buffer

    private func encodeSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        lame: OpaquePointer,
        outputFile: FileHandle
    ) throws {

        guard let dataBuffer =
            CMSampleBufferGetDataBuffer(
                sampleBuffer
            )
        else {

            throw FetchProcessingError
                .readerFailed(
                    "PCM-buffer bevat geen data."
                )
        }


        let sampleCount =
            CMSampleBufferGetNumSamples(
                sampleBuffer
            )


        guard sampleCount > 0 else {

            return
        }


        var totalLength =
            0


        var rawPointer:
            UnsafeMutablePointer<Int8>?


        let pointerStatus =
            CMBlockBufferGetDataPointer(
                dataBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &totalLength,
                dataPointerOut: &rawPointer
            )


        guard
            pointerStatus ==
                kCMBlockBufferNoErr,
            let rawPointer
        else {

            throw FetchProcessingError
                .readerFailed(
                    "PCM-buffer kon niet gelezen worden."
                )
        }


        // =========================================
        // Stereo Int16 interleaved:
        //
        // L R L R L R ...
        //
        // CMSampleBufferGetNumSamples gives
        // number of PCM frames.
        // =========================================

        let pcm =
            UnsafeRawPointer(
                rawPointer
            )
            .assumingMemoryBound(
                to: Int16.self
            )


        let mp3BufferSize =
            Int(
                1.25 *
                Double(sampleCount)
            )
            +
            7200


        var mp3Buffer =
            [UInt8](
                repeating: 0,
                count: mp3BufferSize
            )


        let encoded =
            mp3Buffer
                .withUnsafeMutableBufferPointer {

                    buffer -> Int32 in


                    guard let destination =
                        buffer.baseAddress
                    else {

                        return -1
                    }


                    return lame_encode_buffer_interleaved(
                        lame,
                        UnsafeMutablePointer(
                            mutating: pcm
                        ),
                        Int32(sampleCount),
                        destination,
                        Int32(buffer.count)
                    )
                }


        guard encoded >= 0 else {

            throw FetchProcessingError
                .lameEncodingFailed(
                    encoded
                )
        }


        if encoded > 0 {

            let data =
                Data(
                    mp3Buffer[
                        0..<Int(encoded)
                    ]
                )


            try outputFile.write(
                contentsOf: data
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

            item.title.withCString {

                id3tag_set_title(
                    lame,
                    $0
                )
            }


            item.artist.withCString {

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
        // Spotify cover
        // =========================================

        if
            settings.embedArtwork,
            let artworkData,
            !artworkData.isEmpty {

            artworkData.withUnsafeBytes {

                rawBuffer in


                guard let address =
                    rawBuffer.baseAddress
                else {

                    return
                }


                let pointer =
                    address.assumingMemoryBound(
                        to: CChar.self
                    )


                let result =
                    id3tag_set_albumart(
                        lame,
                        pointer,
                        artworkData.count
                    )


                if result != 0 {

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

            let (data, response) =
                try await
                URLSession.shared.data(
                    from: url
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
                separatedBy: illegal
            )
            .joined(
                separator: ""
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
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


        var index =
            2


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
