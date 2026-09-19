import Foundation
import XCTest

final class EchoWidgetModelTests: XCTestCase {
    func testNightlyWithoutLegacyMetadataUsesEmbeddedProfile() throws {
        let mapped = EchoWidgetSnapshotStore.appGroupIdentifier + ".ABC1234567"
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "Entitlements": ["com.apple.security.application-groups": [mapped]]
        ], format: .xml, options: 0)
        // Non-UTF8 bytes model the surrounding CMS envelope.
        var profile = Data([0x30, 0x82, 0xFF, 0x00])
        profile.append(plist)
        profile.append(contentsOf: [0x00, 0xFF])
        let groups = EchoWidgetSnapshotStore.appGroups(inProvisioningProfile: profile)
        XCTAssertEqual(groups, [mapped])
        let result = EchoWidgetSnapshotStore.containerURL(
            installedGroups: [], provisionedGroups: groups
        ) { id in id == mapped ? URL(fileURLWithPath: "/shared/current") : nil }
        XCTAssertEqual(result?.lastPathComponent, "current")
    }

    func testCurrentProfileWinsOverStaleLegacyMetadata() {
        let base = EchoWidgetSnapshotStore.appGroupIdentifier
        let result = EchoWidgetSnapshotStore.containerURL(
            installedGroups: [base + ".OLDTEAM"], provisionedGroups: [base + ".NEWTEAM"]
        ) { URL(fileURLWithPath: "/shared/" + $0) }
        XCTAssertEqual(result?.lastPathComponent, base + ".NEWTEAM")
    }

    func testProfileDoesNotGrantAccessOrSelectUnrelatedGroups() {
        let base = EchoWidgetSnapshotStore.appGroupIdentifier
        var requested: [String] = []
        let result = EchoWidgetSnapshotStore.containerURL(
            installedGroups: [], provisionedGroups: ["group.other.app", base + ".TEAM"]
        ) { id in requested.append(id); return nil }
        XCTAssertNil(result)
        XCTAssertEqual(requested, [base + ".TEAM", base])
    }

    func testMalformedAndMissingProfileEntitlementsAreIgnored() throws {
        for data in [Data(), Data("<plist>truncated".utf8), Data("<plist>bad</plist>".utf8)] {
            XCTAssertTrue(EchoWidgetSnapshotStore.appGroups(inProvisioningProfile: data).isEmpty)
        }
        let data = try PropertyListSerialization.data(fromPropertyList: ["Name": "No groups"], format: .xml, options: 0)
        XCTAssertTrue(EchoWidgetSnapshotStore.appGroups(inProvisioningProfile: data).isEmpty)
    }

    func testSideStoreMappingPreferredOverOriginalGroup() {
        let base = EchoWidgetSnapshotStore.appGroupIdentifier
        let mapped = base + ".ABC1234567"
        var requested: [String] = []
        let result = EchoWidgetSnapshotStore.containerURL(installedGroups: [mapped]) { id in
            requested.append(id)
            return URL(fileURLWithPath: "/shared/" + id)
        }
        XCTAssertEqual(result?.lastPathComponent, mapped)
        XCTAssertEqual(requested, [mapped])
    }

    func testStandardInstallUsesOriginalGroup() {
        let expected = URL(fileURLWithPath: "/shared/echo")
        let result = EchoWidgetSnapshotStore.containerURL(installedGroups: []) { id in
            XCTAssertEqual(id, EchoWidgetSnapshotStore.appGroupIdentifier)
            return expected
        }
        XCTAssertEqual(result, expected)
    }

    func testUnrelatedGroupsAreNeverUsedAndDeniedMappingFallsBack() {
        let base = EchoWidgetSnapshotStore.appGroupIdentifier
        var requested: [String] = []
        let result = EchoWidgetSnapshotStore.containerURL(
            installedGroups: ["group.other.app", base + "evil", base + ".", base + ".ABC1234567"]
        ) { id in
            requested.append(id)
            return id == base ? URL(fileURLWithPath: "/shared/original") : nil
        }
        XCTAssertEqual(requested, [base + ".ABC1234567", base])
        XCTAssertEqual(result?.lastPathComponent, "original")
    }

    func testMissingEntitlementsReturnsUnavailable() {
        XCTAssertNil(EchoWidgetSnapshotStore.containerURL(
            installedGroups: ["group.com.echomusic.app.ABC1234567"]
        ) { _ in nil })
    }

    func testAppAndExtensionResolveSameGroupRegardlessOfListOrder() {
        let base = EchoWidgetSnapshotStore.appGroupIdentifier
        let groups = [base + ".ZYX1234567", base + ".ABC1234567", base + ".ABC1234567"]
        let app = EchoWidgetSnapshotStore.containerURL(installedGroups: groups) { URL(fileURLWithPath: "/shared/" + $0) }
        let widget = EchoWidgetSnapshotStore.containerURL(installedGroups: Array(groups.reversed())) { URL(fileURLWithPath: "/shared/" + $0) }
        XCTAssertEqual(app, widget)
    }

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
