import Foundation

/// Coalesces snapshots and keeps JSON encoding and atomic file writes off the UI thread.
///
/// Artwork is not part of the JSON: `Song.coverData` and `Song.imageData` live in
/// `SongArtworkStore`, which loads them on demand. This class removes the artwork
/// of songs that leave the library. Libraries saved by older versions, with
/// artwork inside the JSON, are migrated while decoding.
final class SongLibraryPersistence: @unchecked Sendable {
    private let url: URL
    private let artwork: SongArtworkStore
    private let queue = DispatchQueue(label: "com.echomusic.library-storage", qos: .utility)
    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var completions: [() -> Void] = []
    /// Song IDs in the last loaded or saved library. Only accessed on `queue`.
    private var savedIDs: Set<UUID>?

    init(url: URL, artwork: SongArtworkStore = .shared) {
        self.url = url
        self.artwork = artwork
    }

    /// Reads the saved library. Returns `nil` when nothing has been saved yet.
    func load() throws -> [Song]? {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let songs = try JSONDecoder().decode([Song].self, from: Data(contentsOf: url))
            let ids = Set(songs.map(\.id))
            savedIDs = ids
            // Artwork left behind by songs that are gone (or by temporary songs, such as podcast episodes).
            artwork.removeArtwork(notIn: ids)
            return songs
        }
    }

    func submit(_ songs: [Song], immediately: Bool = false, completion: (() -> Void)? = nil) {
        lock.lock()
        revision &+= 1
        let token = revision
        if let completion { completions.append(completion) }
        lock.unlock()
        queue.asyncAfter(deadline: .now() + (immediately ? 0 : 0.4)) { [self] in
            guard isCurrent(token) else { return }
            do {
                let data = try JSONEncoder().encode(songs)
                guard isCurrent(token) else { return }
                try data.write(to: url, options: .atomic)
                let ids = Set(songs.map(\.id))
                if let savedIDs { artwork.removeArtwork(for: savedIDs.subtracting(ids)) }
                savedIDs = ids
                // Make sure artwork is on disk too before reporting the save as done.
                artwork.waitForWrites()
            } catch {
                print("Songs opslaan mislukt:", error.localizedDescription)
            }
            complete(token)
        }
    }

    private func isCurrent(_ token: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return revision == token
    }

    private func complete(_ token: UInt64) {
        lock.lock()
        let callbacks = revision == token ? completions : []
        if revision == token { completions.removeAll() }
        lock.unlock()
        callbacks.forEach { $0() }
    }
}
