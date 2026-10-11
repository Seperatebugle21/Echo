import Foundation
#if canImport(FoundationModels)
import FoundationModels

/// Common intents have their own native schemas. Foundation Models does not
/// have to invent a JSON string or select an unrelated action for these requests.
@available(iOS 26.0, *)
struct AppleActionBridge {
    let executor: @MainActor (AIToolCall) async throws -> String
    func run(_ name: String, _ arguments: [String: Any]) async throws -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: arguments)
            return try await executor(AIToolCall(id: UUID().uuidString, name: name, arguments: String(decoding: data, as: UTF8.self)))
        } catch is CancellationError { throw CancellationError() }
        catch { return try AIToolFailure.result(error, action: name) }
    }
}

@available(iOS 26.0, *)
struct ApplePlaybackStatusTool: Tool {
    let name = "playback_status"
    let description = "Read the real song currently playing, artist, song ID, favorite state, playback position and upcoming queue. Use for questions about what is playing. Does not change playback."
    let bridge: AppleActionBridge
    @Generable struct Arguments {
        @Guide(description: "Set true to read current playback and the upcoming queue.") var includeUpcoming: Bool
    }
    func call(arguments: Arguments) async throws -> String { try await bridge.run(name, [:]) }
}

@available(iOS 26.0, *)
struct AppleLibrarySearchTool: Tool {
    let name = "library_search"
    let description = "Find real songs in the local library. Query matches title, artist, album or genre. Empty query lists music. Returns real song IDs for play_songs and favorite. This only reads the library."
    let bridge: AppleActionBridge
    @Generable struct Arguments {
        @Guide(description: "The requested title, artist, album or genre; empty for any song.") var query: String
        @Guide(description: "Requested ordering, recommended unless the user specifies otherwise.", .anyOf(["recommended", "mostPlayed", "leastPlayed", "recentAdded", "leastRecent"])) var sort: String
        @Guide(description: "Maximum number of matching songs to return.", .range(1...40)) var limit: Int
    }
    func call(arguments: Arguments) async throws -> String {
        try await bridge.run(name, ["query": arguments.query, "sort": arguments.sort, "limit": arguments.limit])
    }
}

@available(iOS 26.0, *)
struct ApplePlaySongsTool: Tool {
    let name = "play_songs"
    let description = "Start playing one or more songs found by library_search. Use the exact returned IDs. For 'play a song', search with an empty query and pick a real result. Never use this for favoriting or questions about playback."
    let bridge: AppleActionBridge
    @Generable struct Arguments {
        @Guide(description: "Exact song IDs returned by library_search, in playback order.") var songIDs: [String]
        @Guide(description: "True only if the user explicitly requests shuffle.") var shuffle: Bool
    }
    func call(arguments: Arguments) async throws -> String {
        try await bridge.run(name, ["songIDs": arguments.songIDs, "shuffle": arguments.shuffle])
    }
}

@available(iOS 26.0, *)
struct AppleTransportTool: Tool {
    let name = "transport"
    let description = "Pause, resume, next or previous. Next/previous only when explicitly asked to skip/change the track. Favoriting a song must use favorite and must never skip or start another song."
    let bridge: AppleActionBridge
    @Generable struct Arguments {
        @Guide(description: "The explicit playback command.", .anyOf(["pause", "resume", "next", "previous"])) var command: String
    }
    func call(arguments: Arguments) async throws -> String { try await bridge.run(name, ["command": arguments.command]) }
}

@available(iOS 26.0, *)
struct AppleFavoriteTool: Tool {
    let name = "favorite"
    let description = "Mark or unmark a song as favorite without changing playback or skipping. For 'make this a favorite', omit songID to target the current song. For a named song, search first and use its real ID."
    let bridge: AppleActionBridge
    @Generable struct Arguments {
        @Guide(description: "True to mark as favorite, false only to remove from favorites.") var enabled: Bool
        @Guide(description: "Omit for the song currently playing; otherwise an exact ID from library_search.") var songID: String?
    }
    func call(arguments: Arguments) async throws -> String {
        var values: [String: Any] = ["enabled": arguments.enabled]
        if let id = arguments.songID { values["songID"] = id }
        return try await bridge.run(name, values)
    }
}
#endif
