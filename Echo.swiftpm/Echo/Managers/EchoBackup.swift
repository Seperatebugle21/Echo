import Foundation

/// Backup and restore of everything Echo keeps on the device: the library,
/// artwork, playlists, favorites, listening history, podcasts, settings and,
/// optionally, the music files themselves.
///
/// A backup is one `.echobackup` file: a short header with a manifest, then each
/// file as a length-prefixed entry. It is written and read as a stream, so large
/// libraries never have to fit in memory.
///
/// Restoring happens in two steps so a running app cannot overwrite restored data:
/// the archive is unpacked and verified into a staging folder, and the next launch
/// moves it into place before any library code runs.
enum EchoBackup {
    static let fileExtension = "echobackup"

    struct Manifest: Codable, Equatable, Sendable {
        var format = 1
        var created: Date
        var appVersion: String
        var songCount: Int
        var includesMusic: Bool
        var fileCount: Int
        var byteCount: Int64
    }

    /// Where data lives. Production uses the app's own folders; tests use temporary ones.
    struct Locations: Sendable {
        var documents: URL
        var support: URL
        /// Holds a verified, unpacked backup until the next launch.
        var staging: URL

        static var app: Locations {
            let manager = FileManager.default
            let library = manager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            return Locations(documents: manager.urls(for: .documentDirectory, in: .userDomainMask)[0],
                             support: manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                             staging: library.appendingPathComponent("EchoPendingRestore", isDirectory: true))
        }

        fileprivate var roots: [(prefix: String, url: URL)] { [("documents", documents), ("support", support)] }
    }

    enum BackupError: LocalizedError {
        case notABackup, unsupportedVersion, damaged, unsafePath

        var errorDescription: String? {
            switch self {
            case .notABackup: return String(localized: "backup_error_not_backup")
            case .unsupportedVersion: return String(localized: "backup_error_version")
            case .damaged, .unsafePath: return String(localized: "backup_error_damaged")
            }
        }
    }

