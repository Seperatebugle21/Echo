import Foundation

/// Only complete, unambiguous commands take this path. Quoted text, negation,
/// named songs and multi-step requests stay with the conversational provider.
struct AIQuickCommand {
    enum Action { case status, favorite(Bool), transport(String), playAny }
    let action: Action
    let dutch: Bool

    static func parse(_ input: String) -> Self? {
        guard !input.contains("\""), !input.contains("“"),
              !matches(input, "^\\s*['‘].*['’]\\s*$") else { return nil }
        let value = normalized(input)
            .replacingOccurrences(of: "^echo ", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^(kan je|kun je|wil je|kunt u|can you|could you|would you) ", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^(alsjeblieft|aub|please) ", with: "", options: .regularExpression)
            .replacingOccurrences(of: " (alsjeblieft|aub|please)$", with: "", options: .regularExpression)
        let nl: [(Action, [String])] = [
            (.status, ["wat speelt er", "wat speelt er nu", "wat is dit nummer", "welk nummer speelt er", "welk nummer speelt er nu", "welk liedje speelt er", "welk liedje speelt er nu", "welk nummer speelt nu", "welk liedje speelt nu", "wat luister ik nu", "wat is het huidige nummer", "welk nummer speelt nu af", "welk liedje speelt nu af", "wat wordt er nu afgespeeld"]),
            (.transport("pause"), ["pauze", "pauzeer", "pauzeer de muziek", "pauzeer dit nummer", "stop de muziek"]),
            (.transport("resume"), ["hervat", "hervat de muziek", "speel verder", "ga verder met de muziek"]),
            (.transport("next"), ["volgende", "volgend nummer", "volgende nummer", "volgende liedje", "volgend liedje", "speel het volgende nummer", "speel het volgende liedje", "het volgende nummer afspelen", "het volgende liedje afspelen", "sla dit nummer over", "sla dit liedje over"]),
            (.transport("previous"), ["vorige", "vorig nummer", "vorige nummer", "vorig liedje", "vorige liedje", "speel het vorige nummer", "speel het vorige liedje", "het vorige nummer afspelen", "het vorige liedje afspelen"]),
            (.playAny, ["speel een nummer", "speel een liedje", "speel een willekeurig nummer", "speel een willekeurig liedje", "speel een random nummer", "speel een random liedje"])
        ]
        let en: [(Action, [String])] = [
            (.status, ["whats playing", "whats playing now", "what is playing", "what is playing now", "what song is this", "what song is playing", "what song is playing now", "current song"]),
            (.transport("pause"), ["pause", "pause music", "pause the music", "pause playback", "pause this song", "stop the music"]),
            (.transport("resume"), ["resume", "resume music", "resume playback", "continue playing"]),
            (.transport("next"), ["next", "next song", "next track", "skip this song", "skip this track", "play the next song"]),
            (.transport("previous"), ["previous", "previous song", "previous track", "play the previous song"]),
            (.playAny, ["play a song", "play any song", "play a random song"])
        ]
        for (action, phrases) in nl where phrases.contains(value) { return Self(action: action, dutch: true) }
        for (action, phrases) in en where phrases.contains(value) { return Self(action: action, dutch: false) }
        let currentNL = "(?:dit|dit nummer|dit liedje|deze track|deze song|het huidige nummer|het huidige liedje)"
        if matches(value, "^(?:(?:zet|markeer) \(currentNL) (?:als (?:een )?(?:favoriet|favorite)|(?:in|bij) (?:mijn |de )?(?:favorieten|favorites))|maak \(currentNL) (?:een )?(?:favoriet|favorite)|voeg \(currentNL) toe aan (?:mijn |de )?(?:favorieten|favorites)|\(currentNL) (?:als )?(?:een )?(?:favoriet|favorite) (?:maken|zetten|markeren))$") {
            return Self(action: .favorite(true), dutch: true)
        }
        if matches(value, "^(?:(?:haal|verwijder) \(currentNL) uit (?:mijn |de )?favorieten|maak \(currentNL) geen favoriet)$") {
            return Self(action: .favorite(false), dutch: true)
        }
        let currentEN = "(?:this|this song|this track|the current song|the current track)"
        if matches(value, "^(?:(?:favorite|favourite) \(currentEN)|(?:mark|make) \(currentEN) (?:as )?(?:a )?(?:favorite|favourite)|add \(currentEN) to (?:my )?(?:favorites|favourites))$") {
            return Self(action: .favorite(true), dutch: false)
        }
        if matches(value, "^(?:(?:unfavorite|unfavourite) \(currentEN)|remove \(currentEN) from (?:my )?(?:favorites|favourites))$") {
            return Self(action: .favorite(false), dutch: false)
        }
        return nil
    }

