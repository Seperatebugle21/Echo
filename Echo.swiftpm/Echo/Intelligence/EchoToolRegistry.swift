import Foundation

struct EchoToolDefinition {
    let name: String
    let description: String
    let mutating: Bool
    var sensitive = false
    let properties: [String: [String: Any]]
    var required: [String] = []
    var wire: [String: Any] {
        ["type": "function", "function": ["name": name, "description": description,
          "parameters": ["type": "object", "properties": properties, "required": required, "additionalProperties": false]]]
    }
    func validate(_ json: String) throws -> [String: Any] {
        guard json.utf8.count <= 16_384, let data = json.data(using: .utf8),
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(value.keys).isSubset(of: Set(properties.keys)), required.allSatisfy({ value[$0] != nil }) else { throw AIError.invalidArguments }
        for (key, entry) in value {
            guard let schema = properties[key] else { throw AIError.invalidArguments }
            switch schema["type"] as? String {
            case "string":
                guard let text = entry as? String, text.count <= 1000 else { throw AIError.invalidArguments }
                if let options = schema["enum"] as? [String], !options.contains(text) { throw AIError.invalidArguments }
            case "number", "integer":
                guard let number = entry as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { throw AIError.invalidArguments }
                if schema["type"] as? String == "integer", number.doubleValue.rounded() != number.doubleValue { throw AIError.invalidArguments }
                if let min = schema["minimum"] as? Double, number.doubleValue < min { throw AIError.invalidArguments }
                if let max = schema["maximum"] as? Double, number.doubleValue > max { throw AIError.invalidArguments }
            case "boolean":
                guard let number = entry as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw AIError.invalidArguments }
            case "array":
                guard let list = entry as? [String], list.count <= 100, list.allSatisfy({ $0.count <= 200 }) else { throw AIError.invalidArguments }
            default: throw AIError.invalidArguments
            }
        }
        return value
    }
}
import CoreFoundation

enum EchoToolRegistry {
    static let text: [String: Any] = ["type": "string"]
    static let ids: [String: Any] = ["type": "array", "items": ["type": "string"], "maxItems": 100]
    static let boolean: [String: Any] = ["type": "boolean"]
    static func choice(_ values: [String]) -> [String: Any] { ["type": "string", "enum": values] }
    static func number(_ min: Double, _ max: Double) -> [String: Any] { ["type": "number", "minimum": min, "maximum": max] }
    static let all: [EchoToolDefinition] = [
        .init(name: "library_search", description: "Search real local music; returns IDs and metadata only, max 40 results. Query matches title, artist, album or genre. Filter and sort locally before sharing. Use returned IDs for actions.", mutating: false,
              properties: ["query": text, "genre": text, "artist": text, "album": text, "favorites": boolean, "sort": choice(["recommended", "mostPlayed", "leastPlayed", "recentAdded", "leastRecent"]), "yearFrom": number(0, 3000), "yearTo": number(0, 3000), "exclude": ids, "limit": ["type": "integer", "minimum": 1.0, "maximum": 40.0]]),
        .init(name: "playback_status", description: "Current track, playback state and upcoming queue IDs.", mutating: false, properties: [:]),
        .init(name: "play_songs", description: "Play real song IDs in order. Replaces current playback. For artist or album playback search first.", mutating: true, properties: ["songIDs": ids, "shuffle": boolean], required: ["songIDs"]),
        .init(name: "transport", description: "Control music or podcast playback.", mutating: true, properties: ["command": choice(["pause", "resume", "next", "previous"])] , required: ["command"]),
        .init(name: "seek", description: "Seek in seconds within the current track.", mutating: true, properties: ["seconds": number(0, 86400)], required: ["seconds"]),
        .init(name: "playback_options", description: "Set shuffle or repeat mode.", mutating: true, properties: ["shuffle": boolean, "repeat": choice(["off", "all", "one"])]),
        .init(name: "queue_edit", description: "Add/remove IDs or clear/replace upcoming songs, preserving the current track. Stops automatic Flow refill.", mutating: true, properties: ["operation": choice(["add", "remove", "clear", "replace"]), "songIDs": ids], required: ["operation"]),
        .init(name: "favorite", description: "Set favorite state of a song.", mutating: true, properties: ["songID": text, "enabled": boolean], required: ["songID", "enabled"]),
        .init(name: "playlists", description: "List existing playlists and their IDs, names, counts.", mutating: false, properties: [:]),
        .init(name: "playlist_create", description: "Create a named playlist with validated song IDs.", mutating: true, properties: ["name": text, "songIDs": ids], required: ["name", "songIDs"]),
        .init(name: "playlist_edit", description: "Rename, add, remove or reorder songs in a manual playlist. Reorder requires all current song IDs exactly once.", mutating: true, properties: ["playlistID": text, "operation": choice(["rename", "add", "remove", "reorder"]), "name": text, "songIDs": ids], required: ["playlistID", "operation"]),
        .init(name: "playlist_play", description: "Play an existing playlist; resolves smart playlists with the existing library.", mutating: true, properties: ["playlistID": text, "shuffle": boolean], required: ["playlistID"]),
        .init(name: "playlist_delete", description: "Delete a playlist only, never its music files. Always requires confirmation.", mutating: true, sensitive: true, properties: ["playlistID": text], required: ["playlistID"]),
        .init(name: "echo_flow", description: "Start or stop the existing adaptive Echo Flow. Uses listening feedback. Optional real seed song ID.", mutating: true, properties: ["enabled": boolean, "songID": text], required: ["enabled"]),
        .init(name: "dj_mix", description: "Start or refine a persistent DJ session. Filters actual metadata and ranks with Echo learning; no audio mood/tempo analysis. Query/exclusions persist until changed. Update upcoming songs without interrupting current playback and continue through filtered Echo Flow. Empty query clears the filter.", mutating: true, properties: ["query": text, "exclude": ids, "songIDs": ids, "startNow": boolean, "limit": ["type": "integer", "minimum": 1.0, "maximum": 100.0]]),
        .init(name: "podcast_search", description: "Search saved/cached episodes and subscriptions, including progress and download state. No web search.", mutating: false, properties: ["query": text]),
        .init(name: "podcast_action", description: "Play/resume, download, cancel download, subscribe or unsubscribe a known cached episode's show. Downloads report scheduled, not finished.", mutating: true, properties: ["episodeID": text, "operation": choice(["play", "download", "cancelDownload", "subscribe", "unsubscribe"])], required: ["episodeID", "operation"]),
        .init(name: "settings_change", description: "Values: appearance=system/light/dark/custom; equalizer=flat/bassBoost/bassReducer/trebleBoost/vocal/acoustic/pop/rock/electronic; crossfade=0 or 1–12 seconds; mono=true/false. Cannot change AI permissions or credentials.", mutating: true, properties: ["setting": choice(["appearance", "equalizer", "crossfade", "mono"]), "value": text], required: ["setting", "value"]),
        .init(name: "navigate", description: "Open an existing Echo screen and close Intelligence.", mutating: true, properties: ["screen": choice(["home", "library", "podcasts", "fetch", "search", "settings", "playlists", "favorites", "songs"])], required: ["screen"])
    ]
    static func definition(_ name: String) throws -> EchoToolDefinition {
        guard let tool = all.first(where: { $0.name == name }) else { throw AIError.invalidArguments }
        return tool
    }
}
