import Foundation

struct YouTubeSearchResult: Identifiable, Hashable {
    let id: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?
    let videoURL: URL
}
