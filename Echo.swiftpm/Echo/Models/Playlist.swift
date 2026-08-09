import Foundation

struct Playlist: Identifiable, Codable {
    
    let id: UUID
    var name: String
    var songIDs: [UUID]
    
    var imageData: Data?
    
}
