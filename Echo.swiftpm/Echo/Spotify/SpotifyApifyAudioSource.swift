import Foundation

struct SpotifyApifyResult {

    let downloadURL: URL
    let suggestedFileName: String?
}


enum SpotifyApifyError: LocalizedError {

    case missingToken
    case invalidSpotifyURL
    case invalidResponse
    case requestFailed(Int, String)
    case noDownloadURL

    var errorDescription: String? {

        switch self {

        case .missingToken:
            return "No Apify API token configured."

        case .invalidSpotifyURL:
            return "Invalid Spotify URL."

        case .invalidResponse:
            return "Invalid response from the Spotify Actor."

        case let .requestFailed(code, message):
            return "Spotify Actor failed (\(code)): \(message)"

        case .noDownloadURL:
            return "The Spotify Actor returned no audio download URL."
        }
    }
}


final class SpotifyApifyAudioSource {

    static let shared =
        SpotifyApifyAudioSource()

    private init() {}


    func resolve(
        spotifyURL: URL
    ) async throws -> SpotifyApifyResult {

        // MARK: - Token

        let token =
            await MainActor.run {
                ApifySettings.shared.apiToken
            }
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !token.isEmpty else {
            throw SpotifyApifyError.missingToken
        }


        // MARK: - Validate Spotify URL

        guard
            let host = spotifyURL.host?.lowercased(),
            host == "open.spotify.com" ||
            host.hasSuffix(".spotify.com")
        else {
            throw SpotifyApifyError.invalidSpotifyURL
        }


        // MARK: - Actor URL

        let actorID =
            "D50jl7rp34h8YHRWg"

        guard var components =
                URLComponents(
                    string:
                        "https://api.apify.com/v2/actors/\(actorID)/run-sync-get-dataset-items"
                )
        else {
            throw SpotifyApifyError.invalidResponse
        }

        components.queryItems = [

            URLQueryItem(
                name: "clean",
                value: "true"
            ),

            URLQueryItem(
                name: "limit",
                value: "10"
            )
        ]

        guard let url = components.url else {
            throw SpotifyApifyError.invalidResponse
        }


        // MARK: - Request

        var request =
            URLRequest(url: url)

        request.httpMethod = "POST"

        request.timeoutInterval = 300

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        request.setValue(
            "Bearer \(token)",
            forHTTPHeaderField: "Authorization"
        )


        // MARK: - Actor Input

        let input:
            [String: Any] = [

                "links": [
                    spotifyURL.absoluteString
                ],

                "proxyConfiguration": [
                    "useApifyProxy": false
                ]
            ]

        request.httpBody =
            try JSONSerialization.data(
                withJSONObject: input
            )


        // MARK: - Run Actor

        let (data, response) =
            try await URLSession.shared.data(
                for: request
            )


        guard let http =
                response as? HTTPURLResponse
        else {
            throw SpotifyApifyError.invalidResponse
        }


        // Debug response

        let raw =
            String(
                data: data,
                encoding: .utf8
            ) ?? ""

        print(
            "Spotify Actor response:",
            raw
        )


        guard 200..<300 ~= http.statusCode else {

            throw SpotifyApifyError.requestFailed(
                http.statusCode,
                raw
            )
        }


        // MARK: - Decode JSON

        let json =
            try JSONSerialization.jsonObject(
                with: data
            )

        guard let items =
                json as? [[String: Any]],
              let first = items.first
        else {
            throw SpotifyApifyError.invalidResponse
        }


        // MARK: - Find Audio URL

        guard let downloadURL =
                findDownloadURL(
                    in: first
                )
        else {

            print(
                "Could not find audio URL in:",
                first
            )

            throw SpotifyApifyError.noDownloadURL
        }


        // MARK: - Filename

        let fileName =
            findString(
                keys: [
                    "filename",
                    "fileName",
                    "name",
                    "title"
                ],
                in: first
            )


        print(
            "Spotify download URL:",
            downloadURL
        )


        return SpotifyApifyResult(
            downloadURL: downloadURL,
            suggestedFileName: fileName
        )
    }


    // MARK: - Download URL Detection

    private func findDownloadURL(
        in dictionary: [String: Any]
    ) -> URL? {

        let preferredKeys = [

            "downloadUrl",
            "downloadURL",

            "download_url",

            "audioUrl",
            "audioURL",

            "audio_url",

            "fileUrl",
            "fileURL",

            "file_url",

            "mp3Url",
            "mp3URL",

            "mp3_url",

            "url"
        ]


        // First try known keys

        for key in preferredKeys {

            if
                let value =
                    dictionary[key] as? String,
                let url =
                    makeAudioURL(value)
            {
                return url
            }
        }


        // Then inspect nested values

        for value in dictionary.values {

            if let nested =
                    value as? [String: Any]
            {

                if let found =
                        findDownloadURL(
                            in: nested
                        )
                {
                    return found
                }
            }


            if let array =
                    value as? [[String: Any]]
            {

                for object in array {

                    if let found =
                            findDownloadURL(
                                in: object
                            )
                    {
                        return found
                    }
                }
            }
        }


        return nil
    }


    private func makeAudioURL(
        _ string: String
    ) -> URL? {

        guard
            let url = URL(string: string),
            let scheme =
                url.scheme?.lowercased(),
            scheme == "https" ||
            scheme == "http"
        else {
            return nil
        }

        return url
    }


    // MARK: - String Finder

    private func findString(
        keys: [String],
        in dictionary: [String: Any]
    ) -> String? {

        for key in keys {

            if let value =
                    dictionary[key] as? String,
               !value.isEmpty
            {
                return value
            }
        }

        return nil
    }
}
