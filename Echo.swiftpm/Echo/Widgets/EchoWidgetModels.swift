import Foundation

struct EchoWidgetSongItem: Codable, Hashable, Identifiable {

    let id: UUID
    let title: String
    let artist: String
    let artworkData: Data?

    var playbackURL: URL {
        var components = URLComponents()
        components.scheme = "echo"
        components.host = "play"
        components.queryItems = [
            URLQueryItem(
                name: "id",
                value: id.uuidString
            )
        ]

        return components.url
            ?? URL(string: "echo://open")!
    }
}

struct EchoWidgetSnapshot: Codable, Hashable {

    let updatedAt: Date
    let songs: [EchoWidgetSongItem]

    static let empty = EchoWidgetSnapshot(
        updatedAt: .distantPast,
        songs: []
    )
}

enum EchoWidgetSnapshotStore {

    static let appGroupIdentifier =
        "group.com.echomusic.app"

    private static let fileName =
        "EchoWidgetSnapshot.json"

    static func load() -> EchoWidgetSnapshot {

        guard
            let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let snapshot = try? JSONDecoder().decode(
                EchoWidgetSnapshot.self,
                from: data
            )
        else {
            return .empty
        }

        return snapshot
    }

    static func save(_ snapshot: EchoWidgetSnapshot) throws {

        guard let fileURL else {
            return
        }

        let data = try JSONEncoder().encode(snapshot)

        try data.write(
            to: fileURL,
            options: [.atomic]
        )
    }

    private static var fileURL: URL? {

        FileManager.default
            .containerURL(
                forSecurityApplicationGroupIdentifier:
                    appGroupIdentifier
            )?
            .appendingPathComponent(fileName)
    }
}
