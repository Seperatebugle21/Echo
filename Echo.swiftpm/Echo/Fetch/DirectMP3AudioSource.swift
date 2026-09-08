import Foundation

final class DirectMP3AudioSource: FetchAudioSource {

    static let shared = DirectMP3AudioSource()

    private init() {}

    func resolveAudio(
        for item: FetchItem,
        quality: FetchQuality
    ) async throws -> FetchAudioResult {

        /*
         Hier moet later jouw toegestane audioresolver komen.

         Bijvoorbeeld:
         Spotify metadata
              ↓
         jouw server/API
              ↓
         directe MP3 URL
        */

        throw FetchAudioSourceError.noSourceAvailable
    }

    func result(
        fromDirectURL url: URL,
        fileName: String? = nil
    ) -> FetchAudioResult {

        FetchAudioResult(
            downloadURL: url,
            suggestedFileName: fileName
        )
    }
}