    /// A named favorite still needs real library IDs, but cannot become a skip.
    /// Keep all tools for conjunctions/complex requests rather than misrouting them.
    static func focusedTools(for input: String) -> Set<String>? {
        let value = normalized(input)
            .replacingOccurrences(of: "^(?:echo )?(?:kan je|kun je|wil je|kunt u|can you|could you|would you) ", with: "", options: .regularExpression)
            .replacingOccurrences(of: " (alsjeblieft|aub|please)$", with: "", options: .regularExpression)
        guard value.count < 200,
              !matches(value, "\\b(en|and|then|daarna|maar|but|niet|not|mix|flow)\\b") else { return nil }
        if matches(value, "^(?:(?:maak|markeer|zet) .+ (?:als )?(?:een )?(?:favoriet|favorite)|(?:zet|markeer) .+ (?:in|bij) (?:mijn |de )?(?:favorieten|favorites)|(?:haal|verwijder) .+ uit (?:mijn |de )?favorieten|voeg .+ toe aan (?:mijn |de )?favorieten|.+ (?:als )?(?:een )?favoriet (?:maken|zetten|markeren)|(?:favorite|favourite|unfavorite|unfavourite) .+|(?:mark|make) .+ (?:as )?(?:a )?(?:favorite|favourite)|add .+ to (?:my )?(?:favorites|favourites)|remove .+ from (?:my )?(?:favorites|favourites))$") {
            return ["library_search", "playback_status", "favorite"]
        }
        return nil
    }

    func call(songID: UUID? = nil) throws -> AIToolCall {
        let name: String, arguments: [String: Any]
        switch action {
        case .status: name = "playback_status"; arguments = [:]
        case .favorite(let enabled): name = "favorite"; arguments = ["enabled": enabled]
        case .transport(let command): name = "transport"; arguments = ["command": command]
        case .playAny:
            guard let songID else { throw AIError.missing }
            name = "play_songs"; arguments = ["songIDs": [songID.uuidString], "shuffle": false]
        }
        return AIToolCall(id: UUID().uuidString, name: name,
                          arguments: String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self))
    }

    func reply(to result: String) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any] else { throw AIError.response }
        if object["status"] as? String == "failed" { return object["reason"] as? String ?? AIError.response.localizedDescription }
        if object["status"] as? String == "denied_by_user" { return dutch ? "De opdracht is niet uitgevoerd." : "The action was not performed." }
        switch action {
        case .status:
            guard let song = object["current"] as? [String: Any], let title = song["title"] as? String else {
                return dutch ? "Er is momenteel geen nummer geselecteerd." : "No song is currently selected."
            }
            let artist = song["artist"] as? String ?? ""
            let paused = object["isPlaying"] as? Bool == true ? "" : (dutch ? " (gepauzeerd)" : " (paused)")
            return (dutch ? "Nu: " : "Now: ") + title + (artist.isEmpty ? "" : " · " + artist) + paused
        case .favorite(let enabled):
            let title = (object["song"] as? [String: Any])?["title"] as? String ?? (dutch ? "Dit nummer" : "This song")
            return title + (dutch ? (enabled ? " staat nu bij je favorieten." : " is uit je favorieten verwijderd.") : (enabled ? " is now a favorite." : " was removed from your favorites."))
        case .playAny:
            guard let title = (object["song"] as? [String: Any])?["title"] as? String else { throw AIError.response }
            return (dutch ? "Speelt: " : "Playing: ") + title
        case .transport(let command):
            if ["next", "previous"].contains(command),
               let title = (object["song"] as? [String: Any])?["title"] as? String {
                let paused = object["isPlaying"] as? Bool == true ? "" : (dutch ? " (gepauzeerd)" : " (paused)")
                return (dutch ? "Nu geselecteerd: " : "Selected: ") + title + paused
            }
            switch command {
            case "pause": return dutch ? "Muziek gepauzeerd." : "Music paused."
            case "resume": return dutch ? "Muziek hervat." : "Music resumed."
            case "next": return dutch ? "De opdracht ‘volgende’ is uitgevoerd." : "The next command was performed."
            default: return dutch ? "De opdracht ‘vorige’ is uitgevoerd." : "The previous command was performed."
            }
        }
    }

    private static func normalized(_ input: String) -> String {
        input.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "['’]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[.!?,;:]", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
