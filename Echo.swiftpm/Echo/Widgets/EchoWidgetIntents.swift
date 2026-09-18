import AppIntents
import Foundation

enum EchoWidgetAction: String, AppEnum {
    case toggle, previous, next, favorite, play
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Muziekbediening"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .toggle: "Afspelen of pauzeren", .previous: "Vorig nummer", .next: "Volgend nummer",
        .favorite: "Favoriet wijzigen", .play: "Nummer afspelen"
    ]
}

// AudioPlaybackIntent runs in the app process, where the actual player lives.
struct EchoWidgetPlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Bedien Echo"
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Actie") var action: EchoWidgetAction
    @Parameter(title: "Nummer") var songID: String

    init() { action = .toggle; songID = "" }
    init(_ action: EchoWidgetAction, songID: UUID? = nil) {
        self.action = action
        self.songID = songID?.uuidString ?? ""
    }

    @MainActor func perform() async throws -> some IntentResult {
        #if !ECHO_WIDGET_EXTENSION
        try EchoWidgetPlaybackController.perform(action, songID: UUID(uuidString: songID))
        #endif
        return .result()
    }
}

#if !ECHO_WIDGET_EXTENSION
@MainActor enum EchoWidgetPlaybackController {
    enum PlaybackError: LocalizedError {
        case missingSong
        var errorDescription: String? { "Dit nummer is niet meer beschikbaar in Echo." }
    }

    static func perform(_ action: EchoWidgetAction, songID: UUID?) throws {
        let library = MusicLibraryManager.shared
        let player = AudioPlayerManager.shared
        defer { EchoWidgetSnapshotPublisher.refresh() }
        if action == .next, player.currentSong != nil { player.next(); return }
        if action == .previous, player.currentSong != nil { player.previous(); return }
        if action == .toggle, player.currentSong != nil { player.togglePlayPause(); return }
        let id = songID ?? player.currentSong?.id ?? EchoWidgetSnapshotStore.load().currentSong?.id
        if let episode = PodcastStore.shared.state.episodes.values.first(where: { $0.playbackID == id }) {
            if action == .favorite { PodcastStore.shared.toggleSaved(episode) }
            else { player.playPodcast(episode) }
            return
        }
        guard let song = library.songs.first(where: { $0.id == id }) else { throw PlaybackError.missingSong }
        if action == .favorite { library.toggleFavorite(song); return }
        guard let url = library.getURL(for: song), FileManager.default.fileExists(atPath: url.path)
        else { throw PlaybackError.missingSong }
        library.markAsPlayed(song)
        player.lastPlaybackDirection = .fade
        player.allSongs = library.songs
        player.play(song: song, url: url, queue: [song])
        player.fillAutoNext(from: library.songs)
    }
}
#endif
