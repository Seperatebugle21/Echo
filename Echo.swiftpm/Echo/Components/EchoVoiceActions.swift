import AppIntents
import Foundation

/// Siri uses system localization; free-form commands respond in their recognized language.
/// Deliberately independent of Echo's in-app selectedLanguage preference.
enum EchoSiriText {
    static func string(_ key: String, language: EchoSpokenCommand.Language? = nil) -> String {
        #if SWIFT_PACKAGE
        let resources = Bundle.module
        #else
        let resources = Bundle.main
        #endif
        let bundle: Bundle
        if let language, let path = resources.path(forResource: language.rawValue, ofType: "lproj"),
           let localized = Bundle(path: path) { bundle = localized }
        else { bundle = resources }
        return bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }
}

@MainActor
enum EchoVoiceActions {
    static func perform(_ action: EchoSpokenCommand.Action, language: EchoSpokenCommand.Language? = nil) throws -> String {
        let audio = AudioPlayerManager.shared
        let library = MusicLibraryManager.shared
        func requireCurrent() throws -> Song {
            guard let song = audio.currentSong else { throw EchoSiriError.nothingPlaying }
            return song
        }
        func requireLocal() throws -> Song {
            let song = try requireCurrent()
            guard song.podcastEpisodeID == nil, library.songs.contains(where: { $0.id == song.id }) else {
                throw EchoSiriError.localMusicRequired
            }
            return song
        }
        let key: String
        switch action {
        case .flow, .flowCurrent:
            if action == .flowCurrent { _ = try requireLocal() }
            guard library.songs.contains(where: { song in
                song.podcastEpisodeID == nil && library.getURL(for: song).map { FileManager.default.fileExists(atPath: $0.path) } == true
            }) else { throw EchoSiriError.audioFileMissing }
            // The existing Flow uses the current song as its anchor without restarting it.
            audio.startEchoFlow()
            guard audio.flowActive else { throw EchoSiriError.operationFailed }
            key = "siri_reply_flow"
        case .stopFlow:
            audio.stopEchoFlow(); key = "siri_reply_flow_off"
        case .favorite, .unfavorite:
            let song = try requireLocal(), enabled = action == .favorite
            if library.isFavorite(song) != enabled { library.toggleFavorite(song) }
            guard library.isFavorite(song) == enabled else { throw EchoSiriError.operationFailed }
            key = enabled ? "siri_reply_favorite" : "siri_reply_unfavorite"
        case .shuffleOn, .shuffleOff:
            _ = try requireCurrent()
            audio.setShuffle(action == .shuffleOn)
            key = action == .shuffleOn ? "siri_reply_shuffle_on" : "siri_reply_shuffle_off"
        case .repeatOne, .repeatAll, .repeatOff:
            _ = try requireCurrent()
            audio.setRepeatMode(action == .repeatOne ? .one : action == .repeatAll ? .all : .off)
            key = action == .repeatOne ? "siri_reply_repeat_one" : action == .repeatAll ? "siri_reply_repeat_all" : "siri_reply_repeat_off"
        case .pause, .resume:
            _ = try requireCurrent()
            audio.setPlaybackDesired(action == .resume)
            key = action == .pause ? "siri_reply_pause" : "siri_reply_resume"
        case .next, .previous:
            _ = try requireCurrent()
            if action == .next { audio.next() } else { audio.previous() }
            key = action == .next ? "siri_reply_next" : "siri_reply_previous"
        case .status:
            let song = try requireCurrent()
            let prefix = EchoSiriText.string(audio.isPlaying ? "siri_reply_playing" : "siri_reply_paused", language: language)
            return prefix + " " + song.title + " · " + song.artist
        case .sleep(let minutes):
            guard (1...720).contains(minutes) else { throw EchoSiriError.invalidDuration }
            _ = try requireCurrent()
            audio.startSleepTimer(minutes: minutes); key = "siri_reply_sleep"
        case .cancelSleep:
            audio.cancelSleepTimer(); key = "siri_reply_sleep_off"
        }
        return EchoSiriText.string(key, language: language)
    }
}

/// Shortcuts can pass dictated or typed text in any supported language to this action.
struct EchoVoiceCommandIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "siri_command_title"
    static var description = IntentDescription("siri_command_description")
    static var openAppWhenRun = false
    @Parameter(title: "siri_command_parameter") var command: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let parsed = EchoSpokenCommand.parse(command) else { throw EchoSiriError.commandNotUnderstood }
        do {
            let reply = try EchoVoiceActions.perform(parsed.action, language: parsed.language)
            return .result(dialog: "\(reply)")
        } catch let error as EchoSiriError {
            let reply = EchoSiriText.string(error.localizationKey, language: parsed.language)
            throw EchoSiriLocalizedFailure(message: reply)
        }
    }
}

private struct EchoSiriLocalizedFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct StartEchoFlowIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "siri_flow_title"
    static var description = IntentDescription("siri_flow_description")
    static var openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try EchoVoiceActions.perform(.flow)
        return .result(dialog: "\(reply)")
    }
}

struct FavoriteCurrentSongIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "siri_favorite_title"
    static var openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try EchoVoiceActions.perform(.favorite)
        return .result(dialog: "\(reply)")
    }
}

struct UnfavoriteCurrentSongIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "siri_unfavorite_title"
    static var openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try EchoVoiceActions.perform(.unfavorite)
        return .result(dialog: "\(reply)")
    }
}

struct StopEchoFlowIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "siri_stop_flow_title"
    static var openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try EchoVoiceActions.perform(.stopFlow)
        return .result(dialog: "\(reply)")
    }
}

struct EchoSleepTimerIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "siri_sleep_title"
    static var openAppWhenRun = false
    @Parameter(title: "siri_minutes", default: 30) var minutes: Int
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try EchoVoiceActions.perform(.sleep(minutes))
        return .result(dialog: "\(reply)")
    }
}

struct CancelEchoSleepTimerIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "siri_cancel_sleep_title"
    static var openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try EchoVoiceActions.perform(.cancelSleep)
        return .result(dialog: "\(reply)")
    }
}

struct PauseEchoIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "siri_pause_title"
    static var openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try EchoVoiceActions.perform(.pause)
        return .result(dialog: "\(reply)")
    }
}

struct ResumeEchoIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "siri_resume_title"
    static var openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try EchoVoiceActions.perform(.resume)
        return .result(dialog: "\(reply)")
    }
}

struct NextEchoSongIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "siri_next_title"
    static var openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try EchoVoiceActions.perform(.next)
        return .result(dialog: "\(reply)")
    }
}

struct PreviousEchoSongIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "siri_previous_title"
    static var openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try EchoVoiceActions.perform(.previous)
        return .result(dialog: "\(reply)")
    }
}

struct EchoPlaybackStatusIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "siri_status_title"
    static var openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try EchoVoiceActions.perform(.status)
        return .result(dialog: "\(reply)")
    }
}
