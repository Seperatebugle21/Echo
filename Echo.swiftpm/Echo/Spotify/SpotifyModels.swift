import Foundation

struct SpotifyTrack: Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let durationMS: Int
    let artworkURL: URL?
    let spotifyURL: URL
}

struct SpotifyPlaylist: Identifiable, Hashable {
    let id: String
    let name: String
    let artworkURL: URL?
    let spotifyURL: URL
    let trackCount: Int
}

struct SpotifyAlbum: Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String
    let artworkURL: URL?
    let spotifyURL: URL
    let trackCount: Int
}
