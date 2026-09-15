import Foundation

struct ArtistGroup: Identifiable {
    var id: String { ArtistCredits.key(name) }
    let name: String
    let songs: [Song]
}

enum ArtistCredits {
    // These separators are also part of some established artist names.
    // Structured credits, when available, always take precedence over this fallback.
    private static let compoundNames = [
        "Earth, Wind & Fire", "Tyler, The Creator", "Crosby, Stills & Nash",
        "Crosby, Stills, Nash & Young", "Simon & Garfunkel", "Hall & Oates",
        "Daryl Hall & John Oates", "Florence & The Machine", "Belle & Sebastian",
        "Of Monsters and Men", "Years & Years", "Angus & Julia Stone",
        "KC & The Sunshine Band", "Huey Lewis & The News", "Kool & The Gang",
        "The Mamas & The Papas", "Mumford & Sons", "CHAGE and ASKA"
    ].sorted { $0.count > $1.count }

    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func names(in credit: String) -> [String] {
        var protected = credit.replacingOccurrences(
            of: #"(?i)\s*[\[(](?:feat\.?|ft\.?|featuring)\s+([^\])]+)[\])]"#,
            with: ", $1", options: .regularExpression
        )
        var replacements: [String: String] = [:]
        for (index, name) in compoundNames.enumerated() {
            let pattern = #"(?i)(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: name) + #"(?![\p{L}\p{N}])"#
            let marker = "ECHOCREDITPLACEHOLDER\(index)END"
            if protected.range(of: pattern, options: .regularExpression) != nil {
                protected = protected.replacingOccurrences(of: pattern, with: marker, options: .regularExpression)
                replacements[marker] = name
            }
        }
        // Never split an unspaced slash: AC/DC is a single artist.
        let separator = #"(?i)\s*(?:,|;|&|\n)\s*|\s+(?:feat\.?|ft\.?|featuring|with|x|and|/)\s+"#
        let divided = protected.replacingOccurrences(of: separator, with: "\u{001F}", options: .regularExpression)
        return unique(divided.components(separatedBy: "\u{001F}").map { value in
            var name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            for (marker, original) in replacements { name = name.replacingOccurrences(of: marker, with: original) }
            return name
        })
    }

    static func names(for song: Song) -> [String] {
        if let credits = song.artistNames {
            let names = unique(credits)
            if !names.isEmpty { return names }
        }
        return names(in: song.artist)
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(key($0)).inserted }
    }

    static func groups(for songs: [Song], unknownName: String) -> [ArtistGroup] {
        var groups: [String: (name: String, songs: [Song], ids: Set<UUID>)] = [:]
        for song in songs {
            let credits = names(for: song)
            for name in credits.isEmpty ? [unknownName] : credits {
                let id = key(name)
                var group = groups[id] ?? (name, [], [])
                if group.ids.insert(song.id).inserted { group.songs.append(song) }
                groups[id] = group
            }
        }
        return groups.values.map { ArtistGroup(name: $0.name, songs: $0.songs) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
