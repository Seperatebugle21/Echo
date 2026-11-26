import Foundation

/// All interface text, in Dutch and English. Switches at once with the game language.
struct L10n {
    let language: GameLanguage

    private func t(_ nl: String, _ en: String) -> String {
        language == .dutch ? nl : en
    }

    // MARK: Home
    var tagline: String { t("Vind het woord dat de woorden verbindt.", "Find the word that links the words.") }
    var daily: String { t("Dagpuzzel", "Daily puzzle") }
    var dailySubtitle: String { t("5 rondes · voor iedereen dezelfde", "5 rounds · the same for everyone") }
    var endless: String { t("Eindeloos", "Endless") }
    var endlessSubtitle: String { t("Ronde na ronde, tot je levens op zijn", "Round after round until your lives run out") }
    var archive: String { t("Archief", "Archive") }
    var archiveSubtitle: String { t("Speel eerdere dagen", "Play past days") }
    var statistics: String { t("Statistieken", "Statistics") }
    var settings: String { t("Instellingen", "Settings") }
    var howToPlay: String { t("Hoe speel je?", "How to play") }
    var play: String { t("Spelen", "Play") }
    var resume: String { t("Verder spelen", "Continue") }
    var done: String { t("Klaar", "Done") }
    var close: String { t("Sluiten", "Close") }
    func puzzleNumber(_ n: Int) -> String { t("Puzzel #\(n)", "Puzzle #\(n)") }
    func streakDays(_ n: Int) -> String { t("\(n) \(n == 1 ? "dag" : "dagen") op rij", "\(n)-day streak") }
    var nextPuzzleIn: String { t("Volgende puzzel over", "Next puzzle in") }
    func bestRun(_ n: Int) -> String { t("Beste reeks: \(n)", "Best run: \(n)") }
    func scoreToday(_ n: Int) -> String { t("Vandaag: \(n) punten", "Today: \(n) points") }

    // MARK: Rounds
    func roundOf(_ n: Int, _ total: Int) -> String { t("Ronde \(n) van \(total)", "Round \(n) of \(total)") }
    func round(_ n: Int) -> String { t("Ronde \(n)", "Round \(n)") }
    func kindTitle(_ kind: RoundKind) -> String {
        switch kind {
        case .bridge: return t("Tweewoordbrug", "Two-word bridge")
        case .tripleBridge: return t("Driewoordbrug", "Three-word bridge")
        case .longBridge: return t("Lange brug", "Long bridge")
        }
    }
    func kindHint(_ kind: RoundKind) -> String {
        switch kind {
        case .bridge: return t("Welk woord past achter het eerste en vóór het tweede?",
                               "Which word goes after the first and before the second?")
        case .tripleBridge: return t("Eén woord dat bij alle drie past.", "One word that fits all three.")
        case .longBridge: return t("Twee woorden op een rij verbinden het begin met het einde.",
                                   "Two words in a row link the start to the end.")
        }
    }
    var hint: String { t("Letter", "Letter") }
    var skip: String { t("Weet ik niet", "Pass") }
    var nextRound: String { t("Volgende ronde", "Next round") }
    var seeResult: String { t("Bekijk resultaat", "See result") }
    var correct: String { t("Juist!", "Correct!") }
    var alsoCorrect: String { t("Ook goed!", "Also right!") }
    var wrong: String { t("Helaas", "Not quite") }
    var notInList: String { t("Typ eerst alle letters", "Type every letter first") }
    func answerWas(_ word: String) -> String { t("Het was \(word.uppercased())", "It was \(word.uppercased())") }
    func points(_ n: Int) -> String { t("\(n) punten", "\(n) points") }
    var lives: String { t("Levens", "Lives") }
    var run: String { t("Reeks", "Run") }
    var endRun: String { t("Stoppen", "Stop") }
    var quitTitle: String { t("Spel verlaten?", "Leave the game?") }
    var quitMessage: String { t("Je voortgang blijft bewaard.", "Your progress is saved.") }
    var endRunTitle: String { t("Reeks beëindigen?", "End this run?") }
    var leave: String { t("Verlaten", "Leave") }
    var cancel: String { t("Annuleren", "Cancel") }

