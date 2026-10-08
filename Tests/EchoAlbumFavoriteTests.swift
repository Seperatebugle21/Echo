import Foundation
import XCTest

@MainActor
final class EchoAlbumFavoriteTests: XCTestCase {
    private func local(_ name: String = "Album", artist: String = "Artist") -> AlbumGroup {
        AlbumGroup(name: name, artist: artist, songs: [Song(title: "One", artist: artist, fileName: "one.wav", album: name)])
    }
    func testFavoritesPersistAndRemoveWithoutChangingSongs() throws {
        let domain = "EchoAlbumFavoriteTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let album = FavoriteAlbum(album: local())
        let store = FavoriteAlbumsStore(defaults: defaults)
        store.toggle(album)
        XCTAssertTrue(FavoriteAlbumsStore(defaults: defaults).contains(album))
        store.toggle(album)
        XCTAssertTrue(FavoriteAlbumsStore(defaults: defaults).albums.isEmpty)
        XCTAssertEqual(local().songs.count, 1)
    }
    func testLocalAndOnlineAlbumShareFavoriteAcrossCaseAndAccents() {
        let localAlbum = FavoriteAlbum(album: local("Café", artist: " ARTIST "))
        let online = FavoriteAlbum(album: OnlineMusicAlbum(provider: .youtubeMusic, sourceID: "MPREalbum",
            title: "cafe", artistName: "artist", artists: []))
        XCTAssertEqual(localAlbum.id, online.id)
        XCTAssertNotEqual(localAlbum.id, FavoriteAlbum(album: local("Café", artist: "Other")).id)
        XCTAssertNotEqual(FavoriteAlbum(album: local("ab", artist: "c")).id,
            FavoriteAlbum(album: local("a", artist: "bc")).id)
    }
    func testDownloadedSongsResolveFromCurrentLibrary() {
        let reference = FavoriteAlbum(album: local())
        let first = Song(title: "One", artist: "Artist", fileName: "one.wav", album: "Album")
        let second = Song(title: "Two", artist: "Artist", fileName: "two.wav", album: "Album")
        XCTAssertEqual(reference.localAlbum(in: [first, second])?.songs.count, 2)
        XCTAssertNil(reference.localAlbum(in: []))
    }
    func testOnlineFavoriteKeepsProviderMetadataAfterReload() throws {
        let domain = "EchoAlbumFavoriteTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let online = OnlineMusicAlbum(provider: .spotify, sourceID: "album-id", title: "Album",
            artistName: "Artist", artists: [], artworkURL: URL(string: "https://example.com/cover.jpg"))
        FavoriteAlbumsStore(defaults: defaults).toggle(FavoriteAlbum(album: online))
        XCTAssertEqual(FavoriteAlbumsStore(defaults: defaults).albums.first?.onlineAlbum, online)
    }
}
