import Foundation
import WidgetKit
import UIKit

struct EchoWidgetEntry: TimelineEntry {

    let date: Date
    let snapshot: EchoWidgetSnapshot
    var sharedContainerAvailable: Bool = true
}

extension EchoWidgetSnapshot {
    // Gallery-only art: never substituted for a user's real library snapshot.
    static var preview: EchoWidgetSnapshot {
        let names = ["Late Night", "Ocean Blue", "Afterglow", "Soft Focus"]
        let colors: [UIColor] = [.systemPurple, .systemTeal, .systemOrange, .systemIndigo]
        let songs = names.enumerated().map { index, title in
            let artwork = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).image { context in
                colors[index].setFill()
                context.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
                UIColor.white.withAlphaComponent(0.22).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 55, y: 25, width: 200, height: 200))
                UIColor.black.withAlphaComponent(0.3).setFill()
                context.fill(CGRect(x: 0, y: 155, width: 240, height: 85))
            }
            return EchoWidgetSongItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index + 1)")!,
                title: title, artist: "Echo Sessions", artworkData: artwork.jpegData(compressionQuality: 0.8),
                isFavorite: index == 0
            )
        }
        return EchoWidgetSnapshot(updatedAt: Date(), songs: songs, currentSong: songs.first, isPlaying: true)
    }
}

struct EchoWidgetProvider: TimelineProvider {

    func placeholder(
        in context: Context
    ) -> EchoWidgetEntry {

        EchoWidgetEntry(
            date: Date(),
            snapshot: .preview
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (EchoWidgetEntry) -> Void
    ) {

        completion(
            EchoWidgetEntry(
                date: Date(),
                snapshot: context.isPreview ? .preview : EchoWidgetSnapshotStore.load(),
                sharedContainerAvailable: context.isPreview || EchoWidgetSnapshotStore.isAvailable
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<EchoWidgetEntry>) -> Void
    ) {

        let entry = EchoWidgetEntry(
            date: Date(),
            snapshot: EchoWidgetSnapshotStore.load(),
            sharedContainerAvailable: EchoWidgetSnapshotStore.isAvailable
        )

        completion(
            Timeline(
                entries: [entry],
                policy: .after(
                    Date().addingTimeInterval(6 * 60 * 60)
                )
            )
        )
    }
}
