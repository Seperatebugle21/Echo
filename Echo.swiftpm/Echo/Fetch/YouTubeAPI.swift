import Foundation

@MainActor
final class YouTubeAPI {

    static let shared = YouTubeAPI()

    private init() {}

    // Zet hier je YouTube Data API v3 key.
    private let apiKey = "AIzaSyC4N7M9pA9Um3PZzH6a2l_cMq_1JhQDP44"

    func search(
        title: String,
        artist: String,
        maxResults: Int = 10
    ) async throws -> [YouTubeSearchResult] {

        let query = "\(title) \(artist) audio"

        var components = URLComponents(
            string: "https://www.googleapis.com/youtube/v3/search"
        )!

        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: "\(maxResults)"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components.url else {
            throw YouTubeAPIError.invalidURL
        }

        let (data, response) =
            try await URLSession.shared.data(from: url)

        guard
            let http = response as? HTTPURLResponse,
            200..<300 ~= http.statusCode
        else {
            throw YouTubeAPIError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(
            YouTubeSearchResponse.self,
            from: data
        )

        return decoded.items.compactMap { item in

            guard
                let videoID = item.id.videoId,
                let videoURL = URL(
                    string: "https://www.youtube.com/watch?v=\(videoID)"
                )
            else {
                return nil
            }

            let thumbnail =
                item.snippet.thumbnails.high?.url ??
                item.snippet.thumbnails.medium?.url ??
                item.snippet.thumbnails.defaultImage?.url

            return YouTubeSearchResult(
                id: videoID,
                title: item.snippet.title,
                channelTitle: item.snippet.channelTitle,
                thumbnailURL: thumbnail,
                videoURL: videoURL
            )
        }
    }
}


// MARK: - API JSON

private struct YouTubeSearchResponse: Decodable {
    let items: [YouTubeSearchItem]
}

private struct YouTubeSearchItem: Decodable {
    let id: YouTubeSearchItemID
    let snippet: YouTubeSnippet
}

private struct YouTubeSearchItemID: Decodable {
    let videoId: String?
}

private struct YouTubeSnippet: Decodable {
    let title: String
    let channelTitle: String
    let thumbnails: YouTubeThumbnails
}

private struct YouTubeThumbnails: Decodable {
    let defaultImage: YouTubeThumbnail?
    let medium: YouTubeThumbnail?
    let high: YouTubeThumbnail?

    enum CodingKeys: String, CodingKey {
        case defaultImage = "default"
        case medium
        case high
    }
}

private struct YouTubeThumbnail: Decodable {
    let url: URL
}

enum YouTubeAPIError: LocalizedError {
    case invalidURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ongeldige YouTube URL."
        case .invalidResponse:
            return "YouTube kon niet worden geladen."
        }
    }
}
