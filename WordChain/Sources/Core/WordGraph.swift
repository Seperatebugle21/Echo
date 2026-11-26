import Foundation

/// Every link between two words, read from a bundled list.
///
/// A link `a → b` means "a" followed by "b" forms a real compound word or
/// fixed phrase: fire → fly (firefly), boek → kast (boekenkast).
struct WordGraph {
    let language: GameLanguage
    /// Words that can follow a word, sorted so generation is deterministic.
    private(set) var following: [String: [String]] = [:]
    /// Words that can come before a word, sorted.
    private(set) var preceding: [String: [String]] = [:]
    /// Written forms that differ from simply gluing the two words together.
    private var writtenForms: [String: String] = [:]
    private var linkSet: Set<String> = []
    /// All words, sorted.
    private(set) var words: [String] = []

    var linkCount: Int { linkSet.count }

    init(text: String, language: GameLanguage) {
        self.language = language
        var following: [String: Set<String>] = [:]
        var preceding: [String: Set<String>] = [:]
        var all = Set<String>()

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let halves = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let parts = halves[0].split(separator: " ").map { String($0).lowercased() }
            guard parts.count == 2, parts[0] != parts[1],
                  parts.allSatisfy({ WordGraph.isPlayable($0) }) else { continue }
            let (first, second) = (parts[0], parts[1])
            following[first, default: []].insert(second)
            preceding[second, default: []].insert(first)
            all.insert(first)
            all.insert(second)
            let key = WordGraph.key(first, second)
            linkSet.insert(key)
            if halves.count == 2, !halves[1].isEmpty {
                writtenForms[key] = halves[1].lowercased()
            }
        }
        self.following = following.mapValues { $0.sorted() }
        self.preceding = preceding.mapValues { $0.sorted() }
        self.words = all.sorted()
    }

    /// Loads the list for a language from the app bundle.
    static func load(_ language: GameLanguage, bundle: Bundle = .main) -> WordGraph {
        guard let url = bundle.url(forResource: language.resourceName, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("Missing word list \(language.resourceName).txt")
            return WordGraph(text: "", language: language)
        }
        return WordGraph(text: text, language: language)
    }

    static func isPlayable(_ word: String) -> Bool {
        (2...12).contains(word.count) && word.allSatisfy { ("a"..."z").contains($0) }
    }

    private static func key(_ a: String, _ b: String) -> String { a + " " + b }

    func links(_ first: String, _ second: String) -> Bool {
        linkSet.contains(WordGraph.key(first, second))
    }

    func contains(_ word: String) -> Bool {
        following[word] != nil || preceding[word] != nil
    }

    /// How the two linked words are written together.
    func compound(_ first: String, _ second: String) -> String {
        if let written = writtenForms[WordGraph.key(first, second)] { return written }
        switch language {
        case .dutch: return first + second
        case .english: return first + " " + second
        }
    }
}
