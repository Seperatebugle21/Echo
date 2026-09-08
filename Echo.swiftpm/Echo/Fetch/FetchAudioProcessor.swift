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
            return "The downloaded file does not contain an audio track."

        case .cannotCreateReader:
            return "Echo could not start the audio decoder."

        case .cannotAddReaderOutput:
            return "Echo could not configure the PCM audio output."

        case .readerFailed(let message):
            return "Audio decoding failed: \(message)"

        case .cannotCreateMP3:
            return "Echo could not create the temporary MP3 file."

        case .cannotMoveFinalMP3(let message):
            return "The finished MP3 could not be moved to the library: \(message)"

        case .lameInitializationFailed:
            return "The MP3 encoder could not be started."

        case .lameConfigurationFailed(let setting):
            return "The MP3 encoder could not configure '\(setting)'."

        case .lameEncodingFailed(let code):
            return "MP3 encoding failed. LAME code: \(code)"
        }
    }
}


// MARK: - Snapshot

private struct FetchMP3Snapshot: Sendable {

    let sourceURL:
        URL

    let temporaryMP3URL:
        URL

    let bitrate:
        Int

    let title:
        String

    let artist:
        String

    let album:
        String?

    let artworkData:
        Data?
}


// MARK: - Processor

@MainActor
final class FetchAudioProcessor {

    static let shared =
        FetchAudioProcessor()


    private init() {}


    func process(
        sourceURL: URL,
        item: FetchItem,
        quality: FetchQuality,
        progress:
            @escaping
            @MainActor
            (Double) -> Void
    ) async throws -> FetchProcessedAudio {

        progress(
            0.01
        )


        let manager =
            FileManager.default


        let documents =
            manager.urls(
                for:
                    .documentDirectory,
                in:
                    .userDomainMask
            )[0]


        let finalName =
            safeFileName(
                "\(item.title) - \(item.artist).mp3"
            )


        let finalURL =
            uniqueURL(
                directory:
                    documents,
                filename:
                    finalName
            )


        // MARK: Temporary MP3

        let temporaryDirectory =
            manager
                .temporaryDirectory
                .appendingPathComponent(
                    "EchoMP3Processing",
                    isDirectory:
                        true
                )


        try manager
            .createDirectory(
                at:
                    temporaryDirectory,
                withIntermediateDirectories:
                    true
            )


        let temporaryMP3URL =
            temporaryDirectory
                .appendingPathComponent(
                    "\(UUID().uuidString).mp3"
                )


        // MARK: Artwork

        let originalArtwork:
            Data?


        if FetchSettings.shared
            .embedArtwork {

            originalArtwork =
                await downloadArtwork(
                    item.artworkURL
                )

        } else {

            originalArtwork =
                nil
        }


        let id3Artwork =
            prepareArtworkForID3(
                originalArtwork
            )


        progress(
            0.05
        )


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
                    id3Artwork
            )


        let progressBridge:
            @Sendable
            (Double) -> Void = {
                value in


                Task {
                    @MainActor in

                    progress(
                        value
                    )
                }
            }


        do {

            // Higher priority than before.
            // Encoding is user-visible work.

            try await Task.detached(
                priority:
                    .userInitiated
            ) {

                try await Self
                    .encodeInBackground(
                        snapshot,
                        progress:
                            progressBridge
                    )

            }.value

        } catch {

            try? manager
                .removeItem(
                    at:
                        temporaryMP3URL
                )

            throw error
        }


        progress(
            0.97
        )


        // Only expose a fully finished MP3
        // in Documents.

        do {

            try manager
                .moveItem(
                    at:
                        temporaryMP3URL,
                    to:
                        finalURL
                )

        } catch {

            try? manager
                .removeItem(
                    at:
                        temporaryMP3URL
                )


            throw FetchProcessingError
                .cannotMoveFinalMP3(
                    error.localizedDescription
                )
        }