    static let musicExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "alac", "ogg", "opus", "mp4", "m4b", "webm"]
    /// Temporary or re-downloadable data that a backup leaves out.
    static let skippedFolders: Set<String> = ["EchoBackgroundSources", "Inbox", ".Trash"]

    private static let magic = Data("ECHOBAK1".utf8)
    private enum Kind: UInt8 { case end = 0, file = 1, defaults = 2, manifest = 3 }
    private static let chunk = 1 << 20

    // MARK: Export

    /// Writes a backup to `archive`. `progress` receives 0...1 from the calling thread.
    @discardableResult
    static func export(to archive: URL, locations: Locations = .app, defaults: [String: Any]?,
                       includeMusic: Bool, songCount: Int, appVersion: String,
                       progress: (Double) -> Void = { _ in }) throws -> Manifest {
        var files: [(path: String, url: URL, size: Int64)] = []
        for root in locations.roots {
            for (relative, url, size) in try collect(root.url, includeMusic: includeMusic) {
                files.append((root.prefix + "/" + relative, url, size))
            }
        }
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        let manifest = Manifest(created: Date(), appVersion: appVersion, songCount: songCount,
                                includesMusic: includeMusic, fileCount: files.count, byteCount: total)

        try? FileManager.default.removeItem(at: archive)
        guard FileManager.default.createFile(atPath: archive.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let out = try FileHandle(forWritingTo: archive)
        defer { try? out.close() }
        do {
            try out.write(contentsOf: magic)
            try writeEntry(out, .manifest, path: "manifest", data: JSONEncoder().encode(manifest))
            if let defaults {
                let data = try PropertyListSerialization.data(fromPropertyList: defaults, format: .binary, options: 0)
                try writeEntry(out, .defaults, path: "defaults", data: data)
            }
            var written: Int64 = 0
            for file in files {
                try autoreleasepool {
                    let input = try FileHandle(forReadingFrom: file.url)
                    defer { try? input.close() }
                    try writeHeader(out, .file, path: file.path, size: UInt64(file.size))
                    var remaining = file.size
                    while remaining > 0 {
                        let data = try input.read(upToCount: Int(min(Int64(chunk), remaining))) ?? Data()
                        guard !data.isEmpty else { throw BackupError.damaged } // file shrank while reading
                        try out.write(contentsOf: data)
                        remaining -= Int64(data.count)
                        written += Int64(data.count)
                        if total > 0 { progress(Double(written) / Double(total)) }
                    }
                }
            }
            try out.write(contentsOf: [Kind.end.rawValue])
            try out.synchronize()
        } catch {
            try? out.close()
            try? FileManager.default.removeItem(at: archive)
            throw error
        }
        progress(1)
        return manifest
    }

    private static func collect(_ root: URL, includeMusic: Bool) throws -> [(String, URL, Int64)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isExcludedFromBackupKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        var result: [(String, URL, Int64)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isExcludedFromBackup == true || skippedFolders.contains(url.lastPathComponent) {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            if !includeMusic, musicExtensions.contains(url.pathExtension.lowercased()) { continue }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard path.hasPrefix(base + "/") else { continue }
            result.append((String(path.dropFirst(base.count + 1)), url, Int64(values.fileSize ?? 0)))
        }
        return result.sorted { $0.0 < $1.0 }
    }

    // MARK: Inspect and stage

    /// Reads only the manifest at the start of a backup.
    static func manifest(of archive: URL) throws -> Manifest {
        let input = try FileHandle(forReadingFrom: archive)
        defer { try? input.close() }
        return try readManifest(input)
    }

    /// Unpacks and verifies `archive` into the staging folder. The next launch applies it.
    @discardableResult
    static func stageRestore(from archive: URL, locations: Locations = .app,
                             progress: (Double) -> Void = { _ in }) throws -> Manifest {
        let manager = FileManager.default
        let staging = locations.staging
        try? manager.removeItem(at: staging)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let input = try FileHandle(forReadingFrom: archive)
            defer { try? input.close() }
            let manifest = try readManifest(input)
            var read: Int64 = 0, files = 0
            entries: while true {
                guard let kindByte = try input.read(upToCount: 1)?.first else { throw BackupError.damaged }
                guard let kind = Kind(rawValue: kindByte) else { throw BackupError.damaged }
                if kind == .end { break entries }
                let (path, size) = try readHeader(input)
                let destination: URL
                switch kind {
                case .defaults: destination = staging.appendingPathComponent("defaults.plist")
                case .file: destination = try stagedURL(for: path, in: staging); files += 1
                default: throw BackupError.damaged
                }
                try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard manager.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
                let out = try FileHandle(forWritingTo: destination)
                defer { try? out.close() }
                var remaining = Int64(size)
                while remaining > 0 {
                    try autoreleasepool {
                        let data = try input.read(upToCount: Int(min(Int64(chunk), remaining))) ?? Data()
                        guard !data.isEmpty else { throw BackupError.damaged }
                        try out.write(contentsOf: data)
                        remaining -= Int64(data.count)
                        read += Int64(data.count)
                    }
                    if manifest.byteCount > 0 { progress(min(1, Double(read) / Double(manifest.byteCount))) }
                }
            }
            guard files == manifest.fileCount else { throw BackupError.damaged }
            // Written last: its presence means the staging folder is complete.
            try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            progress(1)
            return manifest
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    /// The backup waiting for the next launch, if any.
    static func pendingRestore(locations: Locations = .app) -> Manifest? {
        guard let data = try? Data(contentsOf: locations.staging.appendingPathComponent("manifest.json")) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    static func cancelPendingRestore(locations: Locations = .app) {
        try? FileManager.default.removeItem(at: locations.staging)
    }

    // MARK: Apply at launch

    /// Moves a staged backup into place. Call before any code reads the library.
    /// Returns the applied manifest.
    @discardableResult
    static func applyPendingRestore(locations: Locations = .app,
                                    defaults: UserDefaults = .standard,
                                    domain: String? = Bundle.main.bundleIdentifier) -> Manifest? {
        guard let manifest = pendingRestore(locations: locations) else {
            // An incomplete staging folder (e.g. the app closed while unpacking).
            if FileManager.default.fileExists(atPath: locations.staging.path) { cancelPendingRestore(locations: locations) }
            return nil
        }
        let keepMusic = !manifest.includesMusic
        for root in locations.roots {
            clear(root.url, keepMusic: keepMusic)
            merge(from: locations.staging.appendingPathComponent(root.prefix, isDirectory: true), into: root.url)
        }
        let defaultsURL = locations.staging.appendingPathComponent("defaults.plist")
        if let domain, let data = try? Data(contentsOf: defaultsURL),
           let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            defaults.setPersistentDomain(values, forName: domain)
            defaults.synchronize()
        }
        cancelPendingRestore(locations: locations)
        return manifest
    }

    /// Removes what a restore replaces; keeps data excluded from backups
    /// (such as downloaded AI models) and, for backups without music, the music files.
    private static func clear(_ root: URL, keepMusic: Bool) {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isExcludedFromBackupKey]
        guard let items = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: keys) else { return }
        for item in items {
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isExcludedFromBackup == true || skippedFolders.contains(item.lastPathComponent) { continue }
            if values?.isDirectory == true {
                if keepMusic { clear(item, keepMusic: true) } else { try? manager.removeItem(at: item) }
            } else if !(keepMusic && musicExtensions.contains(item.pathExtension.lowercased())) {
                try? manager.removeItem(at: item)
            }
        }
    }

    private static func merge(from source: URL, into destination: URL) {
        let manager = FileManager.default
        guard let items = try? manager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        try? manager.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            var isDirectory: ObjCBool = false
            let exists = manager.fileExists(atPath: target.path, isDirectory: &isDirectory)
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if exists && !isDirectory.boolValue { try? manager.removeItem(at: target) }
                merge(from: item, into: target)
            } else {
                if exists { try? manager.removeItem(at: target) }
                try? manager.moveItem(at: item, to: target)
            }
        }
    }

    // MARK: Format

    private static func writeHeader(_ out: FileHandle, _ kind: Kind, path: String, size: UInt64) throws {
        let name = Data(path.utf8)
        var header = Data([kind.rawValue])
        withUnsafeBytes(of: UInt32(name.count).littleEndian) { header.append(contentsOf: $0) }
        header.append(name)
        withUnsafeBytes(of: size.littleEndian) { header.append(contentsOf: $0) }
        try out.write(contentsOf: header)
    }

    private static func writeEntry(_ out: FileHandle, _ kind: Kind, path: String, data: Data) throws {
        try writeHeader(out, kind, path: path, size: UInt64(data.count))
        try out.write(contentsOf: data)
    }

    private static func readHeader(_ input: FileHandle) throws -> (String, UInt64) {
        guard let lengthData = try input.read(upToCount: 4), lengthData.count == 4 else { throw BackupError.damaged }
        let length = lengthData.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard length > 0, length < 4096,
              let nameData = try input.read(upToCount: Int(length)), nameData.count == Int(length),
              let path = String(data: nameData, encoding: .utf8),
              let sizeData = try input.read(upToCount: 8), sizeData.count == 8
        else { throw BackupError.damaged }
        let size = sizeData.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
        return (path, size)
    }

    private static func readManifest(_ input: FileHandle) throws -> Manifest {
        guard try input.read(upToCount: magic.count) == magic else { throw BackupError.notABackup }
        guard try input.read(upToCount: 1)?.first == Kind.manifest.rawValue else { throw BackupError.damaged }
        let (_, size) = try readHeader(input)
        guard size < 1 << 20, let data = try input.read(upToCount: Int(size)), data.count == Int(size) else { throw BackupError.damaged }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.format == 1 else { throw BackupError.unsupportedVersion }
        return manifest
    }

    /// Maps an archive path to the staging folder, rejecting anything that could escape it.
    private static func stagedURL(for path: String, in staging: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2, ["documents", "support"].contains(parts[0]),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else { throw BackupError.unsafePath }
        return parts.reduce(staging) { $0.appendingPathComponent(String($1)) }
    }
}
