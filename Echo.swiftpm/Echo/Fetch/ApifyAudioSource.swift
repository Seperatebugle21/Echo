import Foundation

enum ApifyDownloadError: LocalizedError {
    case missingToken
    case invalidURL
    case requestFailed(Int)
    case invalidResponse
    case noDownloadURL
    case permissionRequired

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Apify API token ontbreekt."

        case .invalidURL:
            return "Ongeldige Apify URL."

        case .requestFailed(let code):
            return "Apify download mislukt. HTTP \(code)."

        case .invalidResponse:
            return "Echo kon het Apify-resultaat niet lezen."

        case .noDownloadURL:
            return "Apify heeft geen downloadbaar MP3-bestand teruggegeven."

        case .permissionRequired:
            return "Bevestig eerst dat je toestemming hebt."
        }
    }
}


struct ApifyDownloadResult {
    let downloadURL: URL
    let fileName: String?
}


private struct ApifyActorResult: Decodable {
    let note: String?
    let id: String?
    let input: String?

    let downloadedFileUrl: String?
    let fileKey: String?

    let audioOnlyUrl: String?
}


@MainActor
final class ApifyAudioSource {

    static let shared = ApifyAudioSource()

    private init() {}


    // MARK: - Download MP3

    func resolveMP3(
        youtubeURL: URL,
        permissionConfirmed: Bool
    ) async throws -> ApifyDownloadResult {

        guard permissionConfirmed else {
            throw ApifyDownloadError.permissionRequired
        }

        guard
            let token = Bundle.main.object(
                forInfoDictionaryKey: "APIFY_API_TOKEN"
            ) as? String,
            !token.isEmpty
        else {
            throw ApifyDownloadError.missingToken
        }


        var components = URLComponents(
            string:
                "https://api.apify.com/v2/actors/streamers~youtube-video-downloader/run-sync-get-dataset-items"
        )

        components?.queryItems = [
            URLQueryItem(
                name: "token",
                value: token
            )
        ]

        guard let endpoint = components?.url else {
            throw ApifyDownloadError.invalidURL
        }


        var request = URLRequest(url: endpoint)

        request.httpMethod = "POST"

        request.timeoutInterval = 180

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )


        let body: [String: Any] = [

            "videos": [
                [
                    "url":
                        youtubeURL.absoluteString
                ]
            ],

            // Laat Apify het resultaat opslaan,
            // zodat we een download-URL terugkrijgen.
            "storeInKVStore": true,

            // Vraag MP3
            "preferredFormat": "mp3",

            "filenameTemplateParts": [
                "title"
            ]
        ]


        request.httpBody =
            try JSONSerialization.data(
                withJSONObject: body
            )


        let (data, response) =
            try await URLSession.shared.data(
                for: request
            )


        guard
            let http =
                response as? HTTPURLResponse
        else {
            throw ApifyDownloadError.invalidResponse
        }


        guard 200..<300 ~= http.statusCode else {

            if let text = String(
                data: data,
                encoding: .utf8
            ) {

                print(
                    "Apify error:",
                    text
                )
            }

            throw ApifyDownloadError.requestFailed(
                http.statusCode
            )
        }


        let results: [ApifyActorResult]

        do {

            results =
                try JSONDecoder().decode(
                    [ApifyActorResult].self,
                    from: data
                )

        } catch {

            print(
                "Apify JSON:",
                String(
                    data: data,
                    encoding: .utf8
                ) ?? "?"
            )

            throw ApifyDownloadError.invalidResponse
        }


        guard let result = results.first else {
            throw ApifyDownloadError.invalidResponse
        }


        print(
            "Apify note:",
            result.note ?? "none"
        )

        print(
            "Apify file:",
            result.downloadedFileUrl ?? "none"
        )


        /*
         We gebruiken downloadedFileUrl.

         audioOnlyUrl kan bijvoorbeeld een directe
         audio-stream zijn, maar is niet gegarandeerd
         een MP3. We doen dus niet alsof die een MP3 is.
        */

        guard
            let string = result.downloadedFileUrl,
            let downloadURL = URL(string: string)
        else {
            throw ApifyDownloadError.noDownloadURL
        }


        return ApifyDownloadResult(
            downloadURL: downloadURL,
            fileName: result.fileKey
        )
    }
}
