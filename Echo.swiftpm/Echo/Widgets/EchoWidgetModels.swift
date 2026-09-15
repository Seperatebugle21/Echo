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

    // SideStore/AltStore writes the provisioned groups to each bundle's
    // ALTAppGroups after re-signing. Do not guess a team ID from the bundle ID.
    static func containerURL(
        installedGroups: [String],
        lookup: (String) -> URL?
    ) -> URL? {
        let remapped = Set(installedGroups.filter {
            $0.hasPrefix(appGroupIdentifier + ".") && $0.count > appGroupIdentifier.count + 1
        }).sorted()
        // Prefer the installed mapping over a potentially stale original group.
        // The original remains the fallback for Xcode/TestFlight/enterprise.
        for identifier in remapped + [appGroupIdentifier] {
            if let url = lookup(identifier) { return url }
        }
        return nil
    }

    private static var fileURL: URL? {
        let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        return containerURL(installedGroups: groups) { identifier in
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        }?.appendingPathComponent(fileName)
    }
}
