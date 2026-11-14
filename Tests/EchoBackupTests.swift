import Foundation
import XCTest

final class EchoBackupTests: XCTestCase {
    private var root: URL!
    private var source: EchoBackup.Locations!
    private var target: EchoBackup.Locations!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("EchoBackupTests-" + UUID().uuidString, isDirectory: true)
        source = locations("source")
        target = locations("target")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func locations(_ name: String) -> EchoBackup.Locations {
        let base = root.appendingPathComponent(name, isDirectory: true)
        return .init(documents: base.appendingPathComponent("Documents", isDirectory: true),
                     support: base.appendingPathComponent("Support", isDirectory: true),
                     staging: base.appendingPathComponent("Staging", isDirectory: true))
    }

    private func write(_ text: String, _ base: URL, _ path: String) throws {
        let url = base.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ base: URL, _ path: String) -> String? {
        (try? Data(contentsOf: base.appendingPathComponent(path))).map { String(decoding: $0, as: UTF8.self) }
    }

    private func exists(_ base: URL, _ path: String) -> Bool {
        FileManager.default.fileExists(atPath: base.appendingPathComponent(path).path)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var url = url; try url.setResourceValues(values)
    }

    private func populateSource() throws {
        try write("song", source.documents, "Song.mp3")
        try write("library", source.documents, "EchoSongs.json")
        try write("cover", source.documents, "EchoSongs-Artwork/A-cover")
        try write("podcasts", source.support, "Podcasts/state.json")
        try write("model", source.support, "Intelligence/model.bin")
        try excludeFromBackup(source.support.appendingPathComponent("Intelligence"))
        try write("temporary", source.support, "EchoBackgroundSources/part")
    }

    private func suite() -> (UserDefaults, String) {
        let name = "EchoBackupTests-" + UUID().uuidString
        return (UserDefaults(suiteName: name)!, name)
    }

    func testFullBackupRestoresEverythingAndReplacesCurrentData() throws {
        try populateSource()
        let archive = root.appendingPathComponent("backup.echobackup")
        var reported: [Double] = []
        let manifest = try EchoBackup.export(to: archive, locations: source, defaults: ["selectedLanguage": "nl", "count": 3],
                                             includeMusic: true, songCount: 1, appVersion: "1.0") { reported.append($0) }
        XCTAssertEqual(manifest.fileCount, 4, "excluded and temporary folders are left out")
        XCTAssertEqual(reported.last, 1)
        XCTAssertEqual(try EchoBackup.manifest(of: archive), manifest)

        // Current data on the restoring device.
        try write("old library", target.documents, "EchoSongs.json")
        try write("other song", target.documents, "Other.m4a")
        try write("kept model", target.support, "Intelligence/model.bin")
        try excludeFromBackup(target.support.appendingPathComponent("Intelligence"))

        XCTAssertEqual(try EchoBackup.stageRestore(from: archive, locations: target), manifest)
        XCTAssertEqual(EchoBackup.pendingRestore(locations: target), manifest)
        // Nothing changes before the next launch.
        XCTAssertEqual(read(target.documents, "EchoSongs.json"), "old library")

        let (defaults, domain) = suite()
        defer { defaults.removePersistentDomain(forName: domain) }
        XCTAssertNotNil(EchoBackup.applyPendingRestore(locations: target, defaults: defaults, domain: domain))
        XCTAssertEqual(read(target.documents, "EchoSongs.json"), "library")
        XCTAssertEqual(read(target.documents, "Song.mp3"), "song")
        XCTAssertEqual(read(target.documents, "EchoSongs-Artwork/A-cover"), "cover")
        XCTAssertEqual(read(target.support, "Podcasts/state.json"), "podcasts")
        XCTAssertFalse(exists(target.documents, "Other.m4a"), "a full restore replaces the music")
        XCTAssertEqual(read(target.support, "Intelligence/model.bin"), "kept model", "excluded data is kept")
        XCTAssertFalse(exists(target.support, "EchoBackgroundSources/part"))
        XCTAssertEqual(defaults.string(forKey: "selectedLanguage"), "nl")
        XCTAssertEqual(defaults.integer(forKey: "count"), 3)
        XCTAssertNil(EchoBackup.pendingRestore(locations: target))
        XCTAssertFalse(exists(target.staging, ""))
    }

    func testBackupWithoutMusicKeepsMusicOnTheDevice() throws {
        try populateSource()
        let archive = root.appendingPathComponent("small.echobackup")
        let manifest = try EchoBackup.export(to: archive, locations: source, defaults: nil,
                                             includeMusic: false, songCount: 1, appVersion: "1.0")
        XCTAssertFalse(manifest.includesMusic)
        XCTAssertEqual(manifest.fileCount, 3)

        try write("device song", target.documents, "Song.mp3")
        try write("old library", target.documents, "EchoSongs.json")
        try write("stale cover", target.documents, "EchoSongs-Artwork/B-cover")
        try EchoBackup.stageRestore(from: archive, locations: target)
        let (defaults, domain) = suite()
        EchoBackup.applyPendingRestore(locations: target, defaults: defaults, domain: domain)
        XCTAssertEqual(read(target.documents, "Song.mp3"), "device song")
        XCTAssertEqual(read(target.documents, "EchoSongs.json"), "library")
        XCTAssertEqual(read(target.documents, "EchoSongs-Artwork/A-cover"), "cover")
        XCTAssertFalse(exists(target.documents, "EchoSongs-Artwork/B-cover"))
    }

    func testDamagedOrForeignFilesChangeNothing() throws {
        try populateSource()
        let archive = root.appendingPathComponent("backup.echobackup")
        try EchoBackup.export(to: archive, locations: source, defaults: nil, includeMusic: true, songCount: 1, appVersion: "1.0")
        let data = try Data(contentsOf: archive)
        let truncated = root.appendingPathComponent("truncated.echobackup")
        try data.prefix(data.count - 5).write(to: truncated)
        XCTAssertThrowsError(try EchoBackup.stageRestore(from: truncated, locations: target))
        XCTAssertNil(EchoBackup.pendingRestore(locations: target))
        XCTAssertFalse(exists(target.staging, ""))

        let foreign = root.appendingPathComponent("photo.jpg")
        try Data(repeating: 1, count: 64).write(to: foreign)
        XCTAssertThrowsError(try EchoBackup.manifest(of: foreign)) {
            guard case EchoBackup.BackupError.notABackup = $0 else { return XCTFail("\($0)") }
        }
    }

    func testPathsCannotEscapeTheStagingFolder() throws {
        let manifest = EchoBackup.Manifest(created: Date(), appVersion: "1", songCount: 0, includesMusic: true, fileCount: 1, byteCount: 1)
        var archive = Data("ECHOBAK1".utf8)
        func entry(_ kind: UInt8, _ path: String, _ body: Data) {
            archive.append(kind)
            withUnsafeBytes(of: UInt32(path.utf8.count).littleEndian) { archive.append(contentsOf: $0) }
            archive.append(Data(path.utf8))
            withUnsafeBytes(of: UInt64(body.count).littleEndian) { archive.append(contentsOf: $0) }
            archive.append(body)
        }
        entry(3, "manifest", try JSONEncoder().encode(manifest))
        entry(1, "documents/../../escaped", Data("x".utf8))
        archive.append(0)
        let url = root.appendingPathComponent("evil.echobackup")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try archive.write(to: url)
        XCTAssertThrowsError(try EchoBackup.stageRestore(from: url, locations: target))
        XCTAssertFalse(exists(root, "target/escaped"))
        XCTAssertFalse(exists(root, "escaped"))
    }
}