    // MARK: Results
    var dayComplete: String { t("Dagpuzzel klaar", "Daily puzzle done") }
    var runOver: String { t("Reeks voorbij", "Run over") }
    func roundsSolved(_ n: Int) -> String { t("\(n) \(n == 1 ? "ronde" : "rondes") opgelost", "\(n) \(n == 1 ? "round" : "rounds") solved") }
    var share: String { t("Delen", "Share") }
    var newRun: String { t("Nieuwe reeks", "New run") }
    var backHome: String { t("Naar start", "Home") }
    var perfect: String { t("Perfect!", "Perfect!") }
    var greatScore: String { t("Sterk gespeeld", "Well played") }
    var goodScore: String { t("Mooi gedaan", "Nice work") }
    var lowScore: String { t("Morgen beter", "Better luck tomorrow") }
    func shareText(number: Int?, score: Int, max: Int, squares: String, endless: Bool, run: Int) -> String {
        if endless {
            return t("Schakel Eindeloos 🔗 \(run) rondes · \(score) punten\n\(squares)",
                     "Schakel Endless 🔗 \(run) rounds · \(score) points\n\(squares)")
        }
        return "Schakel #\(number ?? 0) 🔗 \(score)/\(max)\n\(squares)"
    }

    // MARK: Stats
    var played: String { t("Gespeeld", "Played") }
    var average: String { t("Gemiddeld", "Average") }
    var best: String { t("Beste", "Best") }
    var currentStreak: String { t("Reeks", "Streak") }
    var longestStreak: String { t("Langste reeks", "Longest streak") }
    var perfectDays: String { t("Perfecte dagen", "Perfect days") }
    var scoreSpread: String { t("Scores", "Scores") }
    var endlessBestRun: String { t("Beste reeks", "Best run") }
    var endlessBestScore: String { t("Hoogste score", "High score") }
    var endlessSolved: String { t("Rondes opgelost", "Rounds solved") }
    var endlessRuns: String { t("Reeksen", "Runs") }
    var noGamesYet: String { t("Nog geen spellen gespeeld.", "No games played yet.") }

    // MARK: Archive
    var notPlayed: String { t("Niet gespeeld", "Not played") }
    var inProgress: String { t("Bezig", "In progress") }
    var today: String { t("Vandaag", "Today") }

    // MARK: Settings
    var languageTitle: String { t("Taal", "Language") }
    var languageFooter: String {
        t("De taal bepaalt ook de woorden. Elke taal heeft eigen puzzels en statistieken.",
          "The language also sets the words. Each language has its own puzzles and statistics.")
    }
    var appearance: String { t("Weergave", "Appearance") }
    var system: String { t("Systeem", "System") }
    var light: String { t("Licht", "Light") }
    var dark: String { t("Donker", "Dark") }
    var haptics: String { t("Trillingen", "Haptics") }
    var wordList: String { t("Woordenlijst", "Word list") }
    func wordListSize(words: Int, links: Int) -> String {
        t("\(words) woorden, \(links) verbindingen", "\(words) words, \(links) links")
    }
    func roundCapacity(_ n: Int) -> String {
        t("Goed voor meer dan \(n.formatted()) verschillende rondes",
          "Enough for over \(n.formatted()) different rounds")
    }

    // MARK: How to play
    var rulesIntro: String {
        t("Elke ronde geeft je woorden. Zoek het woord dat ermee een bestaand samengesteld woord of vaste combinatie vormt.",
          "Each round gives you clue words. Find the word that forms a real compound word or common phrase with them.")
    }
    var rulesBridge: String {
        t("ZON ▢ POT → BLOEM: zonnebloem en bloempot.", "SUN ▢ POT → FLOWER: sunflower and flower pot.")
    }
    var rulesTriple: String {
        t("VOET, HAND, ▢ SPEL → BAL: voetbal, handbal en balspel.",
          "FOOT, HAND, ▢ GAME → BALL: football, handball and ball game.")
    }
    var rulesLong: String {
        t("VOET ▢ ▢ JAS → BAD, KAMER: voetbad, badkamer en kamerjas.",
          "BOOK ▢ ▢ ROOM → CASE, STUDY: bookcase, case study and study room.")
    }
    var rulesGuess: String {
        t("Je hebt één poging per woord. Een goed antwoord is tot 1000 punten waard; elke letter die je vraagt kost punten.",
          "You get one guess per word. A right answer is worth up to 1000 points; every letter you ask for costs points.")
    }
    var rulesAlternative: String {
        t("Past een ander woord net zo goed? Dan telt het ook.",
          "Another word that fits just as well counts too.")
    }
    var rulesDaily: String {
        t("De dagpuzzel heeft 5 rondes: 3 tweewoordbruggen, 1 driewoordbrug en 1 lange brug. Samen 5000 punten.",
          "The daily puzzle has 5 rounds: 3 two-word bridges, 1 three-word bridge and 1 long bridge. 5000 points in all.")
    }
    var rulesEndless: String {
        t("In Eindeloos krijg je 3 levens. Elke fout kost er een. Hoe lang houd jij het vol?",
          "Endless gives you 3 lives. Every miss costs one. How long can you last?")
    }
}
