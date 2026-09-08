import SwiftUI
import Foundation

struct Song: Identifiable, Codable, Hashable {
    
    let id: UUID
    var title: String
    var artist: String
    var fileName: String
    
    var album: String?
    var coverData: Data?
    var imageData: Data?
    
    var dateAdded: Date
    var lastPlayed: Date?
    
    var lyrics: String?
    var syncedLyrics: String?
    
    
    init(
        id: UUID = UUID(),
        title: String,
        artist: String = "Onbekende artiest",
        fileName: String,
        album: String? = nil,
        coverData: Data? = nil,
        imageData: Data? = nil,
        dateAdded: Date = Date(),
        lastPlayed: Date? = nil,
        lyrics: String? = nil,
        syncedLyrics: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.fileName = fileName
        self.album = album
        self.coverData = coverData
        self.imageData = imageData
        self.dateAdded = dateAdded
        self.lastPlayed = lastPlayed
        self.lyrics = lyrics
        self.syncedLyrics = syncedLyrics
    }
}
