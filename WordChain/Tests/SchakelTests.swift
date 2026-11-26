import XCTest
@testable import Schakel

final class WordGraphTests: XCTestCase {
    func testBothWordListsLoad() {
        for language in GameLanguage.allCases {
            let graph = WordGraph.load(language)
            XCTAssertGreaterThan(graph.linkCount, 1_000, "\(language) list is too small")
            XCTAssertGreaterThan(graph.words.count, 500)
        }
    }

    func testParsesWrittenForms() {
        let graph = WordGraph(text: "# comment\nboek kast = boekenkast\nzon bloem\n", language: .dutch)
        XCTAssertTrue(graph.links("boek", "kast"))
        XCTAssertFalse(graph.links("kast", "boek"))
        XCTAssertEqual(graph.compound("boek", "kast"), "boekenkast")
        XCTAssertEqual(graph.compound("zon", "bloem"), "zonbloem")
        XCTAssertEqual(graph.following["boek"], ["kast"])
        XCTAssertEqual(graph.preceding["bloem"], ["zon"])
    }

    func testEnglishCompoundsKeepASpace() {
        let graph = WordGraph(text: "bus stop", language: .english)
        XCTAssertEqual(graph.compound("bus", "stop"), "bus stop")
    }
}

final class RoundGeneratorTests: XCTestCase {
    func testDailyRoundsAreStableAndComplete() {
        for language in GameLanguage.allCases {
            let generator = RoundGenerator(graph: WordGraph.load(language))
            for day in stride(from: 0, to: 730, by: 7) {
                let rounds = generator.dailyRounds(language: language, dayIndex: day)
                XCTAssertEqual(rounds.map(\.kind), [.bridge, .bridge, .bridge, .tripleBridge, .longBridge],
                               "\(language) day \(day)")
                XCTAssertEqual(rounds, generator.dailyRounds(language: language, dayIndex: day))
                let words = rounds.flatMap(\.allWords)
                XCTAssertEqual(words.count, Set(words).count, "Repeated word on \(language) day \(day)")
            }
        }
    }

    func testDaysDiffer() {
        let generator = RoundGenerator(graph: WordGraph.load(.english))
        let a = generator.dailyRounds(language: .english, dayIndex: 10)
        let b = generator.dailyRounds(language: .english, dayIndex: 11)
        XCTAssertNotEqual(a.map(\.signature), b.map(\.signature))
    }

    func testRoundsAreValid() {
        for language in GameLanguage.allCases {
            let graph = WordGraph.load(language)
            let generator = RoundGenerator(graph: graph)
            var rng = SplitMix64(seed: 42)
            for kind in RoundKind.allCases {
                for _ in 0..<150 {
                    guard let round = generator.makeRound(kind, id: 0, using: &rng) else {
                        return XCTFail("No \(kind) round for \(language)")
                    }
                    for (index, slot) in round.slots.enumerated() {
                        XCTAssertTrue(round.accepts(slot.answer, slot: index, graph: graph))
                        XCTAssertTrue(RoundGenerator.answerLengths.contains(slot.length))
                    }
                    switch kind {
                    case .bridge, .tripleBridge:
                        for clue in round.clues {
                            let answer = round.slots[0].answer
                            XCTAssertTrue(clue.side == .before ? graph.links(clue.word, answer) : graph.links(answer, clue.word))
                        }
                    case .longBridge:
                        let chain = [round.clues[0].word, round.slots[0].answer, round.slots[1].answer, round.clues[1].word]
                        for pair in zip(chain, chain.dropFirst()) {
                            XCTAssertTrue(graph.links(pair.0, pair.1), "\(chain)")
                        }
                    }
                }
            }
        }
    }

    func testEndlessNeverRunsDry() {
        for language in GameLanguage.allCases {
            let generator = RoundGenerator(graph: WordGraph.load(language))
            var rng = SplitMix64(seed: 7)
            var seen = Set<String>()
            for index in 0..<1_500 {
                let kind = RoundKind.allCases[index % 3]
                guard let round = generator.makeRound(kind, id: index, using: &rng, avoidingSignatures: seen) else {
                    return XCTFail("Ran out after \(index) rounds in \(language)")
                }
                XCTAssertFalse(seen.contains(round.signature))
                seen.insert(round.signature)
            }
        }
    }

    func testCapacityIsLarge() {
        for language in GameLanguage.allCases {
            let capacity = RoundGenerator(graph: WordGraph.load(language)).capacity()
            XCTAssertGreaterThan(capacity.values.reduce(0, +), 50_000, "\(language)")
        }
    }
}

final class GameSessionTests: XCTestCase {
    private let graph = WordGraph(text: """
    sun flower
    flower pot
    sun light
    light house
    house work
    tooth brush
    hair brush
    brush fire
    hair cut
    """, language: .english)

    private var bridge: Round {
        Round(id: 0, kind: .bridge,
              clues: [Clue(word: "sun", side: .before), Clue(word: "pot", side: .after)],
              slots: [AnswerSlot(answer: "flower")])
    }

    private func type(_ word: String, into session: inout GameSession) {
        for letter in word { session.type(letter) }
    }

    func testCorrectAnswerScoresFullPoints() {
        var session = GameSession(mode: .daily, language: .english, dayIndex: 0, rounds: [bridge])
        type("flower", into: &session)
        XCTAssertEqual(session.submit(graph: graph), .correct(alternative: false))
        XCTAssertEqual(session.score, 1000)
        XCTAssertTrue(session.canAdvance)
        session.advance { nil }
        XCTAssertEqual(session.status, .finished)
        XCTAssertEqual(session.resultSquares, "🟩")
    }

