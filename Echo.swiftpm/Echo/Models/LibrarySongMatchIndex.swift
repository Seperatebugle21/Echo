import Foundation

/// Build once per library revision instead of normalizing every song for every row.
struct LibrarySongMatchIndex {
    struct Key: Hashable {
        let title: String
        let artist: String
        init(title: String, artist: String) {
            self.title = Self.normalize(title)
            self.artist = Self.normalize(artist)
        }
        private static func normalize(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).lowercased()
        }
    }
    private let songs: [Key: Song]
    init(_ songs: [Song] = []) {
        self.songs = Dictionary(songs.map { (Key(title: $0.title, artist: $0.artist), $0) },
                                uniquingKeysWith: { first, _ in first })
    }
    func song(title: String, artist: String) -> Song? { songs[Key(title: title, artist: artist)] }

    static func matches(title: String, artist: String, otherTitle: String, otherArtist: String) -> Bool {
        Key(title: title, artist: artist) == Key(title: otherTitle, artist: otherArtist)
    }
}
