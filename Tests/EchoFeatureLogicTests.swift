import Foundation
import XCTest

final class EchoFeatureLogicTests: XCTestCase {
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
