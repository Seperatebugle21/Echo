import Foundation
import Observation
import SwiftUI

/// The app's state: settings, statistics and the game being played.
@MainActor
@Observable
final class AppModel {
    // MARK: Settings

    var language: GameLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    var appearance: AppearanceSetting {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var hapticsEnabled: Bool {
        didSet {
            defaults.set(hapticsEnabled, forKey: Keys.haptics)
            Haptics.enabled = hapticsEnabled
        }
    }

    /// Shown once, on the first launch.
    var hasSeenRules: Bool {
        didSet { defaults.set(hasSeenRules, forKey: Keys.seenRules) }
    }

    // MARK: State

    /// The game on screen, if any.
    var session: GameSession?
    private(set) var stats: [GameLanguage: PlayerStats] = [:]
    /// Today's puzzle number, refreshed when the app comes back.
    private(set) var today: Int = PuzzleCalendar.dayIndex()
    /// Goes up with every save, so screens showing saved games refresh.
    private(set) var saveRevision = 0

    var strings: L10n { L10n(language: language) }

    @ObservationIgnored private var graphs: [GameLanguage: WordGraph] = [:]
    @ObservationIgnored private var generators: [GameLanguage: RoundGenerator] = [:]
    @ObservationIgnored private var endlessRandom = SystemRandomNumberGenerator()
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: Keys.language).flatMap(GameLanguage.init(rawValue:)) ?? .deviceDefault
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppearanceSetting.init(rawValue:)) ?? .system
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        hasSeenRules = defaults.bool(forKey: Keys.seenRules)
        Haptics.enabled = hapticsEnabled
        for language in GameLanguage.allCases {
            stats[language] = load(PlayerStats.self, key: Keys.stats(language)) ?? PlayerStats()
        }
    }

    // MARK: Words

    func graph(for language: GameLanguage) -> WordGraph {
        if let graph = graphs[language] { return graph }
        let graph = WordGraph.load(language)
        graphs[language] = graph
        return graph
    }

    func generator(for language: GameLanguage) -> RoundGenerator {
        if let generator = generators[language] { return generator }
        let generator = RoundGenerator(graph: graph(for: language))
        generators[language] = generator
        return generator
    }

    var currentStats: PlayerStats { stats[language] ?? PlayerStats() }

    func refreshDay() {
        let now = PuzzleCalendar.dayIndex()
        if now != today { today = now }
    }

    // MARK: Starting games

    /// The saved game for a day, finished or not.
    func savedDay(_ day: Int, language: GameLanguage? = nil) -> GameSession? {
        load(GameSession.self, key: Keys.day(language ?? self.language, day))
    }

    var savedEndless: GameSession? {
        load(GameSession.self, key: Keys.endless(language)).flatMap { $0.status == .playing ? $0 : nil }
    }

    func startDaily() {
        refreshDay()
        open(day: today, mode: .daily)
    }

    func startArchive(day: Int) {
        open(day: day, mode: day == today ? .daily : .archive)
    }

    private func open(day: Int, mode: GameMode) {
        if let saved = savedDay(day) {
            session = saved
            return
        }
        let rounds = generator(for: language).dailyRounds(language: language, dayIndex: day)
        let new = GameSession(mode: mode, language: language, dayIndex: day, rounds: rounds)
        session = new
        save(new)
    }

    func startEndless(resume: Bool = true) {
        if resume, let saved = savedEndless {
            session = saved
            return
        }
        var first = GameSession(mode: .endless, language: language, dayIndex: nil, rounds: [])
        if let round = makeEndlessRound(after: first) { first.rounds = [round] }
        session = first
        save(first)
    }

    func closeGame() {
        session = nil
    }

    // MARK: Playing

    func type(_ letter: Character) {
        session?.type(letter)
    }

    func deleteLetter() {
        session?.deleteLetter()
    }

    func submit() -> GuessOutcome {
        guard var game = session else { return .notPlaying }
        let outcome = game.submit(graph: graph(for: game.language))
        session = game
        if outcome != .incomplete { save(game) }
        return outcome
    }

    func useHint() -> Bool {
        guard var game = session else { return false }
        let used = game.useHint()
        session = game
        if used { save(game) }
        return used
    }

    func skip() {
        guard var game = session else { return }
        game.skip()
        session = game
        save(game)
    }

    /// Next round, or the end of the game.
    func advance() {
        guard var game = session else { return }
        let before = game
        game.advance { self.makeEndlessRound(after: before) }
        session = game
        save(game)
        if game.status == .finished { record(game) }
    }

    func endRun() {
        guard var game = session, game.status == .playing else { return }
        game.endRun()
        session = game
        save(game)
        record(game)
    }

    // MARK: Endless rounds

    private func makeEndlessRound(after game: GameSession) -> Round? {
        let generator = generator(for: game.language)
        let recentKey = Keys.recent(game.language)
        var recent = defaults.stringArray(forKey: recentKey) ?? []
        let recentWords = Set(game.rounds.suffix(4).flatMap(\.allWords))

        // Mostly bridges; now and then the harder kinds, more often as the run goes on.
        let roll = Int(endlessRandom.next() % 100)
        let hardShare = min(15 + game.rounds.count, 40)
        let kind: RoundKind = roll < 100 - hardShare ? .bridge : (roll % 2 == 0 ? .tripleBridge : .longBridge)

        var rng = endlessRandom
        let round = generator.makeRound(kind, id: game.rounds.count, using: &rng,
                                        avoidingWords: recentWords, avoidingSignatures: Set(recent))
            ?? generator.makeRound(.bridge, id: game.rounds.count, using: &rng, avoidingWords: recentWords)
        endlessRandom = rng
        if let round {
            recent.append(round.signature)
            defaults.set(Array(recent.suffix(2_000)), forKey: recentKey)
        }
        return round
    }

    // MARK: Results

    private func record(_ game: GameSession) {
        var languageStats = stats[game.language] ?? PlayerStats()
        languageStats.record(game, today: today)
        stats[game.language] = languageStats
        store(languageStats, key: Keys.stats(game.language))
    }

    private func save(_ game: GameSession) {
        saveRevision += 1
        switch game.mode {
        case .daily, .archive:
            if let day = game.dayIndex { store(game, key: Keys.day(game.language, day)) }
        case .endless:
            store(game, key: Keys.endless(game.language))
        }
    }

    func resetStatistics() {
        stats[language] = PlayerStats()
        store(PlayerStats(), key: Keys.stats(language))
    }

    // MARK: Storage

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func store<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private enum Keys {
        static let language = "settings.language"
        static let appearance = "settings.appearance"
        static let haptics = "settings.haptics"
        static let seenRules = "settings.seenRules"
        static func stats(_ language: GameLanguage) -> String { "stats.\(language.rawValue)" }
        static func day(_ language: GameLanguage, _ day: Int) -> String { "game.\(language.rawValue).day.\(day)" }
        static func endless(_ language: GameLanguage) -> String { "game.\(language.rawValue).endless" }
        static func recent(_ language: GameLanguage) -> String { "recent.\(language.rawValue)" }
    }
}
