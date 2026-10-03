import Foundation

struct Playlist: Identifiable, Codable {
    
    let id: UUID
    var name: String
    var songIDs: [UUID]
    
    var imageData: Data?
    var smartDefinition: SmartPlaylistDefinition? = nil
    var builtinCoverID: String? = nil
    var automaticNameKey: String? = nil

    func displayName(language: String? = nil) -> String {
        guard let automaticNameKey else { return name }
        return EchoLocalization.string(automaticNameKey, language: language, fallback: name)
    }
    
}
