import Foundation

struct AlbumGroup: Identifiable {
    var id: String { "\(artist)-\(name)" }
    let name: String
    let artist: String
    let songs: [Song]
}

enum LibraryAlbums {
    static func groups(from songs: [Song]) -> [AlbumGroup] {
        let eligible = songs.filter { $0.podcastEpisodeID == nil && !($0.album ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return Dictionary(grouping: eligible) { "\($0.artist)|\($0.album ?? "")" }
            .compactMap { _, tracks in
                guard let first = tracks.first, let album = first.album else { return nil }
                return AlbumGroup(name: album, artist: first.artist, songs: tracks)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
