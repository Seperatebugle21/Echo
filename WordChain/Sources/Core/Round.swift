import Foundation

/// The kinds of round. A day has three bridges, one triple bridge and one long bridge.
enum RoundKind: String, Codable, CaseIterable {
    /// "SUN ▢ POT": one word that fits after the first clue and before the second.
    case bridge
    /// Three clues that all link with the same word, on either side.
    case tripleBridge
    /// "BOOK ▢ ▢ STORE": two words in a row between the clues.
    case longBridge
}

/// A clue word and the side of the answer it sits on.
struct Clue: Codable, Equatable, Hashable {
    enum Side: String, Codable {
        /// The clue comes first: "foot" + answer.
        case before
        /// The clue comes after: answer + "ball".
        case after
    }

    var word: String
    var side: Side
}

/// One word the player has to find within a round.
struct AnswerSlot: Codable, Equatable {
    enum Result: String, Codable { case correct, wrong }

    var answer: String
    /// Letters from the start shown by hints.
    var hintLetters: Int = 0
    var guess: String?
    var result: Result?

    var length: Int { answer.count }
    var isDone: Bool { result != nil }
}

struct Round: Codable, Equatable, Identifiable {
    static let maxPoints = 1000
    /// Points a hint letter costs, per slot, as a share of the slot's value.
    static let hintCostShare = 0.2

    var id: Int
    var kind: RoundKind
    var clues: [Clue]
    var slots: [AnswerSlot]

    var isDone: Bool { slots.allSatisfy(\.isDone) }
    var isPerfect: Bool { slots.allSatisfy { $0.result == .correct && $0.hintLetters == 0 } }
    var correctSlots: Int { slots.filter { $0.result == .correct }.count }

    /// The first slot still to be guessed.
    var activeSlotIndex: Int? { slots.firstIndex { !$0.isDone } }

    /// Points for each slot: the round's value split over its slots, minus hints.
    func value(ofSlot index: Int) -> Int {
        let full = Round.maxPoints / slots.count
        let cost = Int(Double(full) * Round.hintCostShare) * slots[index].hintLetters
        return max(full - cost, full / 5)
    }

    var points: Int {
        slots.indices.reduce(0) { total, index in
            total + (slots[index].result == .correct ? value(ofSlot: index) : 0)
        }
    }

    /// Clue shown in front of the slots.
    var leadingClue: Clue? { clues.first { $0.side == .before } }
    /// Clue shown after the slots.
    var trailingClue: Clue? { clues.last { $0.side == .after } }

    /// Every word in the round, to keep a day free of repeats.
    var allWords: [String] { clues.map(\.word) + slots.map(\.answer) }

    /// A stable text that identifies a round.
    var signature: String {
        kind.rawValue + ":" + clues.map { "\($0.side == .before ? "<" : ">")\($0.word)" }.sorted().joined(separator: ",")
    }

    /// Whether `guess` fits slot `index`, given what is already known.
    /// Accepts other words than the planned answer when they link just as well.
    func accepts(_ guess: String, slot index: Int, graph: WordGraph) -> Bool {
        if guess == slots[index].answer { return true }
        guard guess.count == slots[index].length,
              guess.hasPrefix(String(slots[index].answer.prefix(slots[index].hintLetters))),
              !clues.contains(where: { $0.word == guess }) else { return false }

        switch kind {
        case .bridge, .tripleBridge:
            return clues.allSatisfy { clue in
                clue.side == .before ? graph.links(clue.word, guess) : graph.links(guess, clue.word)
            }
        case .longBridge:
            guard let first = leadingClue?.word, let last = trailingClue?.word else { return false }
            if index == 0 {
                // The second word must still be findable from this guess.
                return graph.links(first, guess)
                    && (graph.following[guess] ?? []).contains { graph.links($0, last) && $0.count == slots[1].length }
            }
            let previous = slots[0].guess ?? slots[0].answer
            return graph.links(previous, guess) && graph.links(guess, last)
        }
    }
}
