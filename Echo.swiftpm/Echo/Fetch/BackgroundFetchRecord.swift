import Foundation

// MARK: - Persistent Background Record

struct BackgroundFetchRecord:
    Codable,
    Identifiable,
    Sendable {

    let id: UUID

    let spotifyURL: String

    let title: String
    let artist: String
    let album: String?

    let artworkURL: String?
    let youtubeURL: String?

    let permissionConfirmed: Bool

    let destinationPlaylistPositions: [UUID: Int]?

    var destinationAlbums: [LibraryAlbumDestination]? = nil

    var automaticRetryCount: Int? = nil

    let suggestedFileName: String?

    var localFilePath: String?

    var completed: Bool

    var errorMessage: String?

    mutating func mergeAlbumDestinations(_ albums: [LibraryAlbumDestination]) {
        destinationAlbums = LibraryAlbumDestination.unique((destinationAlbums ?? []) + albums)
    }
}


