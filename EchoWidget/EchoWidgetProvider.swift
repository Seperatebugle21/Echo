import Foundation
import WidgetKit

struct EchoWidgetEntry: TimelineEntry {

    let date: Date
    let snapshot: EchoWidgetSnapshot
}

struct EchoWidgetProvider: TimelineProvider {

    func placeholder(
        in context: Context
    ) -> EchoWidgetEntry {

        EchoWidgetEntry(
            date: Date(),
            snapshot: .empty
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (EchoWidgetEntry) -> Void
    ) {

        completion(
            EchoWidgetEntry(
                date: Date(),
                snapshot: EchoWidgetSnapshotStore.load()
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<EchoWidgetEntry>) -> Void
    ) {

        let entry = EchoWidgetEntry(
            date: Date(),
            snapshot: EchoWidgetSnapshotStore.load()
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
