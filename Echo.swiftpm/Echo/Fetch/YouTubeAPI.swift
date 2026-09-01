import Foundation


@MainActor
final class YouTubeAPI {

    static let shared =
        YouTubeAPI()


    private init() {}


    // MARK: - API Key

    private let apiKey =
        "AIzaSyC4N7M9pA9Um3PZzH6a2l_cMq_1JhQDP44"


    // MARK: - Search Track

    func search(
        title: String,
        artist: String,
        maxResults: Int = 10
    ) async throws
        -> [YouTubeSearchResult] {

        let query =
            "\(title) \(artist) audio"


        return try await
            performSearch(
                query:
                    query,
                maxResults:
                    maxResults,
                musicOnly:
                    false
            )
    }


    // MARK: - Search Music

    func searchMusic(
        query: String,
        maxResults: Int = 25
    ) async throws
        -> [YouTubeSearchResult] {

        let cleaned =
            query
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        guard !cleaned.isEmpty else {

            return []
        }


        return try await
            performSearch(
                query:
                    "\(cleaned) audio",
                maxResults:
                    maxResults,
                musicOnly:
                    true
            )
    }


    // MARK: - Perform Search

    private func performSearch(
        query: String,
        maxResults: Int,
        musicOnly: Bool
    ) async throws
        -> [YouTubeSearchResult] {

        var components =
            URLComponents(
                string:
                    "https://www.googleapis.com/youtube/v3/search"
            )!


        var queryItems:
            [URLQueryItem] =
            [

                URLQueryItem(
                    name:
                        "part",
                    value:
                        "snippet"
                ),

                URLQueryItem(
                    name:
                        "type",
                    value:
                        "video"
                ),

                URLQueryItem(
                    name:
                        "maxResults",
                    value:
                        "\(maxResults)"
                ),

                URLQueryItem(
                    name:
                        "q",
                    value:
                        query
                ),

                URLQueryItem(
                    name:
                        "key",
                    value:
                        apiKey
                )
            ]


        if musicOnly {

            queryItems.append(
                URLQueryItem(
                    name:
                        "videoCategoryId",
                    value:
                        "10"
                )
            )
        }


        components.queryItems =
            queryItems


        guard let url =
            components.url
        else {

            throw YouTubeAPIError
                .invalidURL
        }


        let (
            data,
            response
        ) =
            try await
            URLSession.shared
                .data(
                    from:
                        url
                )


        guard let http =
            response
                as?
                HTTPURLResponse
        else {

            throw YouTubeAPIError
                .invalidResponse
        }


        // MARK: - HTTP Errors

        guard 200..<300 ~=
            http.statusCode
        else {

            throw parseAPIError(
                statusCode:
                    http.statusCode,
                data:
                    data
            )
        }


        // MARK: - Decode

        do {

            let decoded =
                try JSONDecoder()
                    .decode(
                        YouTubeSearchResponse.self,
                        from:
                            data
                    )


            return decoded.items
                .compactMap {
                    item in


                    guard
                        let videoID =
                            item.id.videoId,

                        let videoURL =
                            URL(
                                string:
                                    "https://www.youtube.com/watch?v=\(videoID)"
                            )

                    else {

                        return nil
                    }


                    let thumbnail =
                        item.snippet
                            .thumbnails
                            .high?
                            .url
                        ??
                        item.snippet
                            .thumbnails
                            .medium?
                            .url
                        ??
                        item.snippet
                            .thumbnails
                            .defaultImage?
                            .url


                    return YouTubeSearchResult(

                        id:
                            videoID,

                        title:
                            item.snippet.title,

                        channelTitle:
                            item.snippet.channelTitle,

                        thumbnailURL:
                            thumbnail,

                        videoURL:
                            videoURL
                    )
                }


        } catch {

            print(
                "YouTube decode error:",
                error
            )


            throw YouTubeAPIError
                .decodeFailed
        }
    }


    // MARK: - Parse API Error

