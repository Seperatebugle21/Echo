import Foundation
import ImageIO
import UniformTypeIdentifiers
import WidgetKit

enum EchoWidgetSnapshotPublisher {

    static func publish(songs: [Song]) {

        let selectedSongs = widgetSongs(from: songs)

        let items = selectedSongs.map { song in
            EchoWidgetSongItem(
                id: song.id,
                title: song.title,
                artist: song.artist,
                artworkData: thumbnailData(
                    from: song.coverData
                        ?? song.imageData
                )
            )
        }

        do {
            try EchoWidgetSnapshotStore.save(
                EchoWidgetSnapshot(
                    updatedAt: Date(),
                    songs: items
                )
            )

            WidgetCenter.shared.reloadAllTimelines()

        } catch {
            print(
                "Widget snapshot opslaan mislukt:",
                error.localizedDescription
            )
        }
    }

    private static func widgetSongs(
        from songs: [Song]
    ) -> [Song] {

        let recentlyPlayed = songs
            .filter { $0.lastPlayed != nil }
            .sorted {
                ($0.lastPlayed ?? .distantPast)
                    >
                ($1.lastPlayed ?? .distantPast)
            }

        let recentlyAdded = songs.sorted {
            $0.dateAdded > $1.dateAdded
        }

        var result: [Song] = []
        var includedIDs = Set<UUID>()

        for song in recentlyPlayed + recentlyAdded {
            guard includedIDs.insert(song.id).inserted else {
                continue
            }

            result.append(song)

            if result.count == 4 {
                break
            }
        }

        return result
    }

    private static func thumbnailData(
        from data: Data?
    ) -> Data? {

        guard
            let data,
            let source = CGImageSourceCreateWithData(
                data as CFData,
                nil
            )
        else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 360
        ]

        guard
            let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            )
        else {
            return nil
        }

        let output = NSMutableData()

        guard
            let destination = CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            return nil
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [
                kCGImageDestinationLossyCompressionQuality:
                    0.82
            ] as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return output as Data
    }
}
