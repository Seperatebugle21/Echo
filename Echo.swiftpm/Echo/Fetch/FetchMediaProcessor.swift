import Foundation
import AVFoundation

enum FetchMediaProcessingError: LocalizedError {
    case cannotCreateExporter
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .cannotCreateExporter:
            return "Echo kon de audio niet verwerken."

        case .exportFailed:
            return "Audio exporteren is mislukt."
        }
    }
}

@MainActor
final class FetchMediaProcessor {

    static let shared = FetchMediaProcessor()

    private init() {}


    func convertToM4A(
        sourceURL: URL,
        item: FetchItem
    ) async throws -> URL {

        let fileManager = FileManager.default

        let documents = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let fileName = sanitize(
            "\(item.title) - \(item.artist)"
        ) + ".m4a"

        let outputURL = uniqueURL(
            directory: documents,
            fileName: fileName
        )

        let asset = AVURLAsset(url: sourceURL)

        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw FetchMediaProcessingError.cannotCreateExporter
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a

        // Spotify metadata toevoegen
        exporter.metadata = await makeMetadata(
            for: item
        )

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in

            exporter.exportAsynchronously {

                switch exporter.status {

                case .completed:
                    continuation.resume()

                case .failed,
                     .cancelled:

                    continuation.resume(
                        throwing:
                            exporter.error ??
                            FetchMediaProcessingError.exportFailed
                    )

                default:
                    continuation.resume(
                        throwing:
                            FetchMediaProcessingError.exportFailed
                    )
                }
            }
        }

        return outputURL
    }


    // MARK: - Metadata

    private func makeMetadata(
        for item: FetchItem
    ) async -> [AVMetadataItem] {

        var metadata: [AVMetadataItem] = []


        // Title

        let titleItem = AVMutableMetadataItem()

        titleItem.identifier =
            .commonIdentifierTitle

        titleItem.value =
            item.title as NSString

        metadata.append(titleItem)


        // Artist

        let artistItem = AVMutableMetadataItem()

        artistItem.identifier =
            .commonIdentifierArtist

        artistItem.value =
            item.artist as NSString

        metadata.append(artistItem)


        // Album

        if let album = item.album {

            let albumItem =
                AVMutableMetadataItem()

            albumItem.identifier =
                .commonIdentifierAlbumName

            albumItem.value =
                album as NSString

            metadata.append(albumItem)
        }


        // Artwork

        if let artworkURL = item.artworkURL {

            do {

                let (data, response) =
                    try await URLSession.shared.data(
                        from: artworkURL
                    )

                if let http =
                    response as? HTTPURLResponse,
                   200..<300 ~= http.statusCode {

                    let artworkItem =
                        AVMutableMetadataItem()

                    artworkItem.identifier =
                        .commonIdentifierArtwork

                    artworkItem.value =
                        data as NSData

                    metadata.append(
                        artworkItem
                    )
                }

            } catch {

                print(
                    "Artwork downloaden mislukt:",
                    error
                )
            }
        }


        return metadata
    }


    // MARK: - Filename

    private func sanitize(
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
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }


    private func uniqueURL(
        directory: URL,
        fileName: String
    ) -> URL {

        let manager =
            FileManager.default

        let initial =
            directory.appendingPathComponent(
                fileName
            )

        if !manager.fileExists(
            atPath: initial.path
        ) {
            return initial
        }

        let file =
            URL(
                fileURLWithPath: fileName
            )

        let base =
            file
                .deletingPathExtension()
                .lastPathComponent

        let ext =
            file.pathExtension

        var number = 2

        while true {

            let candidate =
                directory.appendingPathComponent(
                    "\(base) \(number).\(ext)"
                )

            if !manager.fileExists(
                atPath: candidate.path
            ) {
                return candidate
            }

            number += 1
        }
    }
}
