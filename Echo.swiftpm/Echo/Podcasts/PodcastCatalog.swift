import Foundation

enum PodcastNetworkError: Error { case invalidResponse, invalidFeed }

actor PodcastCatalog {
    static let shared = PodcastCatalog()
    private var searches: [String: (Date, [PodcastShow])] = [:]
    private var nextSearch = Date.distantPast

    func search(_ term: String, country: String) async throws -> [PodcastShow] {
        let key = country + ":" + term.lowercased()
        if let cached = searches[key], Date().timeIntervalSince(cached.0) < 300 { return cached.1 }
        let delay = max(0, nextSearch.timeIntervalSinceNow)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        nextSearch = Date().addingTimeInterval(3)
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "podcast"), URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "country", value: country), URLQueryItem(name: "limit", value: "50")]
        let data = try await fetch(components.url!)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        var seen = Set<Int>()
        let shows = response.results.compactMap { item -> PodcastShow? in
            guard let id = item.collectionId, let title = item.collectionName,
                  let feed = item.feedUrl, Self.isWebURL(feed), seen.insert(id).inserted else { return nil }
            return PodcastShow(id: id, title: title, author: item.artistName ?? "",
                               artworkURL: item.artworkUrl600 ?? item.artworkUrl100, feedURL: feed)
        }
        if searches.count > 50 { searches.removeAll() }
        searches[key] = (Date(), shows)
        return shows
    }

    func feed(for show: PodcastShow) async throws -> PodcastFeed {
        let data = try await fetch(show.feedURL)
        try Task.checkCancellation()
        return try PodcastFeedParser.parseFeed(data, show: show)
    }

    private func fetch(_ url: URL) async throws -> Data {
        guard Self.isWebURL(url) else { throw PodcastNetworkError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              data.count <= 20_000_000 else { throw PodcastNetworkError.invalidResponse }
        return data
    }

    static func isWebURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }

    private struct SearchResponse: Decodable { let results: [SearchItem] }
    private struct SearchItem: Decodable {
        let collectionId: Int?
        let collectionName: String?
        let artistName: String?
        let feedUrl: URL?
        let artworkUrl600: URL?
        let artworkUrl100: URL?
    }
}

// Created and consumed on the catalog actor, never on the UI thread.
final class PodcastFeedParser: NSObject, XMLParserDelegate {
    private let show: PodcastShow
    private var fields: [String: String] = [:]
    private var stack: [String] = []
    private var audio: URL?
    private var artwork: URL?
    private var inItem = false
    private var foundChannel = false
    private var showDescription = ""
    private var seen = Set<String>()
    private var episodes: [PodcastEpisode] = []

    private init(show: PodcastShow) { self.show = show }

    static func parse(_ data: Data, show: PodcastShow) throws -> [PodcastEpisode] {
        try parseFeed(data, show: show).episodes
    }

    static func parseFeed(_ data: Data, show: PodcastShow) throws -> PodcastFeed {
        let delegate = PodcastFeedParser(show: show)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.foundChannel else { throw PodcastNetworkError.invalidFeed }
        return PodcastFeed(description: plainText(delegate.showDescription), episodes:
            delegate.episodes.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) })
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        stack.append(name)
        if name == "channel" { foundChannel = true }
        if name == "item" { inItem = true; fields = [:]; audio = nil; artwork = nil }
        guard inItem else { return }
        if name == "enclosure", let value = attributes["url"],
           let url = URL(string: value, relativeTo: show.feedURL)?.absoluteURL,
           PodcastCatalog.isWebURL(url),
           attributes["type"]?.hasPrefix("audio/") != false || attributes["type"] == "application/octet-stream" {
            audio = url
        }
        if name == "itunes:image", let value = attributes["href"] { artwork = URL(string: value) }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !inItem, stack.last == "description", stack.dropLast().last == "channel" {
            showDescription += string
        }
        guard inItem, let field = stack.dropFirst(stack.firstIndex(of: "item")! + 1).first else { return }
        fields[field, default: ""] += string
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: string) }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { if !stack.isEmpty { stack.removeLast() } }
        guard name == "item" else { return }
        inItem = false
        guard let audio else { return }
        let guid = fields["guid"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = "\(show.id):\(guid?.isEmpty == false ? guid! : audio.absoluteString)"
        guard seen.insert(id).inserted else { return }
        let title = Self.plainText(fields["title"] ?? "")
        episodes.append(PodcastEpisode(id: id, show: show, title: title.isEmpty ? show.title : title,
            description: Self.plainText(fields["content:encoded"] ?? fields["description"] ?? fields["itunes:summary"] ?? ""),
            published: Self.date(fields["pubDate"]), duration: Self.duration(fields["itunes:duration"]),
            audioURL: audio, artworkURL: artwork ?? show.artworkURL))
    }

    static func duration(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard (1...3).contains(parts.count) else { return nil }
        var value = 0.0
        for part in parts {
            guard let number = Double(part), number.isFinite, number >= 0 else { return nil }
            value = value * 60 + number
        }
        return value > 0 ? value : nil
    }
    private static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz",
                       "EEE, d MMM yyyy HH:mm Z", "dd MMM yyyy HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return ISO8601DateFormatter().date(from: value)
    }
    private static func plainText(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, replacement) in [("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"),
                                      ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
