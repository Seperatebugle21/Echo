import Foundation
import XCTest

final class EchoSmartPlaylistOverrideTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func song(_ title: String) -> Song {
        Song(title: title, artist: "Artist", fileName: title + ".wav", dateAdded: now)
    }
    func testRemovalIsIsolatedAndExpiresAfter120Hours() {
        let track = song("A")
        let definition = SmartPreset.mostPlayed.definition
        let global = SmartListeningSnapshot(total: [track.id: 20])
        var override = SmartSongOverride(manuallyIncluded: true)
        override.remove(at: now)
        let states = [track.id: override]
        XCTAssertEqual(SmartPlaylistEvaluator.songs(definition, from: [track], favorites: [], listening: global, now: now).count, 1)
        XCTAssertTrue(SmartPlaylistEvaluator.songs(definition, from: [track], favorites: [], listening: global, now: now, overrides: states).isEmpty)
        XCTAssertFalse(override.include(at: now.addingTimeInterval(120 * 3600 - 1)))
        XCTAssertTrue(override.isExcluded(at: now.addingTimeInterval(120 * 3600 - 1)))
        XCTAssertFalse(override.isExcluded(at: now.addingTimeInterval(120 * 3600)))
        // Expiry alone does not restore the old global playcount.
        XCTAssertTrue(SmartPlaylistEvaluator.songs(definition, from: [track], favorites: [], listening: global,
            now: now.addingTimeInterval(120 * 3600), overrides: states).isEmpty)
        override.recordPlay(at: now.addingTimeInterval(3600))
        XCTAssertEqual(SmartPlaylistEvaluator.songs(definition, from: [track], favorites: [], listening: global,
            now: now.addingTimeInterval(120 * 3600), overrides: [track.id: override]).count, 1)
        XCTAssertEqual(global.total[track.id], 20)
    }
    func testManualSongsBypassRulesAndAutomaticLimitWithoutDuplicates() {
        let a = song("A"), b = song("B"), manual = song("Manual")
        var definition = SmartPlaylistDefinition(rules: [SmartRule(value: 1)], sort: .title, limit: 1)
        let global = SmartListeningSnapshot(total: [a.id: 3, b.id: 2])
        var override = SmartSongOverride()
        XCTAssertTrue(override.include(at: now))
        let overrides = [manual.id: override, a.id: override]
        XCTAssertEqual(SmartPlaylistEvaluator.songs(definition, from: [a, b, manual, manual], favorites: [],
            listening: global, now: now, overrides: overrides).map(\.id), [a.id, b.id, manual.id])
        definition.limit = 0
        XCTAssertEqual(SmartPlaylistEvaluator.songs(definition, from: [a, b, manual], favorites: [],
            listening: global, now: now, overrides: overrides).map(\.id), [a.id, manual.id])
        override.remove(at: now)
        XCTAssertFalse(override.manuallyIncluded)
    }
    func testResetCountsUseOnlyNewStartsAndRespectDayWindows() throws {
        let track = song("A")
        var override = SmartSongOverride()
        override.remove(at: now)
        override.recordPlay(at: now)
        override.recordPlay(at: now.addingTimeInterval(24 * 3600))
        let later = now.addingTimeInterval(120 * 3600)
        override.recordPlay(at: later)
        let global = SmartListeningSnapshot(total: [track.id: 100], daily: [track.id: [SmartListeningSnapshot.dayKey(later): 50]])
        let today = SmartPlaylistDefinition(rules: [SmartRule(comparison: .equals, value: 1, periodDays: 1)], limit: nil)
        let all = SmartPlaylistDefinition(rules: [SmartRule(comparison: .equals, value: 3)], limit: nil)
        for definition in [today, all] {
            XCTAssertEqual(SmartPlaylistEvaluator.songs(definition, from: [track], favorites: [], listening: global,
                now: later, overrides: [track.id: override]).count, 1)
        }
        override.remove(at: later)
        XCTAssertEqual(override.totalSinceReset, 0)
        XCTAssertEqual(override.dailySinceReset, [:])
    }
    func testLegacyAndOverridePlaylistPersistence() throws {
        let track = song("A")
        let json = "{\"id\":\"\(UUID())\",\"name\":\"Legacy\",\"songIDs\":[]}"
        var playlist = try JSONDecoder().decode(Playlist.self, from: Data(json.utf8))
        XCTAssertNil(playlist.smartOverrides)
        var override = SmartSongOverride()
        override.remove(at: now)
        override.recordPlay(at: now)
        playlist.smartDefinition = SmartPreset.mostPlayed.definition
        playlist.smartOverrides = [track.id: override]
        let restored = try JSONDecoder().decode(Playlist.self, from: JSONEncoder().encode(playlist))
        XCTAssertEqual(restored.smartOverrides, playlist.smartOverrides)
        XCTAssertEqual(restored.smartDefinition, playlist.smartDefinition)
    }
}
