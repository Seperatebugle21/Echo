import Foundation

// MARK: - Models used by Echo

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


// MARK: - Spotify API responses

struct SpotifySavedTracksResponse: Decodable {
    let items: [SpotifySavedTrackItem]
    let next: String?
}

struct SpotifySavedTrackItem: Decodable {
    let track: SpotifyAPITrack
}

struct SpotifyAPITrack: Decodable {
    let id: String
    let name: String
    let durationMS: Int
    let artists: [SpotifyAPIArtist]
    let album: SpotifyAPIAlbum
    let externalURLs: SpotifyExternalURLs

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case durationMS = "duration_ms"
        case artists
        case album
        case externalURLs = "external_urls"
    }
}

struct SpotifyAPIArtist: Decodable {
    let id: String?
    let name: String
}

struct SpotifyAPIAlbum: Decodable {
    let id: String
    let name: String
    let images: [SpotifyAPIImage]
}

struct SpotifyAPIImage: Decodable {
    let url: URL
    let width: Int?
    let height: Int?
}

struct SpotifyExternalURLs: Decodable {
    let spotify: URL
}


// MARK: - Playlists API

struct SpotifyPlaylistsResponse: Decodable {
    let items: [SpotifyAPIPlaylist]
    let next: String?
}

struct SpotifyAPIPlaylist: Decodable {
    let id: String
    let name: String
    let images: [SpotifyAPIImage]
    let externalURLs: SpotifyExternalURLs

    // Spotify renamed `tracks` -> `items` in 2026
    let items: SpotifyPlaylistItemsInfo?

    // Fallback for older responses
    let tracks: SpotifyPlaylistItemsInfo?

    var trackCount: Int {
        items?.total ?? tracks?.total ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case images
        case externalURLs = "external_urls"
        case items
        case tracks
    }
}

struct SpotifyPlaylistItemsInfo: Decodable {
    let total: Int
}

struct SpotifyPlaylistItemsResponse: Decodable {
    let items: [SpotifyPlaylistItem]
    let next: String?
}

struct SpotifyPlaylistItem: Decodable {
    let track: SpotifyAPITrack?
}
