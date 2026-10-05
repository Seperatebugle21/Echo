import Foundation
import Observation
import XCTest

@MainActor
final class EchoDownloadInteractionTests: XCTestCase {
    private func item() -> FetchItem {
        FetchItem(spotifyURL: URL(string: "https://music.youtube.com/watch?v=test")!, title: "Song", artist: "Artist")
    }
    private final class Changes: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        func increment() { lock.lock(); value += 1; lock.unlock() }
    }
    func testProgressDoesNotInvalidateCatalogAvailability() {
        let download = item(), changes = Changes()
        withObservationTracking { _ = download.queueState } onChange: { changes.increment() }
        for step in 0..<100 {
            download.status = .downloading(Double(step) / 100)
        }
        download.status = .processing(0.99)
        XCTAssertEqual(changes.count, 0)
        download.status = .completed
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(download.queueState, .completed)
        download.status = .failed("Temporary failure")
        XCTAssertEqual(download.queueState, .failed)
        download.status = .queued
        XCTAssertEqual(download.queueState, .pending)
    }
    func testOneAutomaticRetryAndRestoredBudget() {
        let download = item()
        XCTAssertTrue(download.consumeAutomaticRetry(after: URLError(.networkConnectionLost)))
        XCTAssertEqual(download.automaticRetryCount, 1)
        XCTAssertFalse(download.consumeAutomaticRetry(after: URLError(.timedOut)))
        let restored = FetchItem(spotifyURL: download.spotifyURL, title: download.title, artist: download.artist,
                                 automaticRetryCount: download.automaticRetryCount)
        XCTAssertFalse(restored.consumeAutomaticRetry())
    }
    func testBackgroundRetryRecordReadsLegacyDataAndPersistsBudget() throws {
        let id = UUID()
        let legacy: [String: Any] = ["id": id.uuidString, "spotifyURL": "https://music.youtube.com/watch?v=test",
            "title": "Song", "artist": "Artist", "permissionConfirmed": true, "completed": false]
        var record = try JSONDecoder().decode(BackgroundFetchRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(record.automaticRetryCount)
        var budget = FetchRetryBudget(used: record.automaticRetryCount ?? 0)
        XCTAssertTrue(budget.consume())
        record.automaticRetryCount = budget.used
        let restored = try JSONDecoder().decode(BackgroundFetchRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored.id, id)
        var restoredBudget = FetchRetryBudget(used: restored.automaticRetryCount ?? 0)
        XCTAssertFalse(restoredBudget.consume())
    }
    func testCancellationDoesNotSpendOrTriggerRetry() {
        let download = item()
        XCTAssertFalse(download.consumeAutomaticRetry(after: CancellationError()))
        XCTAssertFalse(download.consumeAutomaticRetry(after: URLError(.cancelled)))
        XCTAssertEqual(download.automaticRetryCount, 0)
        XCTAssertTrue(download.consumeAutomaticRetry(after: URLError(.cannotConnectToHost)))
    }
    func testProgressGateLimitsUpdatesButAlwaysPublishesCompletion() {
        var gate = FetchProgressGate()
        XCTAssertTrue(gate.publish(0, at: 0))
        XCTAssertFalse(gate.publish(0.1, at: 0.05))
        XCTAssertFalse(gate.publish(0.2, at: 0.10))
        XCTAssertTrue(gate.publish(0.5, at: 0.25))
        XCTAssertFalse(gate.publish(0.5, at: 0.5))
        XCTAssertTrue(gate.publish(1, at: 0.26))
        XCTAssertFalse(gate.publish(1, at: 0.27))
    }
    func testTransferWorkLeavesMainActorResponsive() async throws {
        let started = expectation(description: "Background worker started")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let task = Task {
            try await FetchTransferWork.run {
                let wasMain = Thread.isMainThread
                started.fulfill()
                let released = release.wait(timeout: .now() + 5) == .success
                return (wasMain, released)
            }
        }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(Thread.isMainThread)
        release.signal()
        let result = try await task.value
        XCTAssertFalse(result.0)
        XCTAssertTrue(result.1)
    }
    func testCancellationPropagatesToDetachedTransferWork() async {
        let started = expectation(description: "Transfer ready")
        let task = Task {
            try await FetchTransferWork.run { () async throws -> Void in
                started.fulfill()
                while true { try await Task.sleep(for: .milliseconds(50)) }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Canceled worker completed") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testChunkMergeKeepsOrderAndRejectsIncompleteFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first"), second = directory.appendingPathComponent("second")
        let destination = directory.appendingPathComponent("audio")
        let a = Data(repeating: 12, count: 600_000), b = Data(repeating: 45, count: 700_000)
        try a.write(to: first); try b.write(to: second)
        try await FetchTransferWork.run {
            try FetchTransferWork.merge(parts: [first, second], destination: destination, expectedBytes: 1_300_000)
        }
        XCTAssertEqual(try Data(contentsOf: destination), a + b)
        do {
            try await FetchTransferWork.run {
                try FetchTransferWork.merge(parts: [first], destination: destination, expectedBytes: 1_300_000)
            }
            XCTFail("Truncated file accepted")
        } catch { XCTAssertTrue(error is FetchTransferError) }
    }
    func testAlbumSearchAndShufflePreserveSelectedMembership() {
        let a = Song(title: "First", artist: "Singer", fileName: "a", album: "Album")
        let b = Song(title: "Second", artist: "Guest", fileName: "b", album: "Album")
        XCTAssertEqual(AlbumSongSelection.filtered([a, b], query: "guest"), [b])
        XCTAssertEqual(AlbumSongSelection.filtered([a, b], query: "FIRST"), [a])
        XCTAssertEqual(AlbumSongSelection.filtered([a, b], query: "album"), [a, b])
        XCTAssertTrue(AlbumSongSelection.filtered([a, b], query: "missing").isEmpty)
        XCTAssertEqual(AlbumSongSelection.queue([a, b], shuffled: false), [a, b])
        XCTAssertEqual(Set(AlbumSongSelection.queue([a, b], shuffled: true).map(\.id)), Set([a.id, b.id]))
    }
    func testSongMatchingPreservesNormalizationAndRefreshesWithNewIndex() {
        let original = Song(title: "  A   Song ", artist: "Beyoncé", fileName: "first")
        var changed = original
        changed.title = "Renamed"
        let duplicate = Song(title: "A Song", artist: "Beyonce", fileName: "second")
        let index = LibrarySongMatchIndex([original, duplicate])
        XCTAssertEqual(index.song(title: "a song", artist: "BEYONCE")?.id, original.id)
        let refreshed = LibrarySongMatchIndex([changed])
        XCTAssertNil(refreshed.song(title: "a song", artist: "Beyonce"))
        XCTAssertEqual(refreshed.song(title: "renamed", artist: "Beyonce")?.id, changed.id)
        XCTAssertNil(LibrarySongMatchIndex([]).song(title: "a song", artist: "Beyonce"))
    }
}
