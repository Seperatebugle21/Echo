import Foundation


enum YTDLPAudioSourceError:
    LocalizedError {

    case permissionRequired
    case noYouTubeMatch
    case noDirectAudioURL
    case invalidDirectAudioURL


    var errorDescription:
        String? {

        switch self {

        case .permissionRequired:

            return
                "Bevestig eerst dat je toestemming hebt om deze audio te downloaden."


        case .noYouTubeMatch:

            return
                "Echo kon geen overeenkomende YouTube-video vinden."


        case .noDirectAudioURL:

            return
                "yt-dlp kon geen directe audiostream vinden."


        case .invalidDirectAudioURL:

            return
                "yt-dlp gaf een ongeldige audio-URL terug."
        }
    }
}


@MainActor
final class YTDLPAudioSource {

    static let shared =
        YTDLPAudioSource()


    private init() {}


    // MARK: - Resolve

    func resolve(
        item: FetchItem
    ) async throws
        -> FetchAudioResult {

        guard
            item.permissionConfirmed
        else {

            throw
                YTDLPAudioSourceError
                    .permissionRequired
        }


        // =========================================
        // 1. Resolve YouTube URL
        //
        // Direct URL:
        // use it immediately.
        //
        // No URL:
        // search with embedded yt-dlp.
        //
        // NO YouTube Data API is used here.
        // =========================================

        let youtubeURL:
            URL


        if let existing =
            item.youtubeURL {

            youtubeURL =
                existing


            print(
                "yt-dlp direct YouTube URL:",
                youtubeURL.absoluteString
            )


        } else {

            print(
                "yt-dlp: searching YouTube without API:"
            )

            print(
                item.title,
                "-",
                item.artist
            )


            let result =
                try await
                YTDLPRunner.shared
                    .search(
                        title:
                            item.title,

                        artist:
                            item.artist
                    )


            youtubeURL =
                result.videoURL


            print(
                "yt-dlp search match:",
                result.title
            )


            print(
                "yt-dlp search uploader:",
                result.uploader
                ??
                "Unknown"
            )


            print(
                "yt-dlp YouTube URL:",
                youtubeURL.absoluteString
            )
        }


        // =========================================
        // 2. Extract via embedded yt-dlp
        // =========================================

        print(
            "Starting yt-dlp extraction..."
        )


        let extracted =
            try await
            YTDLPRunner.shared
                .extract(
                    url:
                        youtubeURL
                )


        print(
            "yt-dlp version:",
            extracted.ytdlpVersion
        )


        print(
            "yt-dlp title:",
            extracted.title
        )


        print(
            "yt-dlp uploader:",
            extracted.uploader
            ??
            "Unknown"
        )


        print(
            "yt-dlp format:",
            extracted.formatID
            ??
            "Unknown"
        )


        print(
            "yt-dlp codec:",
            extracted.audioCodec
            ??
            "Unknown"
        )


        print(
            "yt-dlp bitrate:",
            extracted.bitrate
            ??
            0
        )


        // =========================================
        // 3. Direct stream URL
        // =========================================

        guard
            let directURLString =
                extracted.directURL,
            !directURLString.isEmpty
        else {

            throw
                YTDLPAudioSourceError
                    .noDirectAudioURL
        }


        guard
            let directURL =
                URL(
                    string:
                        directURLString
                )
        else {

            throw
                YTDLPAudioSourceError
                    .invalidDirectAudioURL
        }


        // =========================================
        // 4. Correct source extension
        // =========================================

        let fileExtension =
            normalizedExtension(
                extracted.fileExtension
            )


        let fileName =
            makeTemporaryFileName(
                item:
                    item,

                extension:
                    fileExtension
            )


        print(
            "yt-dlp direct audio:",
            directURL.absoluteString
        )


        print(
            "yt-dlp temporary filename:",
            fileName
        )


        return
            FetchAudioResult(

                downloadURL:
                    directURL,

                suggestedFileName:
                    fileName
            )
    }


    // MARK: - Extension

    private func normalizedExtension(
        _ value: String?
    ) -> String {

        guard let value else {

            return "bin"
        }


        let cleaned =
            value
                .lowercased()
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        guard
            !cleaned.isEmpty
        else {

            return "bin"
        }


        switch cleaned {

        case "webm":

            return "webm"


        case "m4a":

            return "m4a"


        case "mp4":

            return "mp4"


        case "mp3":

            return "mp3"


        case "ogg":

            return "ogg"


        case "opus":

            return "opus"


        case "aac":

            return "aac"


        default:

            return cleaned
        }
    }


    // MARK: - File name

    private func makeTemporaryFileName(
        item: FetchItem,
        extension fileExtension: String
    ) -> String {

        let illegal =
            CharacterSet(
                charactersIn:
                    "/\\:*?\"<>|"
            )


        let base =
            "\(item.title) - \(item.artist)"


        let cleaned =
            base
                .components(
                    separatedBy:
                        illegal
                )
                .joined(
                    separator:
                        ""
                )
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        return
            "\(cleaned)-ytdlp-source.\(fileExtension)"
    }
}
