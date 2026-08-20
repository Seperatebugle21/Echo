import Foundation

enum FetchStatus: Equatable {
    case queued
    case preparing
    case downloading(Double)
    case processing
    case completed
    case failed(String)

    var title: String {
        switch self {
        case .queued:
            return "Queued"

        case .preparing:
            return "Preparing"

        case .downloading(let progress):
            return "\(Int(progress * 100))%"

        case .processing:
            return "Processing"

        case .completed:
            return "Completed"

        case .failed(let message):
            return message
        }
    }
}

@Observable
final class FetchItem: Identifiable {

    let id = UUID()

    let spotifyURL: URL

    var title: String
    var artist: String
    var album: String?

    var youtubeURL: URL?
 
    var permissionConfirmed = false
 
    var artworkURL: URL?

    var status: FetchStatus = .queued

    init(
        spotifyURL: URL,
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil
    ) {
        self.spotifyURL = spotifyURL
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
    }
}
