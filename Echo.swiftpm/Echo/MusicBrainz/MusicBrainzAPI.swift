import Foundation


enum MusicBrainzAPIError:
    LocalizedError {

    case invalidURL

    case invalidResponse

    case rateLimited

    case serverError(Int)

    case decodingFailed


    var errorDescription:
        String? {

        switch self {

        case .invalidURL:

            return
                "Echo could not create the MusicBrainz search URL."


        case .invalidResponse:

            return
                "MusicBrainz returned an invalid response."


        case .rateLimited:

            return
                "MusicBrainz is temporarily rate limiting requests. Please try again in a moment."


        case .serverError(
            let code
        ):

            return
                "MusicBrainz returned server error \(code)."


        case .decodingFailed:

            return
                "Echo could not read the MusicBrainz search results."
        }
    }
}


// MARK: - MusicBrainz API

actor MusicBrainzAPI {

    static let shared =
        MusicBrainzAPI()


    private let baseURL =
        "https://musicbrainz.org/ws/2/recording/"


    // MusicBrainz requests a meaningful User-Agent.

    private let userAgent =
        "Echo/1.0 (https://github.com/Seperatebugle21/Echo)"


    // MusicBrainz asks clients not to exceed
    // approximately one API request per second.

    private var lastRequest:
        Date?


    private init() {}


    // MARK: - Search

    func searchTracks(
        query: String,
        limit: Int = 25
    ) async throws
        -> [MusicBrainzTrack] {

        let text =
            query
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        guard !text.isEmpty else {

            return []
        }


        await waitForRateLimit()


        guard var components =
            URLComponents(
                string:
                    baseURL
            )
        else {

            throw MusicBrainzAPIError
                .invalidURL
        }


        components.queryItems = [

            URLQueryItem(
                name:
                    "query",
                value:
                    text
            ),

            URLQueryItem(
                name:
                    "fmt",
                value:
                    "json"
            ),

            URLQueryItem(
                name:
                    "limit",
                value:
                    String(
                        min(
                            max(
                                limit,
                                1
                            ),
                            100
                        )
                    )
            )
        ]


        guard let url =
            components.url
        else {

            throw MusicBrainzAPIError
                .invalidURL
        }


        var request =
            URLRequest(
                url:
                    url
            )


        request.httpMethod =
            "GET"


        request.timeoutInterval =
            20


        request.setValue(
            userAgent,
            forHTTPHeaderField:
                "User-Agent"
        )


        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Accept"
        )


        lastRequest =
            Date()


        let (
            data,
            response
        ) =
            try await
            URLSession.shared
                .data(
                    for:
                        request
                )


        guard let httpResponse =
            response
                as?
                HTTPURLResponse
        else {

            throw MusicBrainzAPIError
                .invalidResponse
        }


        switch httpResponse.statusCode {

        case 200..<300:

            break


        case 429,
             503:

            throw MusicBrainzAPIError
                .rateLimited


        default:

            throw MusicBrainzAPIError
                .serverError(
                    httpResponse.statusCode
                )
        }


        do {

            let response =
                try JSONDecoder()
                    .decode(
                        MusicBrainzRecordingSearchResponse.self,
                        from:
                            data
                    )


            // MusicBrainz can contain several editions/releases
            // of the same recording. Keep the highest-ranked
            // unique recording results.

            var seenIDs =
                Set<String>()


            var tracks:
                [MusicBrainzTrack] = []


            let sorted =
                response.recordings
                    .sorted {

                        (
                            $0.score
                            ??
                            0
                        )
                        >
                        (
                            $1.score
                            ??
                            0
                        )
                    }


            for recording in sorted {

                guard !seenIDs
                    .contains(
                        recording.id
                    )
                else {

                    continue
                }


                seenIDs.insert(
                    recording.id
                )


                tracks.append(
                    recording.echoTrack
                )
            }


            return tracks


        } catch let error
            as MusicBrainzAPIError {

            throw error


        } catch {

            print(
                "MusicBrainz decode error:",
                error
            )


            throw MusicBrainzAPIError
                .decodingFailed
        }
    }


    // MARK: - Rate Limit

    private func waitForRateLimit()
        async {

        guard let lastRequest else {

            return
        }


        let elapsed =
            Date()
                .timeIntervalSince(
                    lastRequest
                )


        let minimumInterval:
            TimeInterval =
            1.05


        guard elapsed <
                minimumInterval
        else {

            return
        }


        let remaining =
            minimumInterval
            -
            elapsed


        let nanoseconds =
            UInt64(
                remaining
                *
                1_000_000_000
            )


        try? await Task.sleep(
            nanoseconds:
                nanoseconds
        )
    }
}
