import Foundation

@MainActor
enum EchoWidgetDeepLink {

    static func handle(_ url: URL) -> Bool {

        guard url.scheme?.lowercased() == "echo" else {
            return false
        }

        switch url.host?.lowercased() {

        case "open":
            return true

        case "play":
            return playSong(from: url)

        default:
            return false
        }
    }

    private static func playSong(from url: URL) -> Bool {

        guard
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            let rawID = components.queryItems?
                .first(where: { $0.name == "id" })?
                .value,
            let songID = UUID(uuidString: rawID)
        else {
            return false
        }

        let library = MusicLibraryManager.shared
        let audioPlayer = AudioPlayerManager.shared

        guard
            let song = library.songs.first(
                where: { $0.id == songID }
            ),
            let fileURL = library.getURL(for: song),
            FileManager.default.fileExists(
                atPath: fileURL.path
            )
        else {
            return true
        }

        library.markAsPlayed(song)

        audioPlayer.lastPlaybackDirection = .fade
        audioPlayer.play(
            song: song,
            url: fileURL,
            queue: [song]
        )

        audioPlayer.allSongs = library.songs
        audioPlayer.fillAutoNext(from: library.songs)

        return true
    }
}
