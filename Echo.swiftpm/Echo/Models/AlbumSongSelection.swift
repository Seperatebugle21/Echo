import Foundation

enum AlbumSongSelection {
    static func filtered(_ songs: [Song], query: String) -> [Song] {
        guard !query.isEmpty else { return songs }
        return songs.filter {
            $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query)
                || ($0.album ?? "").localizedStandardContains(query)
        }
    }
    static func queue(_ songs: [Song], shuffled: Bool) -> [Song] {
        shuffled ? songs.shuffled() : songs
    }
}
