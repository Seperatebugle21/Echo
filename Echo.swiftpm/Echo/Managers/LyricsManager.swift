import Foundation

@Observable
final class LyricsManager {
    static let shared = LyricsManager()
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    private var geniusToken: String { UserDefaults.standard.string(forKey: "geniusAccessToken")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    private var musixmatchApiKey: String { UserDefaults.standard.string(forKey: "musixmatchApiKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    struct LyricsResponse {
        var plainLyrics: String?
        var syncedLyrics: String?
        var source: LyricsProvider
        var sourceURL: URL? = nil
    }

    func fetchLyrics(for song: Song, duration: Double, provider: LyricsProvider = .automatic) async -> LyricsResponse? {
        var fallback: LyricsResponse?
        func process(_ result: LyricsResponse?) -> LyricsResponse? {
            guard var result else { return nil }
            if result.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { result.plainLyrics = nil }
            if result.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { result.syncedLyrics = nil }
            if result.syncedLyrics != nil { return result }
            if fallback == nil && result.plainLyrics != nil { fallback = result }
            return nil
        }
        if provider == .automatic || provider == .musixmatch {
            if let result = process(await fetchMusixmatch(for: song, duration: duration)) { return result }
        }
        guard !Task.isCancelled else { return nil }
        if provider == .automatic || provider == .lrclib {
            if let result = process(await fetchLRCLIB(for: song, duration: duration, exact: true)) { return result }
            guard !Task.isCancelled else { return nil }
            if let result = process(await fetchLRCLIB(for: song, duration: duration, exact: false)) { return result }
        }
        guard !Task.isCancelled else { return nil }
        if provider == .automatic || provider == .genius {
            if let result = process(await fetchGenius(for: song, duration: duration)) { return result }
        }
        return Task.isCancelled ? nil : fallback
    }

    private func data(from url: URL, token: String? = nil) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if url.host == "genius.com" || url.host == "www.genius.com" {
            guard let finalURL = http.url, Self.isGeniusPage(finalURL) else { throw URLError(.badURL) }
        }
        return data
    }

    private func url(_ base: String, _ query: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = query
        return components?.url
    }

    private func fetchLRCLIB(for song: Song, duration: Double, exact: Bool) async -> LyricsResponse? {
        var query = [URLQueryItem(name: "track_name", value: song.title), URLQueryItem(name: "artist_name", value: song.artist)]
        if exact {
            if let album = song.album, !album.isEmpty { query.append(URLQueryItem(name: "album_name", value: album)) }
            if duration.isFinite && duration > 0 { query.append(URLQueryItem(name: "duration", value: String(duration))) }
        }
        guard let url = url("https://lrclib.net/api/" + (exact ? "get" : "search"), query) else { return nil }
        do {
            let data = try await data(from: url)
            let decoder = JSONDecoder()
            let results = exact ? [try decoder.decode(LRCLIBResponse.self, from: data)] : try decoder.decode([LRCLIBResponse].self, from: data)
            let ranked = results.compactMap { result -> (LRCLIBResponse, Double)? in
                guard let title = result.trackName, let artist = result.artistName,
                      let score = LyricsMatching.score(title: song.title, artist: song.artist, duration: duration,
                          candidateTitle: title, candidateArtist: artist, candidateDuration: result.duration),
                      Self.hasText(result.syncedLyrics) || Self.hasText(result.plainLyrics) else { return nil }
                let albumBonus = song.album.map { LyricsMatching.normalized($0) == LyricsMatching.normalized(result.albumName ?? "") ? 1.0 : 0.0 } ?? 0
                return (result, score + albumBonus)
            }.sorted {
                let leftSynced = Self.hasText($0.0.syncedLyrics), rightSynced = Self.hasText($1.0.syncedLyrics)
                if leftSynced != rightSynced { return leftSynced }
                return $0.1 > $1.1
            }
            guard let match = ranked.first?.0 else { return nil }
            return LyricsResponse(plainLyrics: match.plainLyrics, syncedLyrics: match.syncedLyrics, source: .lrclib)
        } catch { return nil }
    }

    private static func hasText(_ text: String?) -> Bool {
        !(text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    private func fetchMusixmatch(for song: Song, duration: Double) async -> LyricsResponse? {
        guard !musixmatchApiKey.isEmpty else { return nil }
        guard let matchURL = url("https://api.musixmatch.com/ws/1.1/matcher.track.get", [
            URLQueryItem(name: "apikey", value: musixmatchApiKey),
            URLQueryItem(name: "q_track", value: song.title), URLQueryItem(name: "q_artist", value: song.artist)
        ]) else { return nil }
        do {
            let match = try JSONDecoder().decode(MusixmatchTrackResponse.self, from: await data(from: matchURL))
            guard match.message.header.statusCode == 200, let track = match.message.body?.track,
                  LyricsMatching.score(title: song.title, artist: song.artist, duration: duration,
                      candidateTitle: track.track_name, candidateArtist: track.artist_name,
                      candidateDuration: track.track_length) != nil,
                  let lyricsURL = url("https://api.musixmatch.com/ws/1.1/track.lyrics.get", [
                    URLQueryItem(name: "apikey", value: musixmatchApiKey), URLQueryItem(name: "track_id", value: String(track.track_id))
                  ]) else { return nil }
            let response = try JSONDecoder().decode(MusixmatchResponse.self, from: await data(from: lyricsURL))
            guard response.message.header.statusCode == 200, let text = response.message.body?.lyrics?.lyricsBody, Self.hasText(text) else { return nil }
            let page = track.track_share_url.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            return LyricsResponse(plainLyrics: text, syncedLyrics: nil, source: .musixmatch, sourceURL: page)
        } catch { return nil }
    }

    static func isGeniusPage(_ url: URL) -> Bool {
        url.scheme == "https" && ["genius.com", "www.genius.com"].contains(url.host?.lowercased() ?? "")
    }

    private func fetchGenius(for song: Song, duration: Double) async -> LyricsResponse? {
        guard !geniusToken.isEmpty, let searchURL = url("https://api.genius.com/search", [
            URLQueryItem(name: "q", value: "\(song.artist) \(song.title)")
        ]) else { return nil }
        do {
            let search = try JSONDecoder().decode(GeniusSearchResponse.self, from: await data(from: searchURL, token: geniusToken))
            let matches = search.response.hits.compactMap { hit -> (GeniusSong, Double)? in
                guard let score = LyricsMatching.score(title: song.title, artist: song.artist, duration: duration,
                    candidateTitle: hit.result.title, candidateArtist: hit.result.artist_names, candidateDuration: nil) else { return nil }
                return (hit.result, score)
            }.sorted { $0.1 > $1.1 }
            for (match, _) in matches.prefix(3) {
                try Task.checkCancellation()
                guard let page = URL(string: match.url), Self.isGeniusPage(page) else { continue }
                // Public lyric pages receive no API credentials. No WebView or script execution.
                guard let pageData = try? await data(from: page), let html = String(data: pageData, encoding: .utf8),
                      let text = try GeniusLyricsParser.parse(html) else { continue }
                return LyricsResponse(plainLyrics: text, syncedLyrics: nil, source: .genius, sourceURL: page)
            }
            return nil
        } catch { return nil }
    }
}

struct LRCLIBResponse: Codable {
    let plainLyrics: String?
    let syncedLyrics: String?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
}

struct MusixmatchTrackResponse: Decodable {
    let message: Message
    struct Message: Decodable {
        let header: MusixmatchResponse.MusixmatchHeader
        let body: Body?
    }
    struct Body: Decodable { let track: Track? }
    struct Track: Decodable {
        let track_id: Int
        let track_name: String
        let artist_name: String
        let track_length: Double?
        let track_share_url: String?
    }
}

// MARK: - Musixmatch Models

struct MusixmatchResponse: Codable {
    let message: MusixmatchMessage
    
    struct MusixmatchMessage: Codable {
        let header: MusixmatchHeader
        let body: MusixmatchBody?
    }
    
    struct MusixmatchHeader: Codable {
        let statusCode: Int
        
        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
        }
    }
    
    struct MusixmatchBody: Codable {
        let lyrics: MusixmatchLyrics?
    }
    
    struct MusixmatchLyrics: Codable {
        let lyricsBody: String?
        
        enum CodingKeys: String, CodingKey {
            case lyricsBody = "lyrics_body"
        }
    }
}

// MARK: - Genius Models

struct GeniusSearchResponse: Codable {
    let response: GeniusResponse
}

struct GeniusResponse: Codable {
    let hits: [GeniusHit]
}

struct GeniusHit: Codable {
    let result: GeniusSong
}

struct GeniusSong: Codable {
    let title: String
    let full_title: String
    let url: String
    let artist_names: String
}
