import Foundation

/// Coalesces snapshots and keeps JSON encoding and atomic file writes off the UI thread.
///
/// Artwork (`coverData` and `imageData`) is stored as separate files in a folder
/// next to the library JSON instead of inside it. A save only writes artwork that
/// changed, so editing one song no longer re-encodes and rewrites every cover in
/// the library. Libraries saved by older versions, with artwork inside the JSON,
/// still load and are migrated on their first save.
final class SongLibraryPersistence: @unchecked Sendable {
    private let url: URL
    let artworkDirectory: URL
    private let queue = DispatchQueue(label: "com.echomusic.library-storage", qos: .utility)
    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var completions: [() -> Void] = []

    // Only accessed on `queue`.
    /// Artwork files believed to exist in `artworkDirectory`.
    private var artworkFiles: Set<String> = []
    /// Contents of artwork files written or read by this instance, used to skip unchanged writes.
    private var artworkCache: [String: Data] = [:]

    init(url: URL) {
        self.url = url
        let name = url.deletingPathExtension().lastPathComponent
        artworkDirectory = url.deletingLastPathComponent()
            .appendingPathComponent(name + "-Artwork", isDirectory: true)
    }

    /// Reads the saved library and attaches artwork from disk.
    /// Returns `nil` when nothing has been saved yet.
    func load() throws -> [Song]? {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            var songs = try JSONDecoder().decode([Song].self, from: Data(contentsOf: url))
            let onDisk = Set((try? FileManager.default.contentsOfDirectory(atPath: artworkDirectory.path)) ?? [])
            artworkFiles = onDisk
            artworkCache = [:]
            for index in songs.indices {
                for kind in ArtworkKind.allCases {
                    // Artwork still embedded in the JSON (older format, or a file
                    // that could not be written) wins; the next save moves it out.
                    guard songs[index][kind] == nil else { continue }
                    let name = kind.fileName(for: songs[index].id)
                    guard onDisk.contains(name),
                          let data = try? Data(contentsOf: artworkDirectory.appendingPathComponent(name))
                    else { continue }
                    songs[index][kind] = data
                    artworkCache[name] = data
                }
            }
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
                let (stored, referenced) = storeArtwork(of: songs)
                let data = try JSONEncoder().encode(stored)
                guard isCurrent(token) else { return }
                try data.write(to: url, options: .atomic)
                // Only after the JSON no longer needs them.
                removeArtwork(except: referenced)
            } catch {
                print("Songs opslaan mislukt:", error.localizedDescription)
            }
            complete(token)
        }
    }

    // MARK: - Artwork files

    /// Writes changed artwork to disk and returns the songs without artwork that was
    /// stored as a file, plus the names of all artwork files the snapshot uses.
    private func storeArtwork(of songs: [Song]) -> ([Song], Set<String>) {
        var stored = songs
        var referenced: Set<String> = []
        var directoryReady = false
        for index in stored.indices {
            for kind in ArtworkKind.allCases {
                guard let data = stored[index][kind], !data.isEmpty else { continue }
                let name = kind.fileName(for: stored[index].id)
                if artworkCache[name] != data || !artworkFiles.contains(name) {
                    do {
                        if !directoryReady {
                            try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
                            directoryReady = true
                        }
                        try data.write(to: artworkDirectory.appendingPathComponent(name), options: .atomic)
                        artworkFiles.insert(name)
                        artworkCache[name] = data
                    } catch {
                        // Keep this artwork inside the JSON rather than losing it.
                        print("Artwork opslaan mislukt:", error.localizedDescription)
                        continue
                    }
                }
                referenced.insert(name)
                stored[index][kind] = nil
            }
        }
        return (stored, referenced)
    }

    private func removeArtwork(except referenced: Set<String>) {
        for name in artworkFiles.subtracting(referenced) {
            try? FileManager.default.removeItem(at: artworkDirectory.appendingPathComponent(name))
            artworkFiles.remove(name)
            artworkCache[name] = nil
        }
    }

    // MARK: - Snapshot bookkeeping

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

private enum ArtworkKind: CaseIterable {
    case cover, image

    func fileName(for id: UUID) -> String {
        switch self {
        case .cover: return id.uuidString + "-cover"
        case .image: return id.uuidString + "-image"
        }
    }
}

private extension Song {
    subscript(_ kind: ArtworkKind) -> Data? {
        get {
            switch kind {
            case .cover: return coverData
            case .image: return imageData
            }
        }
        set {
            switch kind {
            case .cover: coverData = newValue
            case .image: imageData = newValue
            }
        }
    }
}
