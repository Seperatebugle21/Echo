import Foundation

@Observable
final class LyricsManager {
    
    static let shared = LyricsManager()
    
    private let lrclibURL = "https://lrclib.net/api/get"
    
    private var geniusToken: String {
        UserDefaults.standard.string(forKey: "geniusAccessToken") ?? ""
    }
    
    private init() {}
    
    
    struct LyricsResponse {
        var plainLyrics: String?
        var syncedLyrics: String?
    }
    
    
    // MARK: - Main
    
    func fetchLyrics(
        for song: Song,
        duration: Double
    ) async -> LyricsResponse? {
        
        
        // Eerst LRCLIB
        if let lyrics = await fetchLRCLIB(
            for: song,
            duration: duration
        ) {
            
            print("Lyrics via LRCLIB")
            return lyrics
        }


        // Check of er wel een Genius token is ingevuld
        guard !geniusToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Geen Genius token ingesteld")
            return nil
        }
        
        
        // Daarna Genius
        if let lyrics = await fetchGenius(
            for: song
        ) {
            
            print("Lyrics via Genius")
            return lyrics
        }
        
        
        print("Geen lyrics gevonden")
        return nil
    }
    
    
    
    
    // MARK: - LRCLIB
    
    private func fetchLRCLIB(
        for song: Song,
        duration: Double
    ) async -> LyricsResponse? {
        
        
        var components = URLComponents(
            string: lrclibURL
        )
        
        components?.queryItems = [
            URLQueryItem(
                name: "track_name",
                value: song.title
            ),
            URLQueryItem(
                name: "artist_name",
                value: song.artist
            ),
            URLQueryItem(
                name: "album_name",
                value: song.album
            ),
            URLQueryItem(
                name: "duration",
                value: String(duration)
            )
        ]
        
        
        guard let url = components?.url else {
            return nil
        }
        
        
        do {
            
            let (data, _) = try await URLSession.shared.data(
                from: url
            )
            
            
            let result = try JSONDecoder().decode(
                LRCLIBResponse.self,
                from: data
            )
            
            
            return LyricsResponse(
                plainLyrics: result.plainLyrics,
                syncedLyrics: result.syncedLyrics
            )
            
            
        } catch {
            
            return nil
        }
    }
    
    
    
    struct LRCLIBResponse: Codable {
        let plainLyrics: String?
        let syncedLyrics: String?
    }
    
    
    
    
    // MARK: - Genius
    
    private func fetchGenius(
        for song: Song
    ) async -> LyricsResponse? {
        
        
        guard let encoded =
                "\(song.artist) \(song.title)"
            .addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            )
        else {
            return nil
        }
        
        
        guard let url = URL(
            string:
                "https://api.genius.com/search?q=\(encoded)"
        )
        else {
            return nil
        }
        
        
        var request = URLRequest(
            url: url
        )
        
        
        request.setValue(
            "Bearer \(geniusToken)",
            forHTTPHeaderField: "Authorization"
        )
        
        
        do {
            
            let (data, _) = try await URLSession.shared.data(
                for: request
            )
            
            
            let response =
            try JSONDecoder().decode(
                GeniusSearchResponse.self,
                from: data
            )
            
            
            guard let hit = response.response.hits.first(
                where: { hit in
                    
                    let titleMatch =
                    hit.result.title
                        .lowercased()
                        .contains(
                            song.title.lowercased()
                        )
                    
                    let artistMatch =
                    hit.result.artist_names
                        .lowercased()
                        .contains(
                            song.artist.lowercased()
                        )
                    
                    return titleMatch && artistMatch
                }
            )
            else {
                return nil
            }
            
            
            print(
                "Genius match:",
                hit.result.full_title
            )
            
            
            // Genius API geeft geen lyrics tekst terug.
            // Daarvoor moet je nog scraping of een andere lyrics API gebruiken.
            return nil
            
            
        } catch {
            
            print(
                "Genius fout:",
                error.localizedDescription
            )
            
            return nil
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
