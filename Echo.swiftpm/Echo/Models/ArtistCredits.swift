import Foundation

struct ArtistGroup: Identifiable {
    let id: String
    let name: String
    let songs: [Song]

    init(name: String, songs: [Song]) {
        self.id = ArtistCredits.key(name)
        self.name = name
        self.songs = songs
    }
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

    private static let whitespace = try! NSRegularExpression(pattern: #"\s+"#)
    private static let featured = try! NSRegularExpression(
        pattern: #"(?i)\s*[\[(](?:feat\.?|ft\.?|featuring)\s+([^\])]+)[\])]"#
    )
    private static let separator = try! NSRegularExpression(
        pattern: #"(?i)\s*(?:,|;|&|\n)\s*|\s+(?:feat\.?|ft\.?|featuring|with|x|and|/)\s+"#
    )
    private static let protectedNames = compoundNames.enumerated().map { index, name in
        (
            name: name,
            marker: "ECHOCREDITPLACEHOLDER\(index)END",
            expression: try! NSRegularExpression(
                pattern: #"(?i)(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: name) + #"(?![\p{L}\p{N}])"#
            )
        )
    }

    private static func replacing(_ expression: NSRegularExpression, in value: String, with template: String) -> String {
        expression.stringByReplacingMatches(
            in: value, range: NSRange(value.startIndex..., in: value), withTemplate: template
        )
    }

    static func key(_ name: String) -> String {
        replacing(whitespace, in: name.trimmingCharacters(in: .whitespacesAndNewlines), with: " ")
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func names(in credit: String) -> [String] {
        var protected = replacing(featured, in: credit, with: ", $1")
        var replacements: [String: String] = [:]
        for entry in protectedNames {
            if entry.expression.firstMatch(in: protected, range: NSRange(protected.startIndex..., in: protected)) != nil {
                protected = replacing(entry.expression, in: protected, with: entry.marker)
                replacements[entry.marker] = entry.name
            }
        }
        // Never split an unspaced slash: AC/DC is a single artist.
        let divided = replacing(separator, in: protected, with: "\u{001F}")
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
        // Reference buckets avoid copying a growing song array/set on every insert.
        final class Bucket {
            let name: String
            var songs: [Song] = []
            var ids = Set<UUID>()
            init(name: String) { self.name = name }
        }
        var groups: [String: Bucket] = [:]
        var parsedCredits: [String: [String]] = [:]
        var keys: [String: String] = [:]
        for song in songs {
            let credits: [String]
            let structured = song.artistNames.map { unique($0) } ?? []
            if !structured.isEmpty {
                credits = structured
            } else if let cached = parsedCredits[song.artist] {
                credits = cached
            } else {
                credits = names(in: song.artist)
                parsedCredits[song.artist] = credits
            }
            for name in credits.isEmpty ? [unknownName] : credits {
                let id = keys[name] ?? key(name)
                keys[name] = id
                let group: Bucket
                if let existing = groups[id] {
                    group = existing
                } else {
                    group = Bucket(name: name)
                    groups[id] = group
                }
                if group.ids.insert(song.id).inserted { group.songs.append(song) }
            }
        }
        return groups.values.map { ArtistGroup(name: $0.name, songs: $0.songs) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
