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

struct Song: Identifiable, Codable, Hashable, Sendable {
    
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
    /// Changes whenever artwork is assigned, so equality and SwiftUI notice new covers.
    private(set) var artworkRevision: Int = 0
    
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
        self.dateAdded = dateAdded
        self.lastPlayed = lastPlayed
        self.lyrics = lyrics
        self.syncedLyrics = syncedLyrics
        if let coverData { self.coverData = coverData }
        if let imageData { self.imageData = imageData }
    }
}

// MARK: - Artwork

extension Song {
    /// Album cover. Stored on disk by `SongArtworkStore` and read on demand,
    /// so loading the library does not keep every cover in memory.
    var coverData: Data? {
        get { SongArtworkStore.shared.data(for: id, kind: .cover) }
        set { if SongArtworkStore.shared.set(newValue, for: id, kind: .cover) { artworkRevision &+= 1 } }
    }

    /// Custom image for the song, stored like `coverData`.
    var imageData: Data? {
        get { SongArtworkStore.shared.data(for: id, kind: .image) }
        set { if SongArtworkStore.shared.set(newValue, for: id, kind: .image) { artworkRevision &+= 1 } }
    }
}

// MARK: - Coding

extension Song {
    private enum CodingKeys: String, CodingKey {
        case id, title, artist, artistNames, fileName, album, additionalAlbums, genre, releaseYear,
             tagsInspected, artworkRevision, dateAdded, lastPlayed, lyrics, syncedLyrics,
             lyricsSource, lyricsSourceURL, podcastEpisodeID
        // Older libraries kept artwork inside the JSON. Read once and moved to the store.
        case coverData, imageData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decode(String.self, forKey: .artist)
        artistNames = try c.decodeIfPresent([String].self, forKey: .artistNames)
        fileName = try c.decode(String.self, forKey: .fileName)
        album = try c.decodeIfPresent(String.self, forKey: .album)
        additionalAlbums = try c.decodeIfPresent([LibraryAlbumDestination].self, forKey: .additionalAlbums)
        genre = try c.decodeIfPresent(String.self, forKey: .genre)
        releaseYear = try c.decodeIfPresent(Int.self, forKey: .releaseYear)
        tagsInspected = try c.decodeIfPresent(Bool.self, forKey: .tagsInspected)
        artworkRevision = try c.decodeIfPresent(Int.self, forKey: .artworkRevision) ?? 0
        dateAdded = try c.decode(Date.self, forKey: .dateAdded)
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)
        lyrics = try c.decodeIfPresent(String.self, forKey: .lyrics)
        syncedLyrics = try c.decodeIfPresent(String.self, forKey: .syncedLyrics)
        lyricsSource = try c.decodeIfPresent(String.self, forKey: .lyricsSource)
        lyricsSourceURL = try c.decodeIfPresent(URL.self, forKey: .lyricsSourceURL)
        podcastEpisodeID = try c.decodeIfPresent(String.self, forKey: .podcastEpisodeID)
        // Legacy embedded artwork: move it to the store. Keep the decoded revision,
        // so a migrated song still equals the one that was saved.
        let revision = artworkRevision
        if let legacy = try c.decodeIfPresent(Data.self, forKey: .coverData) { coverData = legacy }
        if let legacy = try c.decodeIfPresent(Data.self, forKey: .imageData) { imageData = legacy }
        artworkRevision = revision
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(artist, forKey: .artist)
        try c.encodeIfPresent(artistNames, forKey: .artistNames)
        try c.encode(fileName, forKey: .fileName)
        try c.encodeIfPresent(album, forKey: .album)
        try c.encodeIfPresent(additionalAlbums, forKey: .additionalAlbums)
        try c.encodeIfPresent(genre, forKey: .genre)
        try c.encodeIfPresent(releaseYear, forKey: .releaseYear)
        try c.encodeIfPresent(tagsInspected, forKey: .tagsInspected)
        if artworkRevision != 0 { try c.encode(artworkRevision, forKey: .artworkRevision) }
        try c.encode(dateAdded, forKey: .dateAdded)
        try c.encodeIfPresent(lastPlayed, forKey: .lastPlayed)
        try c.encodeIfPresent(lyrics, forKey: .lyrics)
        try c.encodeIfPresent(syncedLyrics, forKey: .syncedLyrics)
        try c.encodeIfPresent(lyricsSource, forKey: .lyricsSource)
        try c.encodeIfPresent(lyricsSourceURL, forKey: .lyricsSourceURL)
        try c.encodeIfPresent(podcastEpisodeID, forKey: .podcastEpisodeID)
    }
}

