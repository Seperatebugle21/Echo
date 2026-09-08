import Foundation


// MARK: - Errors

enum ApifyDownloadError: LocalizedError {

    case missingToken
    case invalidURL
    case requestFailed(Int, String?)
    case invalidResponse(String)
    case noDownloadURL
    case permissionRequired

    var errorDescription: String? {

        switch self {

        case .missingToken:
            return "Apify API token ontbreekt."

        case .invalidURL:
            return "Ongeldige YouTube- of Apify-URL."

        case .requestFailed(let code, let message):
            if let message, !message.isEmpty {
                return "Apify fout \(code): \(message)"
            }

            return "Apify download mislukt. HTTP \(code)."

        case .invalidResponse(let response):
            return "Echo kon het Apify-resultaat niet lezen: \(response)"

        case .noDownloadURL:
            return "Apify heeft geen downloadbaar bestand teruggegeven."

        case .permissionRequired:
            return "Bevestig eerst dat je toestemming hebt."
        }
    }
}


// MARK: - Result used by Echo

struct ApifyDownloadResult {

    let downloadURL: URL
    let fileName: String?
}


// MARK: - Actor Dataset Item

private struct ApifyActorResult: Decodable {

    let note: String?
    let id: String?
    let input: String?

    let downloadedFileUrl: String?
    let fileKey: String?

    let audioOnlyUrl: String?
    let videoOnlyUrl: String?
}


// MARK: - Possible wrapper

private struct ApifyWrappedResponse: Decodable {
    let data: [ApifyActorResult]?
}


// MARK: - Source

@MainActor
final class ApifyAudioSource {

    static let shared = ApifyAudioSource()

    private init() {}


    // MARK: Resolve

    func resolveMP3(
        youtubeURL: URL,
        permissionConfirmed: Bool
    ) async throws -> ApifyDownloadResult {

        guard permissionConfirmed else {
            throw ApifyDownloadError.permissionRequired
        }


        // Check YouTube URL

        guard let host = youtubeURL.host?.lowercased(),
              host.contains("youtube.com") ||
              host.contains("youtu.be")
        else {
            throw ApifyDownloadError.invalidURL
        }


let token =
    ApifySettings.shared.apiToken
        .trimmingCharacters(
            in: .whitespacesAndNewlines
        )

guard !token.isEmpty else {
    throw ApifyDownloadError.missingToken
}


        // MARK: Endpoint

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


        // MARK: Request

        var request = URLRequest(url: endpoint)

        request.httpMethod = "POST"

        // MP3 conversion can take a while
        request.timeoutInterval = 300

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )


        let body: [String: Any] = [

            "videos": [
                [
                    "url": youtubeURL.absoluteString
                ]
            ],

            "storeInKVStore": true,

            "preferredQuality": "720p",

            "preferredFormat": "mp4",

            "filenameTemplateParts": [
                "title"
            ]
        ]


        request.httpBody =
            try JSONSerialization.data(
                withJSONObject: body
            )


        print("===== APIFY REQUEST =====")
        print("YouTube:", youtubeURL.absoluteString)
        print("Endpoint:", endpoint.absoluteString)


        // MARK: Execute

        let (data, response) =
            try await URLSession.shared.data(
                for: request
            )


        guard let http =
            response as? HTTPURLResponse
        else {
            throw ApifyDownloadError.invalidResponse(
                "Geen HTTP-response."
            )
        }


        let rawResponse =
            String(
                data: data,
                encoding: .utf8
            ) ?? "<geen tekst>"


        print("")
        print("===== APIFY RESPONSE =====")
        print("HTTP:", http.statusCode)
        print(rawResponse)
        print("==========================")
        print("")


        guard 200..<300 ~= http.statusCode else {

            throw ApifyDownloadError.requestFailed(
                http.statusCode,
                rawResponse
            )
        }


        // MARK: Decode

        let decoder = JSONDecoder()

        let results: [ApifyActorResult]


        // Vorm 1:
        //
        // [
        //   {
        //      "downloadedFileUrl": "..."
        //   }
        // ]

        if let array =
            try? decoder.decode(
                [ApifyActorResult].self,
                from: data
            ) {

            results = array


        // Vorm 2:
        //
        // {
        //    "downloadedFileUrl": "..."
        // }

        } else if let single =
            try? decoder.decode(
                ApifyActorResult.self,
                from: data
            ) {

            results = [single]


        // Vorm 3:
        //
        // {
        //    "data": [...]
        // }

        } else if let wrapped =
            try? decoder.decode(
                ApifyWrappedResponse.self,
                from: data
            ),
            let data = wrapped.data {

            results = data


        } else {

            throw ApifyDownloadError.invalidResponse(
                rawResponse
            )
        }


        guard let result = results.first else {

            throw ApifyDownloadError.invalidResponse(
                "Apify gaf een lege dataset terug."
            )
        }


        print("Apify video ID:", result.id ?? "nil")
        print(
            "downloadedFileUrl:",
            result.downloadedFileUrl ?? "nil"
        )
        print(
            "audioOnlyUrl:",
            result.audioOnlyUrl ?? "nil"
        )
        print(
            "fileKey:",
            result.fileKey ?? "nil"
        )


        // MARK: Prefer stored file

        if let string = result.downloadedFileUrl,
           let url = URL(string: string) {

            return ApifyDownloadResult(
                downloadURL: url,
                fileName: makeFileName(
                    result.fileKey
                )
            )
        }


        // Fallback:
        // audioOnlyUrl might exist even when
        // storeInKVStore did not produce a file.

        if let string = result.audioOnlyUrl,
           let url = URL(string: string) {

            return ApifyDownloadResult(
                downloadURL: url,
                fileName: nil
            )
        }


        throw ApifyDownloadError.noDownloadURL
    }


    // MARK: File name

    private func makeFileName(
        _ fileKey: String?
    ) -> String? {

        guard let fileKey,
              !fileKey.isEmpty
        else {
            return nil
        }

        let last =
            URL(
                fileURLWithPath: fileKey
            )
            .lastPathComponent

        return last.isEmpty
            ? nil
            : last
    }
}
