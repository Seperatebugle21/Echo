import Foundation

struct Playlist: Identifiable, Codable {
    
    let id: UUID
    var name: String
    var songIDs: [UUID]
    
    var imageData: Data?
    // Optional so existing manually managed playlists decode unchanged.
    var smartRules: SmartPlaylistConfiguration? = nil

    var isSmart: Bool { smartRules != nil }
    
}
