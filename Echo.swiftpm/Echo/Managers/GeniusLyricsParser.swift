import Foundation
import SwiftSoup

enum GeniusLyricsParser {
    static func parse(_ html: String) throws -> String? {
        let document = try SwiftSoup.parse(html)
        var containers = try document.select("[data-lyrics-container=true]").array()
        if containers.isEmpty { containers = try document.select("div.lyrics").array() }
        var sections: [String] = []
        for container in containers {
            try container.select("script, style, button, [aria-hidden=true], [data-exclude-from-selection=true], [class*=LyricsHeader]").remove()
            var text = ""
            appendText(container, to: &text)
            let cleaned = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { sections.append(cleaned) }
        }
        let lyrics = sections.joined(separator: "\n\n")
        return lyrics.isEmpty ? nil : lyrics
    }

    private static func appendText(_ node: Node, to output: inout String) {
        if let text = node as? TextNode {
            output += text.getWholeText()
            return
        }
        let tag = (node as? Element)?.tagName()
        if tag == "br" { output += "\n"; return }
        for child in node.getChildNodes() { appendText(child, to: &output) }
        if tag == "p" || tag == "div", !output.hasSuffix("\n") { output += "\n" }
    }
}
