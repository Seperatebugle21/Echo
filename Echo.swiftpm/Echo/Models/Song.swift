import Foundation

/// An additional library album, independent of a recording's original tags.
struct LibraryAlbumDestination: Codable, Hashable, Sendable {
    let name: String
    let artist: String

    var identity: String { Self.normalize(artist) + "\u{1F}" + Self.normalize(name) }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).lowercased()
    }

    static func unique(_ albums: [Self]) -> [Self] {
        var seen: Set<String> = []
        return albums.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.identity).inserted }
    }
}

struct Song: Identifiable, Codable, Hashable {
    
    let id: UUID
    var title: String
    var artist: String
    var artistNames: [String]?
    var fileName: String
    
    var album: String?
    var additionalAlbums: [LibraryAlbumDestination]?
    var genre: String?
    var releaseYear: Int?
    var tagsInspected: Bool?
    var coverData: Data?
    var imageData: Data?
    
    var dateAdded: Date
    var lastPlayed: Date?
    
    var lyrics: String?
    var syncedLyrics: String?
    var lyricsSource: String?
    var lyricsSourceURL: URL?
    // Playback metadata only; podcasts are stored in their own library.
    var podcastEpisodeID: String?
    
    
    init(
        id: UUID = UUID(),
        title: String,
        artist: String = "Onbekende artiest",
        fileName: String,
        album: String? = nil,
        coverData: Data? = nil,
        imageData: Data? = nil,
        dateAdded: Date = Date(),
        lastPlayed: Date? = nil,
        lyrics: String? = nil,
        syncedLyrics: String? = nil,
        artistNames: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artistNames = artistNames
        self.fileName = fileName
        self.album = album
        self.coverData = coverData
        self.imageData = imageData
        self.dateAdded = dateAdded
        self.lastPlayed = lastPlayed
        self.lyrics = lyrics
        self.syncedLyrics = syncedLyrics
    }
}