// MARK: - Artwork store

/// Song artwork on disk (`Documents/EchoSongs-Artwork/<song id>-cover|-image`),
/// with a bounded in-memory cache. Thread-safe. Writes happen in the background;
/// until a write finishes, reads return the new value from memory.
final class SongArtworkStore: @unchecked Sendable {
    enum Kind: CaseIterable {
        case cover, image

        func fileName(for id: UUID) -> String {
            id.uuidString + (self == .cover ? "-cover" : "-image")
        }
    }

    static let shared = SongArtworkStore(directory: FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("EchoSongs-Artwork", isDirectory: true))

    private let lock = NSLock()
    private var directory: URL
    /// Names of artwork that exists (on disk or pending). Listed once, then kept current.
    private var index: Set<String>?
    /// Changes not yet on disk; `nil` value means "being deleted".
    private var pending: [String: Data?] = [:]
    private var generations: [String: UInt64] = [:]
    private let cache = NSCache<NSString, NSData>()
    private let io = DispatchQueue(label: "com.echomusic.artwork-store", qos: .utility)

    init(directory: URL) {
        self.directory = directory
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    var artworkDirectory: URL {
        lock.lock(); defer { lock.unlock() }
        return directory
    }

    /// Points the store at another folder (tests). Pending writes finish first.
    func useDirectory(_ url: URL) {
        waitForWrites()
        lock.lock()
        directory = url
        index = nil
        pending = [:]
        cache.removeAllObjects()
        lock.unlock()
    }

    func data(for id: UUID, kind: Kind) -> Data? {
        let name = kind.fileName(for: id)
        lock.lock()
        if let change = pending[name] { lock.unlock(); return change }
        if let cached = cache.object(forKey: name as NSString) { lock.unlock(); return cached as Data }
        let exists = indexLocked().contains(name)
        let url = directory.appendingPathComponent(name)
        lock.unlock()
        guard exists, let data = try? Data(contentsOf: url) else { return nil }
        lock.lock()
        // Skip caching if the artwork changed while reading.
        if pending[name] == nil { cache.setObject(data as NSData, forKey: name as NSString, cost: data.count) }
        lock.unlock()
        return data
    }

    /// Stores (or with `nil`, removes) artwork. Returns false when nothing changed.
    @discardableResult
    func set(_ data: Data?, for id: UUID, kind: Kind) -> Bool {
        let value = data?.isEmpty == true ? nil : data
        guard self.data(for: id, kind: kind) != value else { return false }
        let name = kind.fileName(for: id)
        lock.lock()
        pending[name] = .some(value)
        let generation = (generations[name] ?? 0) &+ 1
        generations[name] = generation
        _ = indexLocked()
        if let value {
            index?.insert(name)
            cache.setObject(value as NSData, forKey: name as NSString, cost: value.count)
        } else {
            index?.remove(name)
            cache.removeObject(forKey: name as NSString)
        }
        let folder = directory
        lock.unlock()

        io.async { [self] in
            let url = folder.appendingPathComponent(name)
            if let value {
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try value.write(to: url, options: .atomic)
                } catch {
                    print("Artwork opslaan mislukt:", error.localizedDescription)
                    return // Keep it pending, so it is not lost while the app runs.
                }
            } else {
                try? FileManager.default.removeItem(at: url)
            }
            lock.lock()
            if generations[name] == generation { pending[name] = nil }
            lock.unlock()
        }
        return true
    }

    /// Removes artwork of songs that left the library.
    func removeArtwork(for ids: some Sequence<UUID>) {
        for id in ids {
            for kind in Kind.allCases { set(nil, for: id, kind: kind) }
        }
    }

    /// Removes artwork files whose song is not in `ids` (e.g. after a crash mid-delete).
    func removeArtwork(notIn ids: Set<UUID>) {
        lock.lock()
        let names = indexLocked().filter { pending[$0] == nil }
        lock.unlock()
        let keep = Set(ids.flatMap { id in Kind.allCases.map { $0.fileName(for: id) } })
        for name in names where !keep.contains(name) {
            guard let id = UUID(uuidString: String(name.prefix(36))),
                  let kind = Kind.allCases.first(where: { $0.fileName(for: id) == name })
            else { continue }
            set(nil, for: id, kind: kind)
        }
    }

    /// Blocks until all queued artwork writes are on disk.
    func waitForWrites() {
        io.sync {}
    }

    private func indexLocked() -> Set<String> {
        if let index { return index }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let listed = Set(names.filter { !$0.hasPrefix(".") })
        index = listed
        return listed
    }
}