        progress(
            1
        )


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
                originalArtwork
        )
    }


    // MARK: - Background Encoding

    private nonisolated static func encodeInBackground(
        _ snapshot: FetchMP3Snapshot,
        progress:
            @escaping
            @Sendable
            (Double) -> Void
    ) async throws {

        progress(
            0.08
        )


        let asset =
            AVURLAsset(
                url:
                    snapshot.sourceURL
            )


        let tracks =
            try await
            asset.loadTracks(
                withMediaType:
                    .audio
            )


        guard let audioTrack =
            tracks.first
        else {

            throw FetchProcessingError
                .noAudioTrack
        }


        let duration =
            try await asset
                .load(
                    .duration
                )


        let durationSeconds =
            max(
                CMTimeGetSeconds(
                    duration
                ),
                0.001
            )


        progress(
            0.10
        )


        let reader =
            try AVAssetReader(
                asset:
                    asset
            )


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


        // MARK: LAME

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


        guard lame_set_in_samplerate(
            lame,
            44_100
        ) >= 0 else {

            throw FetchProcessingError
                .lameConfigurationFailed(
                    "sample rate"
                )
        }


        guard lame_set_num_channels(
            lame,
            2
        ) >= 0 else {

            throw FetchProcessingError
                .lameConfigurationFailed(
                    "channels"
                )
        }


        guard lame_set_brate(
            lame,
            Int32(
                snapshot.bitrate
            )
        ) >= 0 else {

            throw FetchProcessingError
                .lameConfigurationFailed(
                    "bitrate"
                )
        }


        // 0 = slowest/best algorithm.
        // 9 = fastest.
        //
        // 5 is considerably faster than 2 while
        // maintaining very good output quality.

        guard lame_set_quality(
            lame,
            5
        ) >= 0 else {

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


        // MARK: Output

        let manager =
            FileManager.default


        if manager.fileExists(
            atPath:
                snapshot
                    .temporaryMP3URL
                    .path
        ) {

            try manager
                .removeItem(
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


        let output =
            try FileHandle(
                forWritingTo:
                    snapshot
                        .temporaryMP3URL
            )


        defer {

            try? output.close()
        }


        guard reader.startReading()
        else {

            throw FetchProcessingError
                .readerFailed(
                    reader.error?
                        .localizedDescription
                    ??
                    "AVAssetReader could not start."
                )
        }


        progress(
            0.15
        )


        var lastReported =
            0.15


        // Reuse one MP3 buffer for the entire
        // song instead of allocating 128 KB
        // for every sample buffer.

        var reusableMP3Buffer =
            [UInt8](
                repeating:
                    0,
                count:
                    128 * 1024
            )


        // MARK: Actual Encoding

        while reader.status ==
            .reading {

            var processingError:
                Error?

            var timestampSeconds:
                Double?


            let received =
                autoreleasepool {

                    guard let sampleBuffer =
                        readerOutput
                            .copyNextSampleBuffer()
                    else {

                        return false
                    }


                    let timestamp =
                        CMSampleBufferGetPresentationTimeStamp(
                            sampleBuffer
                        )


                    if timestamp.isValid {

                        timestampSeconds =
                            CMTimeGetSeconds(
                                timestamp
                            )
                    }


                    do {

                        try encodeSampleBuffer(
                            sampleBuffer,
                            lame:
                                lame,
                            outputFile:
                                output,
                            mp3Buffer:
                                &reusableMP3Buffer
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


            if !received {

                break
            }


            if
                let timestampSeconds,
                timestampSeconds.isFinite {

                let songProgress =
                    min(
                        max(
                            timestampSeconds
                            /
                            durationSeconds,
                            0
                        ),
                        1
                    )


                let value =
                    0.15
                    +
                    (
                        songProgress
                        *
                        0.75
                    )


                // Reduce main-thread/UI traffic.
                // 1% updates are plenty for the UI.

                if value -
                    lastReported >=
                    0.01 {

                    lastReported =
                        value


                    progress(
                        value
                    )
                }
            }
        }


        switch reader.status {

        case .completed:

            break


        case .failed:

            throw FetchProcessingError
                .readerFailed(
                    reader.error?
                        .localizedDescription
                    ??
                    "Unknown decoder error."
                )


        case .cancelled:

            throw FetchProcessingError
                .readerFailed(
                    "Audio decoding was cancelled."
                )


        default:

            break
        }


        progress(
            0.92
        )


        // MARK: Flush

        var flushBuffer =
            [UInt8](
                repeating:
                    0,
                count:
                    128 * 1024
            )


        let flushed =
            flushBuffer
                .withUnsafeMutableBufferPointer {
                    buffer -> Int32 in


                    guard let destination =
                        buffer.baseAddress
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


        guard flushed >= 0 else {

            throw FetchProcessingError
                .lameEncodingFailed(
                    flushed
                )
        }


        if flushed > 0 {

            try flushBuffer
                .withUnsafeBytes {
                    bytes in


                    guard let base =
                        bytes.baseAddress
                    else {

                        return
                    }


                    let data =
                        Data(
                            bytes:
                                base,
                            count:
                                Int(
                                    flushed
                                )
                        )


                    try output.write(
                        contentsOf:
                            data
                    )
                }
        }


        try output
            .synchronize()


        progress(
            0.96
        )
    }


    // MARK: - PCM -> LAME

    private nonisolated static func encodeSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        lame: OpaquePointer,
        outputFile: FileHandle,
        mp3Buffer: inout [UInt8]
    ) throws {

        guard let dataBuffer =
            CMSampleBufferGetDataBuffer(
                sampleBuffer
            )
        else {

            throw FetchProcessingError
                .readerFailed(
                    "PCM buffer contains no data."
                )
        }


        let samples =
            CMSampleBufferGetNumSamples(
                sampleBuffer
            )


        guard samples > 0 else {

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
                    "PCM buffer could not be read."
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


        let calculatedSize =
            Int(
                1.25 *
                Double(
                    samples
                )
            )
            +
            7200


        let requiredSize =
            max(
                calculatedSize,
                128 * 1024
            )


        if mp3Buffer.count <
            requiredSize {

            mp3Buffer =
                [UInt8](
                    repeating:
                        0,
                    count:
                        requiredSize
                )
        }


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
                            samples
                        ),
                        destination,
                        Int32(
                            buffer.count
                        )
                    )
                }


        guard encoded >= 0 else {

            throw FetchProcessingError
                .lameEncodingFailed(
                    encoded
                )
        }


        if encoded > 0 {

            try mp3Buffer
                .withUnsafeBytes {
                    bytes in


                    guard let base =
                        bytes.baseAddress
                    else {

                        return
                    }


                    let data =
                        Data(
                            bytes:
                                base,
                            count:
                                Int(
                                    encoded
                                )
                        )


                    try outputFile.write(
                        contentsOf:
                            data
                    )
                }
        }
    }


    // MARK: - ID3

    private nonisolated static func configureMetadata(
        lame: OpaquePointer,
        title: String,
        artist: String,
        album: String?,
        artworkData: Data?
    ) {

        id3tag_init(
            lame
        )


        id3tag_add_v2(
            lame
        )


        title.withCString {

            id3tag_set_title(
                lame,
                $0
            )
        }


        artist.withCString {

            id3tag_set_artist(
                lame,
                $0
            )
        }


        if
            let album,
            !album.isEmpty {

            album.withCString {

                id3tag_set_album(
                    lame,
                    $0
                )
            }
        }


        if
            let artworkData,
            !artworkData.isEmpty {

            artworkData
                .withUnsafeBytes {
                    bytes in


                    guard let address =
                        bytes.baseAddress
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


                    print(
                        "ID3 artwork:",
                        result
                    )
                }
        }
    }


    // MARK: - Artwork Download

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
                        as?
                        HTTPURLResponse,
                200..<300 ~=
                    response.statusCode
            else {

                return nil
            }


            return data

        } catch {

            print(
                "Artwork failed:",
                error
            )


            return nil
        }
    }


    // MARK: - Artwork Compression

    private func prepareArtworkForID3(
        _ data: Data?
    ) -> Data? {

        guard
            let data,
            !data.isEmpty
        else {

            return nil
        }


        if data.count <=
            24_000 {

            return data
        }


        guard let image =
            UIImage(
                data:
                    data
            )
        else {

            return nil
        }


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

            let resized =
                resizeArtwork(
                    image,
                    maxDimension:
                        size
                )


            for quality in qualities {

                guard let jpeg =
                    resized.jpegData(
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


        return nil
    }


    private func resizeArtwork(
        _ image: UIImage,
        maxDimension: CGFloat
    ) -> UIImage {

        let largest =
            max(
                image.size.width,
                image.size.height
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


        let size =
            CGSize(
                width:
                    image.size.width
                    *
                    scale,
                height:
                    image.size.height
                    *
                    scale
            )


        return UIGraphicsImageRenderer(
            size:
                size
        )
        .image {
            _ in


            image.draw(
                in:
                    CGRect(
                        origin:
                            .zero,
                        size:
                            size
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


            index +=
                1
        }
    }
}