    func testTypingStopsAtWordLength() {
        var session = GameSession(mode: .daily, language: .english, dayIndex: 0, rounds: [bridge])
        type("flowerpot", into: &session)
        XCTAssertEqual(session.typed, "flower")
        session.deleteLetter()
        XCTAssertEqual(session.submit(graph: graph), .incomplete)
        XCTAssertEqual(session.typed, "flowe")
    }

    func testHintsCostPoints() {
        var session = GameSession(mode: .daily, language: .english, dayIndex: 0, rounds: [bridge])
        XCTAssertTrue(session.useHint())
        XCTAssertTrue(session.useHint())
        XCTAssertEqual(session.remainingLetters, 4)
        type("ower", into: &session)
        XCTAssertEqual(session.submit(graph: graph), .correct(alternative: false))
        XCTAssertEqual(session.score, 600)
        XCTAssertEqual(session.resultSquares, "🟨")
    }

    func testHintsLeaveOneLetter() {
        var session = GameSession(mode: .daily, language: .english, dayIndex: 0, rounds: [bridge])
        for _ in 0..<5 { XCTAssertTrue(session.useHint()) }
        XCTAssertFalse(session.useHint())
        XCTAssertEqual(session.remainingLetters, 1)
    }

    func testWrongAnswerScoresNothing() {
        var session = GameSession(mode: .daily, language: .english, dayIndex: 0, rounds: [bridge])
        type("flowey", into: &session)
        XCTAssertEqual(session.submit(graph: graph), .wrong)
        XCTAssertEqual(session.score, 0)
        XCTAssertTrue(session.canAdvance)
        XCTAssertEqual(session.resultSquares, "🟥")
    }

    func testAcceptsOtherFittingWord() {
        let round = Round(id: 0, kind: .tripleBridge,
                          clues: [Clue(word: "tooth", side: .before), Clue(word: "hair", side: .before), Clue(word: "fire", side: .after)],
                          slots: [AnswerSlot(answer: "brush")])
        XCTAssertTrue(round.accepts("brush", slot: 0, graph: graph))
        XCTAssertFalse(round.accepts("cut", slot: 0, graph: graph))

        let open = Round(id: 0, kind: .bridge,
                         clues: [Clue(word: "hair", side: .before), Clue(word: "fire", side: .after)],
                         slots: [AnswerSlot(answer: "brush")])
        XCTAssertTrue(open.accepts("brush", slot: 0, graph: graph))
    }

    func testLongBridge() {
        let round = Round(id: 0, kind: .longBridge,
                          clues: [Clue(word: "sun", side: .before), Clue(word: "work", side: .after)],
                          slots: [AnswerSlot(answer: "light"), AnswerSlot(answer: "house")])
        var session = GameSession(mode: .daily, language: .english, dayIndex: 0, rounds: [round])
        type("light", into: &session)
        XCTAssertEqual(session.submit(graph: graph), .correct(alternative: false))
        XCTAssertFalse(session.canAdvance)
        type("house", into: &session)
        XCTAssertEqual(session.submit(graph: graph), .correct(alternative: false))
        XCTAssertEqual(session.score, 1000)
    }

    func testEndlessRunEndsWhenLivesRunOut() {
        var session = GameSession(mode: .endless, language: .english, dayIndex: nil, rounds: [bridge])
        for _ in 0..<GameSession.endlessLives {
            session.skip()
            session.advance { self.bridge }
        }
        XCTAssertEqual(session.livesLeft, 0)
        XCTAssertEqual(session.status, .finished)
    }

    func testEndlessKeepsGoing() {
        var session = GameSession(mode: .endless, language: .english, dayIndex: nil, rounds: [bridge])
        for _ in 0..<50 {
            type("flower", into: &session)
            XCTAssertEqual(session.submit(graph: graph), .correct(alternative: false))
            session.advance { self.bridge }
        }
        XCTAssertEqual(session.status, .playing)
        XCTAssertEqual(session.correctRounds, 50)
        XCTAssertEqual(session.streak, 50)
    }

    func testSessionSurvivesEncoding() throws {
        var session = GameSession(mode: .daily, language: .dutch, dayIndex: 3, rounds: [bridge])
        type("flo", into: &session)
        let data = try JSONEncoder().encode(session)
        XCTAssertEqual(try JSONDecoder().decode(GameSession.self, from: data), session)
    }
}

final class StatsTests: XCTestCase {
    func testStreaks() {
        var stats = PlayerStats()
        for day in [1, 2, 3, 5, 6] {
            stats.days[day] = DayResult(dayIndex: day, score: 3000, squares: "", onTheDay: true)
        }
        stats.days[4] = DayResult(dayIndex: 4, score: 5000, squares: "", onTheDay: false)
        XCTAssertEqual(stats.currentStreak(today: 6), 2)
        XCTAssertEqual(stats.currentStreak(today: 7), 2)
        XCTAssertEqual(stats.currentStreak(today: 8), 0)
        XCTAssertEqual(stats.longestStreak, 3)
        XCTAssertEqual(stats.perfectDays, 1)
        XCTAssertEqual(stats.scoreBands, [0, 0, 0, 5, 0, 1])
    }

    func testCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9))!
        XCTAssertEqual(PuzzleCalendar.dayIndex(for: start, calendar: calendar), 0)
        let later = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 23))!
        XCTAssertEqual(PuzzleCalendar.dayIndex(for: later, calendar: calendar), 329)
    }
}
