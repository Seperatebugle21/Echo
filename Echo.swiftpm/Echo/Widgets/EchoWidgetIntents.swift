import AppIntents
import Foundation

enum EchoWidgetAction: String, AppEnum {
    case toggle, previous, next, favorite, play, flow
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "widget_intent_action_type"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .toggle: "widget_intent_action_toggle", .previous: "widget_intent_action_previous",
        .next: "widget_intent_action_next", .favorite: "widget_intent_action_favorite",
        .play: "widget_intent_action_play", .flow: "widget_intent_action_flow"
    ]
}

// AudioPlaybackIntent runs in the app process, where the actual player lives.
struct EchoWidgetPlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "widget_intent_title"
    static var openAppWhenRun: Bool = false
    @Parameter(title: "widget_intent_parameter_action") var action: EchoWidgetAction
    @Parameter(title: "widget_intent_parameter_song") var songID: String

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

/// Control Center / Lock Screen play-pause toggle. Runs in the app process like the widget buttons.
struct EchoControlPlaybackIntent: SetValueIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource = "control_play_pause_title"
    static var openAppWhenRun: Bool = false
    @Parameter(title: "control_play_pause_title") var value: Bool

    init() { value = false }

    @MainActor func perform() async throws -> some IntentResult {
        #if !ECHO_WIDGET_EXTENSION
        EchoWidgetPlaybackController.setPlaying(value)
        #endif
        return .result()
    }
}

/// Opens Echo from a Control Center control.
struct EchoOpenAppIntent: AppIntent {
    static var title: LocalizedStringResource = "control_open_title"
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor func perform() async throws -> some IntentResult { .result() }
}

#if !ECHO_WIDGET_EXTENSION
@MainActor enum EchoWidgetPlaybackController {
    /// Starts or pauses playback; without a current song it resumes the song the widgets show.
    static func setPlaying(_ playing: Bool) {
        let player = AudioPlayerManager.shared
        if player.currentSong != nil {
            player.setPlaybackDesired(playing)
            EchoWidgetSnapshotPublisher.refresh()
        } else if playing {
            try? perform(.play, songID: nil)
        }
    }

    enum PlaybackError: LocalizedError {
        case missingSong
        var errorDescription: String? { EchoLocalization.string("widget_intent_error_missing_song") }
    }

    static func perform(_ action: EchoWidgetAction, songID: UUID?) throws {
        let library = MusicLibraryManager.shared
        let player = AudioPlayerManager.shared
        defer { EchoWidgetSnapshotPublisher.refresh() }
        if action == .next, player.currentSong != nil { player.next(); return }
        if action == .previous, player.currentSong != nil { player.previous(); return }
        if action == .toggle, player.currentSong != nil { player.togglePlayPause(); return }
        if action == .flow {
            player.allSongs = library.songs
            player.startEchoFlow()
            return
        }
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
