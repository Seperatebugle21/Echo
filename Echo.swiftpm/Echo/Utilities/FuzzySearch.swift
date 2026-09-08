import Foundation

enum FuzzySearch {

    static func matches(
        query: String,
        in values: [String?]
    ) -> Bool {

        let queryWords = words(in: query)

        guard !queryWords.isEmpty else {
            return true
        }

        let candidateWords = values
            .compactMap { $0 }
            .flatMap(words)

        guard !candidateWords.isEmpty else {
            return false
        }

        return queryWords.allSatisfy { queryWord in
            candidateWords.contains { candidateWord in
                word(queryWord, matches: candidateWord)
            }
        }
    }

    private static func words(in value: String) -> [String] {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .lowercased()
            .components(
                separatedBy: CharacterSet.alphanumerics.inverted
            )
            .filter { !$0.isEmpty }
    }

    private static func word(
        _ query: String,
        matches candidate: String
    ) -> Bool {

        if candidate.contains(query) {
            return true
        }

        let allowedDistance: Int

        switch max(query.count, candidate.count) {
        case 0...3:
            allowedDistance = 0
        case 4...6:
            allowedDistance = 1
        default:
            allowedDistance = 2
        }

        return editDistance(
            between: query,
            and: candidate,
            limit: allowedDistance
        ) <= allowedDistance
    }

    private static func editDistance(
        between lhs: String,
        and rhs: String,
        limit: Int
    ) -> Int {

        let left = Array(lhs)
        let right = Array(rhs)

        guard abs(left.count - right.count) <= limit else {
            return limit + 1
        }

        var previousPrevious: [Int]?
        var previous = Array(0...right.count)

        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]

            for (rightIndex, rightCharacter) in right.enumerated() {
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let substitution = previous[rightIndex]
                    + (leftCharacter == rightCharacter ? 0 : 1)
                var value = min(insertion, deletion, substitution)

                if
                    leftIndex > 0,
                    rightIndex > 0,
                    leftCharacter == right[rightIndex - 1],
                    left[leftIndex - 1] == rightCharacter,
                    let previousPrevious
                {
                    value = min(
                        value,
                        previousPrevious[rightIndex - 1] + 1
                    )
                }

                current.append(value)
            }

            previousPrevious = previous
            previous = current
        }

        return previous[right.count]
    }
}
