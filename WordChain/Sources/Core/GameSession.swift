import Foundation

enum GameMode: String, Codable, CaseIterable, Identifiable {
    /// Five rounds, the same for everyone that day.
    case daily
    /// A past day, from the archive. Does not count for the streak.
    case archive
    /// Round after round with no end, until the lives run out.
    case endless

    var id: String { rawValue }
}

enum GuessOutcome: Equatable {
    case correct(alternative: Bool)
    case wrong
    /// Not every letter is typed yet.
    case incomplete
    case notPlaying
}

/// The state of a game. Codable so a game survives closing the app.
struct GameSession: Codable, Equatable {
    enum Status: String, Codable { case playing, finished }

    static let dailyRoundCount = 5
    /// Wrong answers an endless run can take before it ends.
    static let endlessLives = 3

    var mode: GameMode
    var language: GameLanguage
    /// Day number counted from the first puzzle (0). Nil in endless mode.
    var dayIndex: Int?
    var rounds: [Round]
    var currentRound: Int = 0
    var typed: String = ""
    var status: Status = .playing
    var livesLeft: Int = GameSession.endlessLives
    /// Rounds in a row answered right (endless).
    var streak: Int = 0
    var startedAt: Date = .init()

    init(mode: GameMode, language: GameLanguage, dayIndex: Int?, rounds: [Round]) {
        self.mode = mode
        self.language = language
        self.dayIndex = dayIndex
        self.rounds = rounds
    }

    var puzzleNumber: Int? { dayIndex.map { $0 + 1 } }

    // MARK: Reading

    var round: Round? { rounds.indices.contains(currentRound) ? rounds[currentRound] : nil }

    var activeSlot: AnswerSlot? {
        guard status == .playing, let round, let index = round.activeSlotIndex else { return nil }
        return round.slots[index]
    }

    /// Letters still to type for the active slot.
    var remainingLetters: Int {
        guard let slot = activeSlot else { return 0 }
        return slot.length - slot.hintLetters - typed.count
    }

    var score: Int { rounds.reduce(0) { $0 + $1.points } }
    var maxScore: Int { rounds.count * Round.maxPoints }
    var completedRounds: Int { rounds.filter(\.isDone).count }
    var correctRounds: Int { rounds.filter { $0.correctSlots == $0.slots.count }.count }

    /// True when the current round is answered and the next one can start.
    var canAdvance: Bool {
        guard status == .playing, let round else { return false }
        return round.isDone
    }

    var isLastDailyRound: Bool { mode != .endless && currentRound >= rounds.count - 1 }

    // MARK: Playing

    mutating func type(_ letter: Character) {
        guard remainingLetters > 0, let lower = letter.lowercased().first, ("a"..."z").contains(lower) else { return }
        typed.append(lower)
    }

    mutating func deleteLetter() {
        guard !typed.isEmpty else { return }
        typed.removeLast()
    }

    /// Checks the typed word. There is one guess per word.
    mutating func submit(graph: WordGraph) -> GuessOutcome {
        guard status == .playing, rounds.indices.contains(currentRound),
              let slotIndex = rounds[currentRound].activeSlotIndex else { return .notPlaying }
        guard remainingLetters == 0 else { return .incomplete }
        let slot = rounds[currentRound].slots[slotIndex]
        let guess = String(slot.answer.prefix(slot.hintLetters)) + typed
        typed = ""

        let right = rounds[currentRound].accepts(guess, slot: slotIndex, graph: graph)
        rounds[currentRound].slots[slotIndex].guess = guess
        rounds[currentRound].slots[slotIndex].result = right ? .correct : .wrong
        if right {
            let alternative = guess != slot.answer
            if alternative { rounds[currentRound].slots[slotIndex].answer = guess }
            if mode == .endless, rounds[currentRound].isDone, rounds[currentRound].correctSlots == rounds[currentRound].slots.count {
                streak += 1
            }
            return .correct(alternative: alternative)
        }

        if mode == .endless {
            livesLeft -= 1
            streak = 0
            // The rest of the round counts as lost too.
            for index in rounds[currentRound].slots.indices where !rounds[currentRound].slots[index].isDone {
                rounds[currentRound].slots[index].result = .wrong
            }
        }
        return .wrong
    }

    /// Shows the next letter of the active word, for fewer points. Leaves at least one letter to guess.
    @discardableResult
    mutating func useHint() -> Bool {
        guard status == .playing, rounds.indices.contains(currentRound),
              let slotIndex = rounds[currentRound].activeSlotIndex else { return false }
        let slot = rounds[currentRound].slots[slotIndex]
        guard slot.hintLetters < slot.length - 1 else { return false }
        rounds[currentRound].slots[slotIndex].hintLetters += 1
        typed = ""
        return true
    }

    /// Gives up the active word: it counts as wrong.
    mutating func skip() {
        guard status == .playing, rounds.indices.contains(currentRound),
              let slotIndex = rounds[currentRound].activeSlotIndex else { return }
        typed = ""
        rounds[currentRound].slots[slotIndex].result = .wrong
        if mode == .endless {
            livesLeft -= 1
            streak = 0
            for index in rounds[currentRound].slots.indices where !rounds[currentRound].slots[index].isDone {
                rounds[currentRound].slots[index].result = .wrong
            }
        }
    }

    /// Goes to the next round. In endless mode `nextRound` supplies it.
    /// Finishes the game after the last daily round or the last endless life.
    mutating func advance(nextRound: () -> Round?) {
        guard canAdvance else { return }
        typed = ""
        switch mode {
        case .daily, .archive:
            if currentRound >= rounds.count - 1 {
                status = .finished
            } else {
                currentRound += 1
            }
        case .endless:
            guard livesLeft > 0, var round = nextRound() else {
                status = .finished
                return
            }
            round.id = rounds.count
            rounds.append(round)
            currentRound = rounds.count - 1
        }
    }

    /// Ends an endless run early.
    mutating func endRun() {
        status = .finished
        typed = ""
    }

    // MARK: Sharing

    /// One square per round: green right first time, yellow right with hints or half right, red wrong.
    var resultSquares: String {
        rounds.filter(\.isDone).map { round in
            if round.isPerfect { return "🟩" }
            return round.correctSlots > 0 ? "🟨" : "🟥"
        }.joined()
    }
}
