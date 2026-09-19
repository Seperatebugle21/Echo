import Foundation

enum PodcastTranscriptParser {
    static func supports(_ type: String) -> Bool {
        ["text/plain", "text/html", "text/vtt", "application/x-subrip", "application/srt", "application/json"]
            .contains(mimeType(type))
    }

    static func parse(_ data: Data, type: String) throws -> String {
        let type = mimeType(type)
        let result: String
        if type == "application/json" {
            let transcript = try JSONDecoder().decode(JSONTranscript.self, from: data)
            result = transcript.segments.map { segment in
                let speaker = segment.speaker.map { "\($0): " } ?? ""
                return speaker + segment.body
            }.joined(separator: "\n\n")
        } else {
            guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                throw PodcastNetworkError.invalidResponse
            }
            let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            switch type {
            case "text/vtt", "application/x-subrip", "application/srt":
                result = text.components(separatedBy: "\n\n").compactMap { block -> String? in
                    let lines = block.components(separatedBy: "\n")
                    guard let timing = lines.firstIndex(where: { $0.contains("-->") }),
                          !block.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("NOTE") else { return nil }
                    let caption = lines.dropFirst(timing + 1).joined(separator: " ")
                        .replacingOccurrences(of: "<v(?:\\.[^ >]+)? ([^>]+)>", with: "$1: ", options: .regularExpression)
                    return PodcastFeedParser.plainText(caption)
                }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            case "text/html":
                let cleaned = text.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "(?i)</p>|<br\\s*/?>|</div>", with: "\n\n", options: .regularExpression)
                result = cleaned.components(separatedBy: "\n\n").map(PodcastFeedParser.plainText)
                    .filter { !$0.isEmpty }.joined(separator: "\n\n")
            case "text/plain": result = text
            default: throw PodcastNetworkError.invalidResponse
            }
        }
        let text = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PodcastNetworkError.invalidResponse }
        return text
    }

    private static func mimeType(_ value: String) -> String {
        value.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private struct JSONTranscript: Decodable {
        let segments: [Segment]
        struct Segment: Decodable {
            let body: String
            let speaker: String?
        }
    }
}
