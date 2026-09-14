import Foundation

enum EchoWidgetKinds {
    static let rounded = "com.echomusic.app.widget.player-rounded"
    static let cover = "com.echomusic.app.widget.player-cover"
    static let edge = "com.echomusic.app.widget.player-edge"
    static let compact = "com.echomusic.app.widget.player-compact"
    // Preserve the kind so existing recent-song widgets migrate to Quick Picks.
    static let quickPicks = "com.echomusic.app.widget.recent-songs"
    static let homeScreen = [rounded, cover, edge, compact, quickPicks]
}

struct EchoWidgetSongItem: Codable, Hashable, Identifiable {

    let id: UUID
    let title: String
    let artist: String
    let artworkData: Data?
    var isFavorite: Bool? = nil

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
    var currentSong: EchoWidgetSongItem? = nil
    var isPlaying: Bool? = nil

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
            throw CocoaError(.fileNoSuchFile)
        }

        let data = try JSONEncoder().encode(snapshot)

        try data.write(
            to: fileURL,
            options: [.atomic]
        )
    }

    static var isAvailable: Bool { fileURL != nil }

    private static var fileURL: URL? {

        FileManager.default
            .containerURL(
                forSecurityApplicationGroupIdentifier:
                    appGroupIdentifier
            )?
            .appendingPathComponent(fileName)
    }
}
