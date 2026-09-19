import Foundation

enum PodcastNetworkError: Error { case invalidResponse, invalidFeed }

actor PodcastCatalog {
    static let shared = PodcastCatalog()
    private var searches: [String: (Date, [PodcastShow])] = [:]
    private var episodeSearches: [String: (Date, [PodcastEpisode])] = [:]
    private var transcriptCache: [URL: String] = [:]
    private var nextSearch = Date.distantPast

    func search(_ term: String, country: String) async throws -> [PodcastShow] {
        let key = country + ":" + term.lowercased()
        if let cached = searches[key], Date().timeIntervalSince(cached.0) < 300 { return cached.1 }
        try await reserveSearchSlot()
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

    private func reserveSearchSlot() async throws {
        while true {
            try Task.checkCancellation()
            let delay = nextSearch.timeIntervalSinceNow
            if delay <= 0 {
                nextSearch = Date().addingTimeInterval(3)
                return
            }
            // Recheck after actor reentry; cancelled queries never reserve future slots.
            try await Task.sleep(for: .seconds(delay))
        }
    }

    func searchEpisodes(_ term: String, country: String) async throws -> [PodcastEpisode] {
        let key = country + ":" + term.lowercased()
        if let cached = episodeSearches[key], Date().timeIntervalSince(cached.0) < 300 { return cached.1 }
        try await reserveSearchSlot()
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "podcast"), URLQueryItem(name: "entity", value: "podcastEpisode"),
            URLQueryItem(name: "country", value: country), URLQueryItem(name: "limit", value: "50")]
        let data = try await fetch(components.url!)
        let episodes = try Self.decodeEpisodes(from: data)
        try Task.checkCancellation()
        if episodeSearches.count > 50 { episodeSearches.removeAll() }
        episodeSearches[key] = (Date(), episodes)
        return episodes
    }

    static func decodeEpisodes(from data: Data) throws -> [PodcastEpisode] {
        let response = try JSONDecoder().decode(EpisodeSearchResponse.self, from: data)
        var seen = Set<String>()
        return response.results.compactMap { item in
            guard let showID = item.collectionId, let showTitle = item.collectionName,
                  let title = item.trackName, let feed = item.feedUrl, isWebURL(feed),
                  let audio = item.episodeUrl, isWebURL(audio),
                  item.episodeContentType == nil || item.episodeContentType == "audio" else { return nil }
            let id = PodcastEpisode.identifier(showID: showID, guid: item.episodeGuid, audioURL: audio)
            guard seen.insert(id).inserted else { return nil }
            let show = PodcastShow(id: showID, title: showTitle, author: item.artistName ?? showTitle,
                                   artworkURL: item.artworkUrl600, feedURL: feed)
            return PodcastEpisode(id: id, show: show, title: title,
                description: PodcastFeedParser.plainText(item.description ?? ""),
                published: item.releaseDate.flatMap { ISO8601DateFormatter().date(from: $0) },
                duration: item.trackTimeMillis.flatMap { $0 > 0 ? $0 / 1000 : nil },
                audioURL: audio, artworkURL: item.artworkUrl600)
        }
    }

    func transcript(for episode: PodcastEpisode) async throws -> String? {
        var references = episode.transcripts ?? []
        if references.isEmpty {
            let refreshed = try await feed(for: episode.show)
            references = refreshed.episodes.first {
                $0.id == episode.id || $0.audioURL == episode.audioURL
            }?.transcripts ?? []
        }
        let supported = references.filter { PodcastTranscriptParser.supports($0.type) }
        guard !supported.isEmpty else { return nil }
        for reference in supported {
            if let cached = transcriptCache[reference.url] { return cached }
            do {
                let data = try await fetch(reference.url)
                try Task.checkCancellation()
                let text = try PodcastTranscriptParser.parse(data, type: reference.type)
                if transcriptCache.count >= 20 { transcriptCache.removeAll() }
                transcriptCache[reference.url] = text
                return text
            } catch {
                try Task.checkCancellation()
                // Try another transcript format supplied by the same publisher.
            }
        }
        throw PodcastNetworkError.invalidResponse
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
    private struct EpisodeSearchResponse: Decodable { let results: [EpisodeSearchItem] }
    private struct EpisodeSearchItem: Decodable {
        let collectionId: Int?
        let collectionName: String?
        let artistName: String?
        let trackName: String?
        let feedUrl: URL?
        let episodeUrl: URL?
        let episodeGuid: String?
        let episodeContentType: String?
        let artworkUrl600: URL?
        let description: String?
        let releaseDate: String?
        let trackTimeMillis: Double?
    }
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
    private var transcripts: [PodcastTranscriptReference] = []
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
        if name == "item" { inItem = true; fields = [:]; audio = nil; artwork = nil; transcripts = [] }
        guard inItem else { return }
        if name == "enclosure", let value = attributes["url"],
           let url = URL(string: value, relativeTo: show.feedURL)?.absoluteURL,
           PodcastCatalog.isWebURL(url),
           attributes["type"]?.hasPrefix("audio/") != false || attributes["type"] == "application/octet-stream" {
            audio = url
        }
        if name == "itunes:image", let value = attributes["href"] { artwork = URL(string: value) }
        if name == "podcast:transcript", let value = attributes["url"], let type = attributes["type"],
           let url = URL(string: value, relativeTo: show.feedURL)?.absoluteURL, PodcastCatalog.isWebURL(url) {
            transcripts.append(PodcastTranscriptReference(url: url, type: type, language: attributes["language"]))
        }
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
        let id = PodcastEpisode.identifier(showID: show.id, guid: guid, audioURL: audio)
        guard seen.insert(id).inserted else { return }
        let title = Self.plainText(fields["title"] ?? "")
        episodes.append(PodcastEpisode(id: id, show: show, title: title.isEmpty ? show.title : title,
            description: Self.plainText(fields["content:encoded"] ?? fields["description"] ?? fields["itunes:summary"] ?? ""),
            published: Self.date(fields["pubDate"]), duration: Self.duration(fields["itunes:duration"]),
            audioURL: audio, artworkURL: artwork ?? show.artworkURL, transcripts: transcripts.isEmpty ? nil : transcripts))
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
    static func plainText(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, replacement) in [("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"),
                                      ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