    private func parseAPIError(
        statusCode: Int,
        data: Data
    ) -> YouTubeAPIError {

        let decoded =
            try? JSONDecoder()
                .decode(
                    YouTubeErrorResponse.self,
                    from:
                        data
                )


        let reason =
            decoded?
                .error
                .errors?
                .first?
                .reason


        let message =
            decoded?
                .error
                .message


        print(
            "YouTube API error:",
            statusCode,
            reason ?? "unknown",
            message ?? "No message"
        )


        // MARK: 400

        if statusCode ==
            400 {

            return .badRequest(
                message
            )
        }


        // MARK: 401

        if statusCode ==
            401 {

            return .unauthorized
        }


        // MARK: 403

        if statusCode ==
            403 {

            switch reason {

            case "quotaExceeded",
                 "dailyLimitExceeded",
                 "dailyLimitExceededUnreg",
                 "rateLimitExceeded":

                return .quotaExceeded


            case "keyInvalid":

                return .invalidAPIKey


            case "accessNotConfigured":

                return .apiNotEnabled


            case "forbidden":

                return .forbidden


            default:

                return .forbiddenMessage(
                    message
                )
            }
        }


        // MARK: 429

        if statusCode ==
            429 {

            return .rateLimited
        }


        // MARK: Server Error

        if statusCode >=
            500 {

            return .serverError(
                statusCode
            )
        }


        return .httpError(
            statusCode,
            message
        )
    }
}


// MARK: - Search JSON

private struct YouTubeSearchResponse:
    Decodable {

    let items:
        [YouTubeSearchItem]
}


private struct YouTubeSearchItem:
    Decodable {

    let id:
        YouTubeSearchItemID

    let snippet:
        YouTubeSnippet
}


private struct YouTubeSearchItemID:
    Decodable {

    let videoId:
        String?
}


private struct YouTubeSnippet:
    Decodable {

    let title:
        String

    let channelTitle:
        String

    let thumbnails:
        YouTubeThumbnails
}


private struct YouTubeThumbnails:
    Decodable {

    let defaultImage:
        YouTubeThumbnail?

    let medium:
        YouTubeThumbnail?

    let high:
        YouTubeThumbnail?


    enum CodingKeys:
        String,
        CodingKey {

        case defaultImage =
            "default"

        case medium
        case high
    }
}


private struct YouTubeThumbnail:
    Decodable {

    let url:
        URL
}


// MARK: - Error JSON

private struct YouTubeErrorResponse:
    Decodable {

    let error:
        YouTubeErrorBody
}


private struct YouTubeErrorBody:
    Decodable {

    let code:
        Int?

    let message:
        String?

    let errors:
        [YouTubeErrorDetail]?
}


private struct YouTubeErrorDetail:
    Decodable {

    let message:
        String?

    let domain:
        String?

    let reason:
        String?
}


// MARK: - API Errors

enum YouTubeAPIError:
    LocalizedError {

    case invalidURL

    case invalidResponse

    case badRequest(
        String?
    )

    case unauthorized

    case forbidden

    case forbiddenMessage(
        String?
    )

    case quotaExceeded

    case rateLimited

    case invalidAPIKey

    case apiNotEnabled

    case decodeFailed

    case serverError(
        Int
    )

    case httpError(
        Int,
        String?
    )


    var errorDescription:
        String? {

        switch self {

        case .invalidURL:

            return
                "Ongeldige YouTube URL."


        case .invalidResponse:

            return
                "YouTube gaf geen geldige response."


        case .badRequest(
            let message
        ):

            return
                message
                ??
                "YouTube heeft de zoekopdracht geweigerd."


        case .unauthorized:

            return
                "De YouTube API kon niet worden geauthenticeerd."


        case .forbidden:

            return
                "YouTube heeft deze aanvraag geweigerd."


        case .forbiddenMessage(
            let message
        ):

            if let message,
               !message.isEmpty {

                return
                    "YouTube heeft de aanvraag geweigerd: \(message)"
            }


            return
                "YouTube heeft deze aanvraag geweigerd."


        case .quotaExceeded:

            return
                "De YouTube API-limiet is bereikt."


        case .rateLimited:

            return
                "Er zijn te veel YouTube-aanvragen kort na elkaar. Probeer later opnieuw."


        case .invalidAPIKey:

            return
                "De YouTube API-key is ongeldig."


        case .apiNotEnabled:

            return
                "YouTube Data API is niet ingeschakeld voor deze API-key."


        case .decodeFailed:

            return
                "Echo kon de YouTube-response niet verwerken."


        case .serverError(
            let code
        ):

            return
                "YouTube heeft momenteel een serverprobleem. Foutcode \(code)."


        case .httpError(
            let code,
            let message
        ):

            if let message,
               !message.isEmpty {

                return
                    "YouTube-fout \(code): \(message)"
            }


            return
                "YouTube-fout \(code)."
        }
    }
}
