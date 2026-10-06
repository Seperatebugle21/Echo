import Foundation
import XCTest

final class EchoFeatureLogicTests: XCTestCase {
    func testCoverAndAutomaticNameStorageMigration() throws {
        let json = "{\"id\":\"\(UUID().uuidString)\",\"name\":\"Meest beluisterd\",\"songIDs\":[]}"
        let legacy = try JSONDecoder().decode(Playlist.self, from: Data(json.utf8))
        XCTAssertNil(legacy.builtinCoverID); XCTAssertNil(legacy.automaticNameKey)
        XCTAssertEqual(legacy.displayName(language: "de"), "Meest beluisterd")
        var custom = legacy; custom.name = "  My name 🎶  "; custom.builtinCoverID = "illustration-04"
        let decoded = try JSONDecoder().decode(Playlist.self, from: JSONEncoder().encode(custom))
        XCTAssertEqual(decoded.name, custom.name); XCTAssertEqual(decoded.builtinCoverID, "illustration-04")
        XCTAssertEqual(decoded.displayName(language: "fr"), custom.name)
    }
    func testAutomaticNamesUseSelectedBundleLanguage() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer { try? FileManager.default.removeItem(at: folder) }
        let translations = ["en": "Most played", "nl": "Meest beluisterd", "fr": "Les plus écoutés", "de": "Meistgespielt"]
        for (language, name) in translations {
            let path = folder.appendingPathComponent(language + ".lproj")
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try "\"smart_preset_mostPlayed\" = \"\(name)\";".write(to: path.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        }
        guard let bundle = Bundle(path: folder.path) else { preconditionFailure("Test bundle missing") }
        for (language, name) in translations {
            XCTAssertEqual(EchoLocalization.string("smart_preset_mostPlayed", language: language, bundle: bundle), name)
        }
    }
    func testSquareCropClampsPanAndPreservesCoverage() {
        for size in [CGSize(width: 800, height: 1200), CGSize(width: 1600, height: 900), CGSize(width: 1024, height: 1024)] {
            for zoom: CGFloat in [1, 2, 4] {
                let geometry = PlaylistCoverGeometry(imageSize: size, side: 300, zoom: zoom)
                for offset in [CGSize.zero, CGSize(width: -10000, height: 10000), CGSize(width: 10000, height: -10000)] {
                    let rect = geometry.drawingRect(offset: offset)
                    XCTAssertLessThanOrEqual(rect.minX, 0); XCTAssertLessThanOrEqual(rect.minY, 0)
                    XCTAssertGreaterThanOrEqual(rect.maxX, 300); XCTAssertGreaterThanOrEqual(rect.maxY, 300)
                }
            }
        }
    }
    private func song(_ title: String, year: Int? = nil, genre: String? = nil) -> Song {
        var value = Song(title: title, artist: "Artist", fileName: title + ".wav", dateAdded: Date(timeIntervalSince1970: 100))
        value.releaseYear = year; value.genre = genre; return value
    }
    private func evaluate(_ definition: SmartPlaylistDefinition, _ songs: [Song]) -> [Song] {
        SmartPlaylistEvaluator.songs(definition, from: songs, favorites: [], listening: SmartListeningSnapshot(), now: Date(timeIntervalSince1970: 1_000_000))
    }
    func testDecadeBoundariesAndMissingYear() {
        let tracks = [song("Before", year: 1979), song("Start", year: 1980), song("End", year: 1989), song("After", year: 1990), song("Unknown")]
        XCTAssertEqual(Set(evaluate(SmartPreset.eighties.definition, tracks).map(\.title)), ["Start", "End"])
    }
    func testMissingGenreOnlyMatchesMissingRule() {
        let tracks = [song("Rock", genre: "Rock"), song("None")]
        var definition = SmartPlaylistDefinition(rules: [SmartRule(field: .genre, comparison: .contains, text: "rock")])
        XCTAssertEqual(evaluate(definition, tracks).map(\.title), ["Rock"])
        definition.rules[0].comparison = .missing
        XCTAssertEqual(evaluate(definition, tracks).map(\.title), ["None"])
    }
    func testAnyAllLimitAndStableOrder() {
        let a = song("A", year: 1985, genre: "Rock"), b = song("B", year: 1995, genre: "Rock")
        var definition = SmartPreset.eighties.definition
        definition.rules.append(SmartRule(field: .genre, comparison: .equals, text: "Rock"))
        XCTAssertEqual(evaluate(definition, [b, a]).map(\.title), ["A"])
        definition.matchAll = false; definition.sort = .title; definition.limit = 1
        XCTAssertEqual(evaluate(definition, [b, a]).map(\.title), ["A"])
        definition.limit = nil; XCTAssertEqual(evaluate(definition, [b, a]).map(\.title), ["A", "B"])
    }
    func testLegacySongAndPlaylistDecode() throws {
        let old = song("Old"), restored = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(old))
        XCTAssertNil(restored.genre); XCTAssertNil(restored.releaseYear)
        let json = "{\"id\":\"\(UUID().uuidString)\",\"name\":\"Legacy\",\"songIDs\":[]}"
        XCTAssertNil(try JSONDecoder().decode(Playlist.self, from: Data(json.utf8)).smartDefinition)
        let smart = Playlist(id: UUID(), name: "80s", songIDs: [], smartDefinition: SmartPreset.eighties.definition)
        XCTAssertEqual(try JSONDecoder().decode(Playlist.self, from: JSONEncoder().encode(smart)).smartDefinition, smart.smartDefinition)
    }
    func testDailyWindowUsesCalendarDaysAndDoesNotInventHistory() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_759_406_400), id = UUID()
        let today = SmartListeningSnapshot.dayKey(now, calendar: calendar)
        let outside = SmartListeningSnapshot.dayKey(calendar.date(byAdding: .day, value: -7, to: now)!, calendar: calendar)
        let snapshot = SmartListeningSnapshot(total: [id: 99], daily: [id: [today: 3, outside: 7]])
        XCTAssertEqual(snapshot.count(id, days: nil, now: now, calendar: calendar), 99)
        XCTAssertEqual(snapshot.count(id, days: 7, now: now, calendar: calendar), 3)
        XCTAssertEqual(snapshot.count(id, days: 30, now: now, calendar: calendar), 10)
        XCTAssertEqual(SmartListeningSnapshot(total: [id: 99]).count(id, days: 30, now: now), 0)
    }
    func testCrossfadeBoundsAndEqualPowerHeadroom() {
        XCTAssertEqual(AudioTransitionPlan.make(mode: .crossfade, seconds: 12, outgoingDuration: 4, incomingDuration: 10).overlap, 2)
        for i in 0...100 {
            let a = AudioTransitionPlan.outgoingGain(Double(i) / 100), b = AudioTransitionPlan.incomingGain(Double(i) / 100)
            XCTAssertEqual(a * a + b * b, 0.5, accuracy: 0.00001); XCTAssertLessThanOrEqual(a + b, 1.00001)
        }
        XCTAssertEqual(AudioTransitionPlan.make(mode: .gapless, seconds: 5, outgoingDuration: 100, incomingDuration: 100).overlap, 0)
    }
    func testMetadataBatchPreservesEditsAndIgnoresRemovedSongs() {
        var edited = song("Edited", year: 1987, genre: "My genre")
        edited.tagsInspected = nil
        let empty = song("Empty"), removed = song("Removed"), replaced = song("Replaced")
        let updates = [edited, empty, removed, replaced].map {
            SongMetadataUpdate(id: $0.id, fileName: $0.fileName, genre: "Rock", year: 2001, readable: true)
        }
        var current = [edited, empty, replaced]
        current[2].fileName = "new-file.wav"
        XCTAssertTrue(SongMetadataUpdates.apply(updates, to: &current))
        XCTAssertEqual(current[0].genre, "My genre"); XCTAssertEqual(current[0].releaseYear, 1987)
        XCTAssertEqual(current[1].genre, "Rock"); XCTAssertEqual(current[1].releaseYear, 2001)
        XCTAssertNil(current[2].genre); XCTAssertNil(current[2].tagsInspected)
        XCTAssertEqual(current.count, 3)
        XCTAssertFalse(SongMetadataUpdates.apply(updates, to: &current))
    }
    func testPrecomputedCountsMatchWindowsAndSort() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_759_406_400)
        let a = song("A"), b = song("B"), c = song("C")
        let today = SmartListeningSnapshot.dayKey(now, calendar: calendar)
        let older = SmartListeningSnapshot.dayKey(calendar.date(byAdding: .day, value: -10, to: now)!, calendar: calendar)
        let future = SmartListeningSnapshot.dayKey(calendar.date(byAdding: .day, value: 1, to: now)!, calendar: calendar)
        let snapshot = SmartListeningSnapshot(total: [a.id: 99, b.id: 20], daily: [a.id: [today: 2, older: 8, future: 100], b.id: [today: 4]])
        for days: Int? in [nil, 0, 7, 30, 90] {
            let counts = snapshot.counts(days: days, now: now, calendar: calendar)
            for track in [a, b, c] {
                XCTAssertEqual(counts[track.id] ?? 0, snapshot.count(track.id, days: days, now: now, calendar: calendar))
            }
        }
        let localToday = SmartListeningSnapshot.dayKey(now)
        let localSnapshot = SmartListeningSnapshot(total: [a.id: 99, b.id: 20], daily: [a.id: [localToday: 2], b.id: [localToday: 4]])
        let definition = SmartPlaylistDefinition(rules: [SmartRule(periodDays: 7)], sort: .mostPlayed, periodDays: 7)
        XCTAssertEqual(SmartPlaylistEvaluator.songs(definition, from: [a, c, b], favorites: [], listening: localSnapshot, now: now).map(\.title), ["B", "A"])
    }
    func testBackgroundStorageKeepsLatestSnapshotAndDeletion() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let persistence = SongLibraryPersistence(url: url)
        let snapshotWritten = expectation(description: "Latest song snapshot written")
        var updated = song("Updated")
        updated.genre = "Rock"; updated.releaseYear = 1990
        for index in 0..<100 { persistence.submit([song("Old \(index)")]) }
        persistence.submit([updated], immediately: true) {
            XCTAssertFalse(Thread.isMainThread)
            snapshotWritten.fulfill()
        }
        // XCTest's wait services the run loop; a semaphore blocks the test
        // thread while the simulator is completing background file work.
        wait(for: [snapshotWritten], timeout: 30)
        XCTAssertEqual(try JSONDecoder().decode([Song].self, from: Data(contentsOf: url)), [updated])
        let deletionWritten = expectation(description: "Empty song snapshot written")
        persistence.submit([], immediately: true) { deletionWritten.fulfill() }
        wait(for: [deletionWritten], timeout: 30)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(try JSONDecoder().decode([Song].self, from: Data(contentsOf: url)), [])
    }
    func testMixMatchesCompatibleTempoAndFallsBackForOthers() {
        let outro = BeatAnalysis(bpm: 120, confidence: 0.9, firstBeat: 0.2), intro = BeatAnalysis(bpm: 116, confidence: 0.9, firstBeat: 0.1)
        let matched = AudioTransitionPlan.make(mode: .mix, seconds: 5, outgoingDuration: 120, incomingDuration: 120, outro: outro, intro: intro)
        XCTAssertTrue(matched.beatMatched); XCTAssertEqual(matched.overlap, 4)
        XCTAssertEqual(matched.incomingRate, 120 / 116.0, accuracy: 0.001); XCTAssertTrue((0.92...1.08).contains(matched.incomingRate))
        XCTAssertTrue((0...0.5).contains(matched.outgoingTrim))
        let incompatible = AudioTransitionPlan.make(mode: .mix, seconds: 5, outgoingDuration: 120, incomingDuration: 120, outro: outro, intro: BeatAnalysis(bpm: 150, confidence: 0.9))
        XCTAssertFalse(incompatible.beatMatched); XCTAssertEqual(incompatible.incomingRate, 1)
        XCTAssertFalse(AudioTransitionPlan.make(mode: .mix, seconds: 5, outgoingDuration: 100, incomingDuration: 100).beatMatched)
    }
    func testBeatDetectorFindsOffsetBeatPhase() {
        var samples = [Float](repeating: 0, count: 12000)
        for beat in 0..<24 {
            let start = 170 + beat * 500
            for frame in 0..<10 { samples[start + frame] = 1 }
        }
        let result = BeatDetector.analyze(samples, sampleRate: 1000)
        XCTAssertEqual(result.bpm, 120, accuracy: 1)
        XCTAssertEqual(result.firstBeat, 0.17, accuracy: 0.01)
        XCTAssertGreaterThan(result.confidence, 0.35)
    }
    func testBeatDetectorRecognizesSyntheticRhythmAndSilence() {
        let rate = 11025.0
        var samples = [Float](repeating: 0, count: Int(rate * 12))
        for beat in 0..<24 {
            let start = Int(Double(beat) * rate / 2)
            for frame in 0..<300 { samples[start + frame] = Float(exp(-Double(frame) / 45) * cos(Double(frame) * 0.06)) }
        }
        let result = BeatDetector.analyze(samples, sampleRate: rate)
        XCTAssertEqual(result.bpm, 120, accuracy: 3); XCTAssertGreaterThan(result.confidence, 0.35)
        XCTAssertEqual(BeatDetector.analyze([Float](repeating: 0, count: 50000), sampleRate: rate).confidence, 0)
    }
}
