import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox
import UIKit
import CLame


enum FetchProcessingError: LocalizedError {

    case noAudioTrack
    case cannotCreateReader
    case cannotAddReaderOutput
    case readerFailed(String)

    case cannotCreateMP3
    case cannotMoveFinalMP3(String)

    case lameInitializationFailed
    case lameConfigurationFailed(String)
    case lameEncodingFailed(Int32)


    var errorDescription: String? {

        switch self {

        case .noAudioTrack:
            return "Het gedownloade bestand bevat geen audiotrack."

        case .cannotCreateReader:
            return "Echo kon de audiodecoder niet starten."

        case .cannotAddReaderOutput:
            return "Echo kon de PCM-audio-uitvoer niet instellen."

        case .readerFailed(let message):
            return "Audio decoderen is mislukt: \(message)"

        case .cannotCreateMP3:
            return "Echo kon het tijdelijke MP3-bestand niet aanmaken."

        case .cannotMoveFinalMP3(let message):
            return "De afgewerkte MP3 kon niet naar de library worden verplaatst: \(message)"

        case .lameInitializationFailed:
            return "De MP3-encoder kon niet gestart worden."

        case .lameConfigurationFailed(let setting):
            return "De MP3-encoder kon '\(setting)' niet instellen."

        case .lameEncodingFailed(let code):
            return "MP3 encoding is mislukt. LAME code: \(code)"
        }
    }
}


// MARK: - Background Processing Snapshot

private struct FetchMP3Snapshot: Sendable {

    let sourceURL: URL

    let temporaryMP3URL: URL

    let bitrate: Int

    let title: String

    let artist: String

    let album: String?

    let artworkData: Data?
}


