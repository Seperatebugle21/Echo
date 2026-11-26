import Foundation

/// Builds rounds from the link graph. With the same seed it always builds the same rounds.
struct RoundGenerator {
    /// Answer lengths that fit the board comfortably.
    static let answerLengths = 3...9

    let graph: WordGraph
    private let middles: [String]
    private let middleSet: Set<String>
    private let tripleHubs: [String]

    init(graph: WordGraph) {
        self.graph = graph
        middles = graph.words.filter { word in
            Self.answerLengths.contains(word.count)
                && !(graph.preceding[word] ?? []).isEmpty
                && !(graph.following[word] ?? []).isEmpty
        }
        middleSet = Set(middles)
        tripleHubs = graph.words.filter { word in
            Self.answerLengths.contains(word.count)
                && (graph.preceding[word]?.count ?? 0) + (graph.following[word]?.count ?? 0) >= 3
        }
    }

    // MARK: Public

    /// The five rounds of a day: three bridges, a triple bridge and a long bridge.
    func dailyRounds(language: GameLanguage, dayIndex: Int) -> [Round] {
        var rng = SplitMix64(seed: stableHash("schakel/\(language.rawValue)/day/\(dayIndex)"))
        var used = Set<String>()
        let plan: [RoundKind] = [.bridge, .bridge, .bridge, .tripleBridge, .longBridge]
        var rounds: [Round] = []
        for (index, kind) in plan.enumerated() {
            if let round = makeRound(kind, id: index, using: &rng, avoidingWords: used) {
                rounds.append(round)
                used.formUnion(round.allWords)
            }
        }
        return rounds
    }

    /// A round of the given kind, or nil if the word list cannot make one.
    func makeRound<R: RandomNumberGenerator>(
        _ kind: RoundKind,
        id: Int,
        using rng: inout R,
        avoidingWords: Set<String> = [],
        avoidingSignatures: Set<String> = []
    ) -> Round? {
        // Look for a round with a single answer first, then accept a second answer.
        for allowedAnswers in [1, 2, 3] {
            for _ in 0..<160 {
                let candidate: Round?
                switch kind {
                case .bridge: candidate = bridge(id: id, rng: &rng, maxAnswers: allowedAnswers)
                case .tripleBridge: candidate = tripleBridge(id: id, rng: &rng, maxAnswers: allowedAnswers)
                case .longBridge: candidate = longBridge(id: id, rng: &rng, maxAnswers: allowedAnswers)
                }
                guard let round = candidate,
                      round.allWords.allSatisfy({ !avoidingWords.contains($0) }),
                      !avoidingSignatures.contains(round.signature) else { continue }
                return round
            }
        }
        return nil
    }

    /// How many distinct rounds of each kind the word list can make (an estimate for bridges).
    func capacity() -> [RoundKind: Int] {
        var bridges = 0
        for middle in middles {
            bridges += (graph.preceding[middle]?.count ?? 0) * (graph.following[middle]?.count ?? 0)
        }
        var triples = 0
        for hub in tripleHubs {
            let n = (graph.preceding[hub]?.count ?? 0) + (graph.following[hub]?.count ?? 0)
            triples += n * (n - 1) * (n - 2) / 6
        }
        var longs = 0
        for first in middles {
            for second in graph.following[first] ?? [] where middleSet.contains(second) {
                longs += (graph.preceding[first]?.count ?? 0) * (graph.following[second]?.count ?? 0)
            }
        }
        return [.bridge: bridges, .tripleBridge: triples, .longBridge: longs]
    }

    // MARK: Kinds

    private func bridge<R: RandomNumberGenerator>(id: Int, rng: inout R, maxAnswers: Int) -> Round? {
        guard let middle = middles.randomElement(using: &rng),
              let before = graph.preceding[middle]?.randomElement(using: &rng),
              let after = graph.following[middle]?.randomElement(using: &rng),
              distinct([before, middle, after]) else { return nil }
        let clues = [Clue(word: before, side: .before), Clue(word: after, side: .after)]
        guard answers(for: clues, length: middle.count).count <= maxAnswers else { return nil }
        return Round(id: id, kind: .bridge, clues: clues, slots: [AnswerSlot(answer: middle)])
    }

    private func tripleBridge<R: RandomNumberGenerator>(id: Int, rng: inout R, maxAnswers: Int) -> Round? {
        guard let hub = tripleHubs.randomElement(using: &rng) else { return nil }
        var options = (graph.preceding[hub] ?? []).map { Clue(word: $0, side: .before) }
            + (graph.following[hub] ?? []).map { Clue(word: $0, side: .after) }
        options.shuffle(using: &rng)
        let clues = Array(options.prefix(3))
        guard clues.count == 3, distinct(clues.map(\.word) + [hub]),
              answers(for: clues, length: hub.count).count <= maxAnswers else { return nil }
        // Clues in front of the answer first, so the board reads naturally.
        let ordered = clues.filter { $0.side == .before } + clues.filter { $0.side == .after }
        return Round(id: id, kind: .tripleBridge, clues: ordered, slots: [AnswerSlot(answer: hub)])
    }

    private func longBridge<R: RandomNumberGenerator>(id: Int, rng: inout R, maxAnswers: Int) -> Round? {
        guard let first = middles.randomElement(using: &rng),
              let start = graph.preceding[first]?.randomElement(using: &rng),
              let second = graph.following[first]?.filter({ middleSet.contains($0) }).randomElement(using: &rng),
              let end = graph.following[second]?.randomElement(using: &rng),
              distinct([start, first, second, end]) else { return nil }
        var pairs = 0
        for x in graph.following[start] ?? [] where x.count == first.count {
            for y in graph.following[x] ?? [] where y.count == second.count && graph.links(y, end) {
                pairs += 1
            }
        }
        guard pairs <= maxAnswers else { return nil }
        return Round(id: id, kind: .longBridge,
                     clues: [Clue(word: start, side: .before), Clue(word: end, side: .after)],
                     slots: [AnswerSlot(answer: first), AnswerSlot(answer: second)])
    }

    // MARK: Helpers

    /// Every word of the given length that fits all clues.
    func answers(for clues: [Clue], length: Int) -> [String] {
        guard let firstClue = clues.first else { return [] }
        let pool = firstClue.side == .before
            ? graph.following[firstClue.word] ?? []
            : graph.preceding[firstClue.word] ?? []
        return pool.filter { word in
            word.count == length && clues.allSatisfy { clue in
                clue.side == .before ? graph.links(clue.word, word) : graph.links(word, clue.word)
            }
        }
    }

    /// No word repeats or hides inside another, so clues never give the answer away.
    private func distinct(_ words: [String]) -> Bool {
        for (i, a) in words.enumerated() {
            for b in words[(i + 1)...] where a.hasPrefix(b) || b.hasPrefix(a) || a.hasSuffix(b) || b.hasSuffix(a) {
                return false
            }
        }
        return true
    }
}
