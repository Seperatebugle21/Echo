import Foundation
import Observation

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
            return String(localized: "fetch_status_queued")

        case .preparing:
            return String(localized: "fetch_status_preparing")

        case .downloading:
            return String(localized: "fetch_status_downloading")

        case .processing:
            return String(localized: "fetch_status_encoding")

        case .completed:
            return String(localized: "fetch_status_completed")

        case .failed(let message):
            return message
        }
    }
}


enum FetchQueueState: Equatable { case pending, completed, failed }

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

    var destinationPlaylistPositions:
        [UUID: Int]

    private(set) var queueState: FetchQueueState = .pending
    @ObservationIgnored private var retryBudget = FetchRetryBudget()
    var automaticRetryCount: Int { retryBudget.used }
    func consumeAutomaticRetry(after error: Error? = nil) -> Bool { retryBudget.consume(after: error) }

    var status: FetchStatus = .queued {
        didSet {
            let next: FetchQueueState
            switch status { case .completed: next = .completed; case .failed: next = .failed; default: next = .pending }
            if queueState != next { queueState = next }
        }
    }


    init(
        spotifyURL: URL,
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        youtubeURL: URL? = nil,
        permissionConfirmed: Bool = false,
        destinationPlaylistPositions: [UUID: Int] = [:],
        automaticRetryCount: Int = 0
    ) {

        self.retryBudget = FetchRetryBudget(used: automaticRetryCount)

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

        self.destinationPlaylistPositions =
            destinationPlaylistPositions
    }
}
