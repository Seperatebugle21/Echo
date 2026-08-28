import Foundation

enum FetchStatus: Equatable {

    case queued

    // Dit zijn OVERALL progresswaarden 0...1
    case preparing(Double)
    case downloading(Double)
    case processing(Double)

    case completed
    case failed(String)


    var progress: Double? {

        switch self {

        case .preparing(let value),
             .downloading(let value),
             .processing(let value):

            return min(
                max(value, 0),
                1
            )

        default:
            return nil
        }
    }


    var title: String {

        switch self {

        case .queued:
            return "Queued"

        case .preparing:
            return "Preparing"

        case .downloading:
            return "Downloading"

        case .processing:
            return "Encoding MP3"

        case .completed:
            return "Completed"

        case .failed(let message):
            return message
        }
    }
}


@Observable
final class FetchItem: Identifiable {

    let id =
        UUID()

    let spotifyURL:
        URL

    var title:
        String

    var artist:
        String

    var album:
        String?

    var youtubeURL:
        URL?

    var permissionConfirmed =
        false

    var artworkURL:
        URL?

    var status:
        FetchStatus =
            .queued


    init(
        spotifyURL: URL,
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        youtubeURL: URL? = nil,
        permissionConfirmed: Bool = false
    ) {

        self.spotifyURL =
            spotifyURL

        self.title =
            title

        self.artist =
            artist

        self.album =
            album

        self.artworkURL =
            artworkURL

        self.youtubeURL =
            youtubeURL

        self.permissionConfirmed =
            permissionConfirmed
    }
}
