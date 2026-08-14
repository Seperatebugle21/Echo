import Foundation

@Observable
final class LyricsManager {
    
    static let shared = LyricsManager()
    
    private let lrclibGetURL = "https://lrclib.net/api/get"
    private let lrclibSearchURL = "https://lrclib.net/api/search"
    private let musixmatchURL = "https://api.musixmatch.com/ws/1.1/matcher.lyrics.get"
    
    // Tokens opgehaald uit UserDefaults
    private var geniusToken: String {
        UserDefaults.standard.string(forKey: "geniusAccessToken") ?? ""
    }
    
    private var musixmatchApiKey: String {
        UserDefaults.standard.string(forKey: "musixmatchApiKey") ?? ""
    }
    
    private init() {}
    
    struct LyricsResponse {
        var plainLyrics: String?
        var syncedLyrics: String?
    }
    
    // MARK: - Main Fetch Method
    
   func fetchLyrics(
    for song: Song,
    duration: Double
) async -> LyricsResponse? {
    
    // Hierin bewaren we de eerste 'gewone' lyrics die we tegenkomen als reserve
    var fallbackResponse: LyricsResponse?
    
    // Helper sluiting om een respons te verwerken
    func process(_ response: LyricsResponse?) -> LyricsResponse? {
        guard let response = response else { return nil }
        
        // 1. Hebben we gesynchroniseerde lyrics? Direct gebruiken!
        if response.syncedLyrics != nil {
            return response
        }
        
        // 2. Geen synced lyrics, maar wel plain lyrics? 
        // Bewaar deze als reserve als we nog geen reserve hadden.
        if fallbackResponse == nil && response.plainLyrics != nil {
            fallbackResponse = response
        }
        
        return nil
    }
    
    // --- STAP 1: LRCLIB Exact ---
    if let exact = await fetchLRCLIBExact(for: song, duration: duration),
       let match = process(exact) {
        print("Gesynchroniseerde lyrics via LRCLIB (Exact)")
        return match
    }
    
    // --- STAP 2: LRCLIB Search ---
    if let search = await fetchLRCLIBSearch(for: song),
       let match = process(search) {
        print("Gesynchroniseerde lyrics via LRCLIB (Search)")
        return match
    }
    
    // --- STAP 3: Musixmatch ---
    if !musixmatchApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if let musixmatch = await fetchMusixmatch(for: song),
           let match = process(musixmatch) {
            print("Gesynchroniseerde lyrics via Musixmatch")
            return match
        }
    }
    
    // --- STAP 4: Genius ---
    if !geniusToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if let genius = await fetchGenius(for: song),
           let match = process(genius) {
            print("Gesynchroniseerde lyrics via Genius")
            return match
        }
    }
    
    // --- FINALE CHECK ---
    // Nergens gesynchroniseerde lyrics gevonden? Gebruik de reserve (gewone lyrics)!
    if let fallback = fallbackResponse {
        print("Geen gesynchroniseerde lyrics gevonden. Gebruik gewone tekst-fallback.")
        return fallback
    }
    
    print("Geen lyrics gevonden bij alle bronnen")
    return nil
}

    
    // MARK: - LRCLIB Exact (/api/get)
    
    private func fetchLRCLIBExact(
        for song: Song,
        duration: Double
    ) async -> LyricsResponse? {
        
        var components = URLComponents(string: lrclibGetURL)
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: song.title),
            URLQueryItem(name: "artist_name", value: song.artist),
            URLQueryItem(name: "album_name", value: song.album),
            URLQueryItem(name: "duration", value: String(Int(duration)))
        ]
        
        guard let url = components?.url else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            let result = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
            guard result.plainLyrics != nil || result.syncedLyrics != nil else { return nil }
            
            return LyricsResponse(
                plainLyrics: result.plainLyrics,
                syncedLyrics: result.syncedLyrics
            )
        } catch {
            return nil
        }
    }
    
    // MARK: - LRCLIB Search (/api/search)
    
    private func fetchLRCLIBSearch(
        for song: Song
    ) async -> LyricsResponse? {
        
        var components = URLComponents(string: lrclibSearchURL)
        let searchQuery = "\(song.artist) \(song.title)"
        
        components?.queryItems = [
            URLQueryItem(name: "q", value: searchQuery)
        ]
        
        guard let url = components?.url else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            let searchResults = try JSONDecoder().decode([LRCLIBResponse].self, from: data)
            
            if let bestMatch = searchResults.first(where: { $0.plainLyrics != nil || $0.syncedLyrics != nil }) {
                return LyricsResponse(
                    plainLyrics: bestMatch.plainLyrics,
                    syncedLyrics: bestMatch.syncedLyrics
                )
            }
            
            return nil
        } catch {
            return nil
        }
    }
    
    // MARK: - Musixmatch API
    
    private func fetchMusixmatch(
        for song: Song
    ) async -> LyricsResponse? {
        
        var components = URLComponents(string: musixmatchURL)
        components?.queryItems = [
            URLQueryItem(name: "apikey", value: musixmatchApiKey),
            URLQueryItem(name: "q_track", value: song.title),
            URLQueryItem(name: "q_artist", value: song.artist)
        ]
        
        guard let url = components?.url else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            let result = try JSONDecoder().decode(MusixmatchResponse.self, from: data)
            
            // Check op HTTP status binnen Musixmatch JSON respons
            guard result.message.header.statusCode == 200,
                  let lyricsBody = result.message.body?.lyrics?.lyricsBody,
                  !lyricsBody.isEmpty else {
                return nil
            }
            
            return LyricsResponse(
                plainLyrics: lyricsBody,
                syncedLyrics: nil
            )
            
        } catch {
            print("Musixmatch fout:", error.localizedDescription)
            return nil
        }
    }
    
    // MARK: - Genius API
    
    private func fetchGenius(
        for song: Song
    ) async -> LyricsResponse? {
        
        guard let encoded = "\(song.artist) \(song.title)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else {
            return nil
        }
        
        guard let url = URL(string: "https://api.genius.com/search?q=\(encoded)") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(geniusToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            let response = try JSONDecoder().decode(
                GeniusSearchResponse.self,
                from: data
            )
            
            guard let hit = response.response.hits.first(where: { hit in
                let titleMatch = hit.result.title.lowercased().contains(song.title.lowercased())
                let artistMatch = hit.result.artist_names.lowercased().contains(song.artist.lowercased())
                return titleMatch && artistMatch
            }) else {
                return nil
            }
            
            print("Genius match gevonden:", hit.result.full_title)
            return nil
            
        } catch {
            print("Genius fout:", error.localizedDescription)
            return nil
        }
    }
}

// MARK: - LRCLIB Models

struct LRCLIBResponse: Codable {
    let plainLyrics: String?
    let syncedLyrics: String?
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
    let artist_names: String
}
