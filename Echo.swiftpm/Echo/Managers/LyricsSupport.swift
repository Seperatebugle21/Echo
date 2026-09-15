import Foundation

enum LyricsProvider: String, Codable, CaseIterable, Identifiable {
    case automatic, musixmatch, lrclib, genius
    var id: String { rawValue }
    var titleKey: String { "lyrics_provider_\(rawValue)" }
}

enum LyricsMatching {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func title(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: #"(?i)\b(?:feat\.?|ft\.?|featuring)\s+.*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)[\[(]\s*(?:official\s+)?(?:music\s+video|audio|video|lyrics)\s*[\])]"#, with: "", options: .regularExpression)
        return normalized(clean)
    }

    private static func versions(_ text: String) -> Set<String> {
        let words = Set(normalized(text).split(separator: " ").map(String.init))
        let markers: Set<String> = ["live", "remix", "acoustic", "instrumental", "karaoke", "demo", "remaster", "remastered", "radio", "edit", "sped", "slowed"]
        return Set(words.intersection(markers).map { $0 == "remastered" ? "remaster" : $0 })
    }

    static func score(title expectedTitle: String, artist expectedArtist: String, duration expectedDuration: Double,
                      candidateTitle: String, candidateArtist: String, candidateDuration: Double?) -> Double? {
        guard versions(expectedTitle) == versions(candidateTitle) else { return nil }
        let expected = title(expectedTitle), candidate = title(candidateTitle)
        guard !expected.isEmpty, !candidate.isEmpty else { return nil }
        let a = Set(expected.split(separator: " ")), b = Set(candidate.split(separator: " "))
        let titleScore = expected == candidate ? 1 : Double(a.intersection(b).count) / Double(a.union(b).count)
        guard titleScore >= 0.85, (a.count > 2 && b.count > 2) || expected == candidate else { return nil }
        let artists = Set(normalized(expectedArtist).split(separator: " ").filter { $0 != "the" })
        let candidates = Set(normalized(candidateArtist).split(separator: " ").filter { $0 != "the" })
        guard !artists.isEmpty, !candidates.isEmpty else { return nil }
        let artistScore = Double(artists.intersection(candidates).count) / Double(artists.union(candidates).count)
        guard artists.isSubset(of: candidates) || artistScore >= 0.66 else { return nil }
        var timingScore = 0.0
        if expectedDuration.isFinite, expectedDuration > 0, let actual = candidateDuration, actual.isFinite, actual > 0 {
            let tolerance = min(8, max(3, expectedDuration * 0.02))
            let difference = abs(actual - expectedDuration)
            guard difference <= tolerance else { return nil }
            timingScore = 1 - difference / tolerance
        }
        return titleScore * 10 + artistScore * 3 + timingScore
    }
}
