import Foundation
import XCTest

final class EchoWidgetModelTests: XCTestCase {
    func testExistingInstallationSnapshotStillDecodes() throws {
        // Actual V1 shape: new state/favorite fields did not exist.
        let json = """
        {"updatedAt":0,"songs":[{"id":"A0000000-0000-0000-0000-000000000001",
        "title":"Existing song","artist":"Artist","artworkData":"AQID"}]}
        """
        let snapshot = try JSONDecoder().decode(EchoWidgetSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.songs.first?.title, "Existing song")
        XCTAssertEqual(snapshot.songs.first?.artworkData, Data([1, 2, 3]))
        XCTAssertNil(snapshot.currentSong)
        XCTAssertNil(snapshot.isPlaying)
        XCTAssertNil(snapshot.songs.first?.isFavorite)
    }

    func testPlaybackStateAndCoversSurviveSharedSnapshotRoundTrip() throws {
        let song = EchoWidgetSongItem(id: UUID(), title: "Één & twee 🎵", artist: "Artist",
                                     artworkData: Data([0, 255, 128, 42]), isFavorite: true)
        let original = EchoWidgetSnapshot(updatedAt: Date(timeIntervalSinceReferenceDate: 42),
                                          songs: [song], currentSong: song, isPlaying: true)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(EchoWidgetSnapshot.self, from: data)
        XCTAssertEqual(restored, original)
    }

    func testArtworkIsOptionalAndEmptyLibraryRoundTrips() throws {
        let song = EchoWidgetSongItem(id: UUID(), title: "No cover", artist: "Artist", artworkData: nil)
        let original = EchoWidgetSnapshot(updatedAt: .distantPast, songs: [song], isPlaying: false)
        let restored = try JSONDecoder().decode(EchoWidgetSnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertNil(restored.songs.first?.artworkData)
        XCTAssertEqual(restored.isPlaying, false)
        let empty = try JSONDecoder().decode(EchoWidgetSnapshot.self, from: JSONEncoder().encode(EchoWidgetSnapshot.empty))
        XCTAssertTrue(empty.songs.isEmpty)
    }

    func testLegacyDeepLinkPreservesExactSongID() throws {
        let id = UUID()
        let song = EchoWidgetSongItem(id: id, title: "A&B?", artist: "Artist", artworkData: nil)
        let components = try XCTUnwrap(URLComponents(url: song.playbackURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "echo")
        XCTAssertEqual(components.host, "play")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "id", value: id.uuidString)])
    }
}
