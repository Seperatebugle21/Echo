import Foundation

final class LyricsCache {
    
    static let shared = LyricsCache()
    
    private let key = "EchoLyricsCache"
    
    private var cache: [UUID: LyricsData] = [:]
    
    
    struct LyricsData: Codable {
        var plainLyrics: String?
        var syncedLyrics: String?
    }
    
    
    private init() {
        load()
    }
    
    
    func save(
        songID: UUID,
        plainLyrics: String?,
        syncedLyrics: String?
    ) {
        
        cache[songID] = LyricsData(
            plainLyrics: plainLyrics,
            syncedLyrics: syncedLyrics
        )
        
        saveToDisk()
    }
    
    
    func get(
        songID: UUID
    ) -> LyricsData? {
        
        cache[songID]
    }
    
    
    private func saveToDisk() {
        
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(
                data,
                forKey: key
            )
        }
    }
    
    
    private func load() {
        
        guard let data = UserDefaults.standard.data(
            forKey: key
        )
        else { return }
        
        
        if let saved = try? JSONDecoder().decode(
            [UUID: LyricsData].self,
            from: data
        ) {
            cache = saved
        }
    }
}
