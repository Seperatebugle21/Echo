import Foundation
import Observation

struct FavoriteAlbum: Codable, Identifiable, Equatable {
    var title: String
    var artist: String
    var onlineAlbum: OnlineMusicAlbum?
    var id: String {
        Self.identity(title: title, artist: artist)
    }
    static func identity(title: String, artist: String) -> String {
        let name = OnlineCatalogLogic.normalizedName(title)
        let credit = OnlineCatalogLogic.normalizedName(artist)
        return "\(name.utf8.count):\(name)\(credit)"
    }
    init(album: AlbumGroup) { title = album.name; artist = album.artist }
    init(album: OnlineMusicAlbum) { title = album.title; artist = album.artistName; onlineAlbum = album }
    func localAlbum(in songs: [Song]) -> AlbumGroup? {
        LibraryAlbums.groups(from: songs).first { Self.identity(title: $0.name, artist: $0.artist) == id }
    }
}

@MainActor
@Observable
final class FavoriteAlbumsStore {
    static let shared = FavoriteAlbumsStore()
    private(set) var albums: [FavoriteAlbum]
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "echo.favorite.albums.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([FavoriteAlbum].self, from: $0) } ?? []
        var seen: Set<String> = []
        albums = saved.filter { seen.insert($0.id).inserted }
    }
    func contains(_ album: FavoriteAlbum) -> Bool { albums.contains { $0.id == album.id } }
    func toggle(_ album: FavoriteAlbum) {
        if contains(album) { albums.removeAll { $0.id == album.id } }
        else { albums.append(album) }
        defaults.set(try? JSONEncoder().encode(albums), forKey: Self.key)
    }
}
