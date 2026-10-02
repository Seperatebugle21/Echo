import Foundation

struct SongMetadataUpdate {
    var id: UUID
    var fileName: String
    var genre: String?
    var year: Int?
    var readable: Bool
}

enum SongMetadataUpdates {
    /// Apply one batch to a local snapshot before publishing a single library change.
    static func apply(_ updates: [SongMetadataUpdate], to songs: inout [Song]) -> Bool {
        let indices = Dictionary(songs.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for update in updates {
            guard let index = indices[update.id], songs[index].fileName == update.fileName else { continue }
            if songs[index].genre == nil, let genre = update.genre {
                songs[index].genre = genre; changed = true
            }
            if songs[index].releaseYear == nil, let year = update.year {
                songs[index].releaseYear = year; changed = true
            }
            if update.readable, songs[index].tagsInspected != true {
                songs[index].tagsInspected = true; changed = true
            }
        }
        return changed
    }
}