// MARK: - Processor

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

        Self.setStage(
            "MP3 1 - start"
        )


        let fileManager =
            FileManager.default


        // =========================================
        // Final Documents destination
        // =========================================

        let documents =
            fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]


        let finalFileName =
            safeFileName(
                "\(item.title) - \(item.artist).mp3"
            )


        let finalURL =
            uniqueURL(
                directory: documents,
                filename: finalFileName
            )


        // =========================================
        // IMPORTANT:
        //
        // We do NOT create the MP3 in Documents yet.
        //
        // Otherwise MusicLibraryManager can see and
        // import a half-written MP3.
        // =========================================

        let temporaryDirectory =
            fileManager
                .temporaryDirectory
                .appendingPathComponent(
                    "EchoMP3Processing",
                    isDirectory: true
                )


        try fileManager.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )


        let temporaryMP3URL =
            temporaryDirectory
                .appendingPathComponent(
                    "\(UUID().uuidString).mp3"
                )


        // =========================================
        // Artwork
        // =========================================

        let originalArtworkData: Data?


        if FetchSettings.shared.embedArtwork {

            originalArtworkData =
                await downloadArtwork(
                    item.artworkURL
                )

        } else {

            originalArtworkData =
                nil
        }


        // LAME's automatic ID3 handling does not like
        // very large embedded tags.
        //
        // Compress the Spotify artwork to a reasonable
        // size before giving it to LAME.

        let id3ArtworkData =
            prepareArtworkForID3(
                originalArtworkData
            )


        print(
            "Original artwork:",
            originalArtworkData?.count ?? 0,
            "bytes"
        )


        print(
            "ID3 artwork:",
            id3ArtworkData?.count ?? 0,
            "bytes"
        )


        Self.setStage(
            "MP3 2 - metadata prepared"
        )


        // =========================================
        // Snapshot
        //
        // Do NOT send FetchItem to Task.detached.
        // FetchItem is Observable/reference state.
        //
        // Copy only immutable Sendable values.
        // =========================================

        let snapshot =
            FetchMP3Snapshot(

                sourceURL:
                    sourceURL,

                temporaryMP3URL:
                    temporaryMP3URL,

                bitrate:
                    quality.rawValue,

                title:
                    item.title,

                artist:
                    item.artist,

                album:
                    item.album,

                artworkData:
                    id3ArtworkData
            )


        // =========================================
        // BACKGROUND ENCODING
        //
        // This is the crucial difference.
        //
        // AVAssetReader + LAME no longer run on
        // MainActor / main UI thread.
        // =========================================

        do {

            try await Task.detached(
                priority: .utility
            ) {

                try await Self
                    .encodeInBackground(
                        snapshot
                    )

            }.value

        } catch {

            try? fileManager.removeItem(
                at: temporaryMP3URL
            )


            Self.setStage(
                "MP3 FAILED - \(error.localizedDescription)"
            )


            throw error
        }


        Self.setStage(
            "MP3 8 - background encoding complete"
        )


        // =========================================
        // Verify temporary file
        // =========================================

        guard fileManager.fileExists(
            atPath: temporaryMP3URL.path
        ) else {

            throw FetchProcessingError
                .cannotCreateMP3
        }


        let attributes =
            try fileManager.attributesOfItem(
                atPath:
                    temporaryMP3URL.path
            )


        let fileSize =
            attributes[
                .size
            ] as? NSNumber


        print(
            "Finished temporary MP3:",
            fileSize?.int64Value ?? 0,
            "bytes"
        )


        // =========================================
        // FINAL MOVE
        //
        // Only NOW does the MP3 appear in Documents.
        //
        // At this point:
        // - decoding finished
        // - LAME flushed
        // - file synchronized
        // - ID3 configured
        // =========================================

        do {

            try fileManager.moveItem(
                at:
                    temporaryMP3URL,

                to:
                    finalURL
            )

        } catch {

            try? fileManager.removeItem(
                at:
                    temporaryMP3URL
            )


            throw FetchProcessingError
                .cannotMoveFinalMP3(
                    error.localizedDescription
                )
        }


        Self.setStage(
            "MP3 9 - moved to Documents"
        )


        print(
            "Final MP3:",
            finalURL.path
        )


        // =========================================
        // Return the ORIGINAL artwork to Echo.
        //
        // Echo itself can use the full Spotify image.
        //
        // Only the embedded ID3 artwork was compressed.
        // =========================================

        return FetchProcessedAudio(

            fileURL:
                finalURL,

            title:
                item.title,

            artist:
                item.artist,

            album:
                item.album,

            artworkData:
                originalArtworkData
        )
    }


    // MARK: - Background Encoding

    private nonisolated static func encodeInBackground(
        _ snapshot: FetchMP3Snapshot
    ) async throws {

        setStage(
            "MP3 3 - background task started"
        )


        print(
            "Background MP3 encoding started"
        )


        print(
            "Source:",
            snapshot.sourceURL.path
        )


        print(
            "Title:",
            snapshot.title
        )


        print(
            "Artist:",
            snapshot.artist
        )


        print(
            "Album:",
            snapshot.album ?? "nil"
        )


        // =========================================
        // Source Asset
        // =========================================

        let asset =
            AVURLAsset(
                url:
                    snapshot.sourceURL
            )


        let tracks =
            try await asset.loadTracks(
                withMediaType:
                    .audio
            )


        guard let audioTrack =
            tracks.first
        else {

            throw FetchProcessingError
                .noAudioTrack
        }


        setStage(
            "MP3 4 - audio track loaded"
        )


        // =========================================
        // AVAssetReader
        // =========================================

        let reader: AVAssetReader


        do {

            reader =
                try AVAssetReader(
                    asset:
                        asset
                )

        } catch {

            throw FetchProcessingError
                .cannotCreateReader
        }


        // Decode directly into exactly what LAME wants:
        //
        // 44.1 kHz
        // stereo
        // signed 16-bit
        // interleaved PCM

        let pcmSettings:
            [String: Any] = [

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

                track:
                    audioTrack,

                outputSettings:
                    pcmSettings
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
        // LAME initialization
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
        // ID3 metadata BEFORE lame_init_params
        // =========================================

        configureMetadata(
            lame:
                lame,

            title:
                snapshot.title,

            artist:
                snapshot.artist,

            album:
                snapshot.album,

            artworkData:
                snapshot.artworkData
        )


        // =========================================
        // LAME configuration
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
                Int32(
                    snapshot.bitrate
                )
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


        setStage(
            "MP3 5 - LAME initialized"
        )


        // =========================================
        // Temporary output
        // =========================================

        let manager =
            FileManager.default


        if manager.fileExists(
            atPath:
                snapshot
                    .temporaryMP3URL
                    .path
        ) {

            try manager.removeItem(
                at:
                    snapshot
                        .temporaryMP3URL
            )
        }


        guard manager.createFile(

            atPath:
                snapshot
                    .temporaryMP3URL
                    .path,

            contents:
                nil
        ) else {

            throw FetchProcessingError
                .cannotCreateMP3
        }


        let outputFile =
            try FileHandle(
                forWritingTo:
                    snapshot
                        .temporaryMP3URL
            )


        defer {

            try? outputFile
                .close()
        }


        // =========================================
        // Start reading
        // =========================================

        guard reader.startReading() else {

            throw FetchProcessingError
                .readerFailed(

                    reader.error?
                        .localizedDescription

                    ??
                    "AVAssetReader kon niet starten."
                )
        }


        setStage(
            "MP3 6 - encoding"
        )


        var bufferCounter =
            0


        // =========================================
        // PCM -> MP3
        //
        // Each AVFoundation/CoreMedia object gets
        // its own autoreleasepool.
        // =========================================

        while reader.status ==
            .reading {

            var processingError:
                Error?


            let receivedBuffer: Bool =
                autoreleasepool {

                    guard let sampleBuffer =
                        readerOutput
                            .copyNextSampleBuffer()
                    else {

                        return false
                    }


                    do {

                        try encodeSampleBuffer(
                            sampleBuffer,

                            lame:
                                lame,

                            outputFile:
                                outputFile
                        )

                    } catch {

                        processingError =
                            error
                    }


                    return true
                }


            if let processingError {

                reader.cancelReading()

                throw processingError
            }


            if !receivedBuffer {

                break
            }


            bufferCounter +=
                1


            if bufferCounter % 500 ==
                0 {

                setStage(
                    "MP3 6 - encoding buffer \(bufferCounter)"
                )
            }
        }


        // =========================================
        // Reader state
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

                    ??
                    "Onbekende decoderfout."
                )


        case .cancelled:

            throw FetchProcessingError
                .readerFailed(
                    "Audio-decoding werd geannuleerd."
                )


        default:

            break
        }


        setStage(
            "MP3 7 - flushing"
        )


        // =========================================
        // Flush LAME
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


                    guard let destination =
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

            try outputFile.write(

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


        // Flush FileHandle buffers to disk.

        try outputFile
            .synchronize()


        print(
            "Background MP3 encoding finished"
        )
    }


    // MARK: - PCM Buffer -> LAME

    private nonisolated static func encodeSampleBuffer(
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


        guard sampleCount >
            0
        else {

            return
        }


        var totalLength =
            0


        var rawPointer:
            UnsafeMutablePointer<Int8>?


        let result =
            CMBlockBufferGetDataPointer(

                dataBuffer,

                atOffset:
                    0,

                lengthAtOffsetOut:
                    nil,

                totalLengthOut:
                    &totalLength,

                dataPointerOut:
                    &rawPointer
            )


        guard
            result ==
                kCMBlockBufferNoErr,

            let rawPointer
        else {

            throw FetchProcessingError
                .readerFailed(
                    "PCM-buffer kon niet gelezen worden."
                )
        }


        let requiredBytes =
            sampleCount
            *
            2
            *
            MemoryLayout<Int16>.size


        guard totalLength >=
            requiredBytes
        else {

            throw FetchProcessingError
                .readerFailed(
                    "PCM-buffer heeft een onverwachte grootte."
                )
        }


        let pcm =
            UnsafeRawPointer(
                rawPointer
            )
            .assumingMemoryBound(
                to:
                    Int16.self
            )


        let calculatedMP3BufferSize =
    Int(
        1.25 *
        Double(sampleCount)
    )
    +
    7200




let mp3BufferSize =
    max(
        calculatedMP3BufferSize,
        128 * 1024
    )


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


                    guard let destination =
                        buffer.baseAddress
                    else {

                        return -1
                    }


                    return lame_encode_buffer_interleaved(

                        lame,

                        UnsafeMutablePointer(
                            mutating:
                                pcm
                        ),

                        Int32(
                            sampleCount
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


        guard encoded >
            0
        else {

            return
        }


        try outputFile.write(

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


    // MARK: - ID3

    private nonisolated static func configureMetadata(
        lame: OpaquePointer,
        title: String,
        artist: String,
        album: String?,
        artworkData: Data?
    ) {

        // Reset ID3 structure.

        id3tag_init(
            lame
        )


        // Force ID3v2.
        //
        // Album artwork requires ID3v2.

        id3tag_add_v2(
            lame
        )


        // =========================================
        // Title
        // =========================================

        title.withCString {

            pointer in


            id3tag_set_title(
                lame,
                pointer
            )
        }


        // =========================================
        // Artist
        // =========================================

        artist.withCString {

            pointer in


            id3tag_set_artist(
                lame,
                pointer
            )
        }


        // =========================================
        // Album
        // =========================================

        if let album,
           !album.isEmpty {

            album.withCString {

                pointer in


                id3tag_set_album(
                    lame,
                    pointer
                )
            }
        }


        // =========================================
        // Artwork
        // =========================================

        if let artworkData,
           !artworkData.isEmpty {

            artworkData.withUnsafeBytes {

                bytes in


                guard let baseAddress =
                    bytes.baseAddress
                else {

                    return
                }


                let pointer =
                    baseAddress
                        .assumingMemoryBound(
                            to:
                                CChar.self
                        )


                let artworkResult =
                    id3tag_set_albumart(

                        lame,

                        pointer,

                        artworkData.count
                    )


                print(
                    "ID3 artwork result:",
                    artworkResult
                )
            }
        }


        print(
            "ID3 configured:"
        )


        print(
            "Title:",
            title
        )


        print(
            "Artist:",
            artist
        )


        print(
            "Album:",
            album ?? "nil"
        )


        print(
            "Artwork:",
            artworkData?.count ?? 0,
            "bytes"
        )
    }


    // MARK: - Download Artwork

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
                        as?
                        HTTPURLResponse,

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


    // MARK: - Prepare Artwork For ID3

    private func prepareArtworkForID3(
        _ data: Data?
    ) -> Data? {

        guard let data,
              !data.isEmpty
        else {

            return nil
        }


        // Already small enough.

        if data.count <=
            24_000 {

            return data
        }


        guard let originalImage =
            UIImage(
                data:
                    data
            )
        else {

            return nil
        }


        // Try progressively smaller covers.

        let sizes:
            [CGFloat] = [

                300,
                240,
                200,
                160
            ]


        let qualities:
            [CGFloat] = [

                0.75,
                0.60,
                0.50,
                0.40,
                0.30
            ]


        for size in sizes {

            let scaledImage =
                resizeArtwork(

                    originalImage,

                    maxDimension:
                        size
                )


            for quality in qualities {

                guard let jpeg =
                    scaledImage
                        .jpegData(
                            compressionQuality:
                                quality
                        )
                else {

                    continue
                }


                if jpeg.count <=
                    24_000 {

                    return jpeg
                }
            }
        }


        // If the cover still cannot fit safely,
        // preserve title/artist/album instead of
        // risking the whole ID3 tag.

        print(
            "Artwork too large for safe LAME ID3 embedding; skipping embedded cover."
        )


        return nil
    }


    // MARK: - Resize Artwork

    private func resizeArtwork(
        _ image: UIImage,
        maxDimension: CGFloat
    ) -> UIImage {

        let width =
            image.size.width


        let height =
            image.size.height


        let largest =
            max(
                width,
                height
            )


        guard largest >
            maxDimension
        else {

            return image
        }


        let scale =
            maxDimension
            /
            largest


        let newSize =
            CGSize(

                width:
                    width
                    *
                    scale,

                height:
                    height
                    *
                    scale
            )


        let renderer =
            UIGraphicsImageRenderer(
                size:
                    newSize
            )


        return renderer.image {

            _ in


            image.draw(

                in:
                    CGRect(
                        origin:
                            .zero,

                        size:
                            newSize
                    )
            )
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


    // MARK: - Unique URL

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


        guard manager.fileExists(
            atPath:
                original.path
        )
        else {

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


            index +=
                1
        }
    }


    // MARK: - Diagnostic Stage

    private nonisolated static func setStage(
        _ stage: String
    ) {

        UserDefaults.standard
            .set(
                stage,
                forKey:
                    "fetchLastStage"
            )


        UserDefaults.standard
            .synchronize()
    }
}
