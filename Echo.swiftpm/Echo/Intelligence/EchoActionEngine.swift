import Foundation

@MainActor final class EchoActionEngine {
    private let library = MusicLibraryManager.shared
    private let player = AudioPlayerManager.shared
    private let learning = RecommendationManager.shared
    private let podcasts = PodcastStore.shared
    private(set) var navigation: AppTab?
    private var dj: DJSession
    struct DJSession: Codable {
        var query = ""
        var exclusions: [String] = []
        var selectedIDs: [UUID] = []
        var recent: [UUID] = []
    }
    init() {
        dj = UserDefaults.standard.data(forKey: "echo.intelligence.dj.v1").flatMap { try? JSONDecoder().decode(DJSession.self, from: $0) } ?? DJSession()
    }
    var djContext: String {
        (try? json(["query": dj.query, "excluded": dj.exclusions, "selectedIDs": dj.selectedIDs.map(\.uuidString)])) ?? "{}"
    }
    func prepare(_ call: AIToolCall) throws -> AIToolCall {
        // Pin 'this song' before showing confirmation, even if the track ends
        // while the user is reviewing the action.
        try AIFavoriteTarget.resolve(call, currentSongID: player.currentSong?.id.uuidString)
    }
    func execute(_ call: AIToolCall) async throws -> String {
        let definition = try EchoToolRegistry.definition(call.name)
        let args = try definition.validate(call.arguments)
        let policy = AISettingsStore.shared.value.permission
        if definition.mutating && policy == .chatOnly { throw AIError.permission }
        try Task.checkCancellation()
        let operation = args["operation"] as? String ?? ""
        switch call.name {
        case "library_search":
            var songs = library.songs.filter { $0.podcastEpisodeID == nil }
            for field in ["query", "genre", "artist", "album"] {
                if let term = args[field] as? String, !term.isEmpty {
                    songs = songs.filter { song in
                        let value: String
                        switch field { case "genre": value = song.genre ?? ""; case "artist": value = ([song.artist] + (song.artistNames ?? [])).joined(separator: " "); case "album": value = ([song.album ?? ""] + (song.additionalAlbums ?? []).map(\.name)).joined(separator: " "); default: value = [song.title, song.artist, song.album ?? "", song.genre ?? ""].joined(separator: " ") }
                        return value.localizedStandardContains(term)
                    }
                }
            }
            if args["favorites"] as? Bool == true { songs = songs.filter { library.isFavorite($0) } }
            if let year = args["yearFrom"] as? Double { songs = songs.filter { $0.releaseYear.map { Double($0) >= year } ?? false } }
            if let year = args["yearTo"] as? Double { songs = songs.filter { $0.releaseYear.map { Double($0) <= year } ?? false } }
            let excluded = args["exclude"] as? [String] ?? []
            songs = songs.filter { !excludedMatch($0, excluded) }
            switch args["sort"] as? String {
            case "mostPlayed": songs.sort { count($0) > count($1) }
            case "leastPlayed": songs.sort { count($0) < count($1) }
            case "recentAdded": songs.sort { $0.dateAdded > $1.dateAdded }
            case "leastRecent": songs.sort { ($0.lastPlayed ?? .distantPast) < ($1.lastPlayed ?? .distantPast) }
            default: songs = learning.recommendations(from: songs, favoriteSongIDs: library.favoriteSongIDs, limit: songs.count)
            }
            return try json(["totalMatches": songs.count, "songs": songs.prefix(args["limit"] as? Int ?? 25).map(metadata)])
        case "playback_status":
            return try json(["isPlaying": player.isPlaying, "position": player.currentTime, "duration": player.duration,
                             "current": player.currentSong.map(metadata) ?? [:], "upcoming": player.queue.dropFirst(max(0, player.currentIndex + 1)).prefix(30).map(metadata)])
        case "play_songs": return try await play(resolve(args), shuffle: args["shuffle"] as? Bool ?? false)
        case "transport":
            guard player.currentSong != nil else { throw AIError.missing }
            switch args["command"] as? String {
            case "pause": player.setPlaybackDesired(false)
            case "resume": player.setPlaybackDesired(true); try await verifyPlayback()
            case "next": player.next(); try await verifyPlayback()
            case "previous": player.previous(); try await verifyPlayback()
            default: throw AIError.invalidArguments
            }
        case "seek":
            guard let seconds = args["seconds"] as? Double, player.duration > 0, seconds <= player.duration else { throw AIError.invalidArguments }
            player.seek(to: seconds)
            return try json(["status": "seek_requested", "seconds": seconds])
        case "playback_options":
            if let shuffle = args["shuffle"] as? Bool { player.setShuffle(shuffle) }
            if let mode = args["repeat"] as? String { player.setRepeatMode(mode == "one" ? .one : mode == "all" ? .all : .off) }
        case "queue_edit":
            let songs = operation == "clear" ? [] : try resolve(args, allowEmpty: operation == "replace")
            player.stopEchoFlow()
            var upcoming = Array(player.queue.dropFirst(max(0, player.currentIndex + 1)))
            switch operation {
            case "clear": upcoming = []
            case "replace": upcoming = songs
            case "add": let existing = Set(upcoming.map(\.id)); upcoming += songs.filter { !existing.contains($0.id) }
            case "remove": let ids = Set(songs.map(\.id)); upcoming.removeAll { ids.contains($0.id) }
            default: throw AIError.invalidArguments
            }
            player.replaceIntelligenceUpcoming(upcoming)
        case "favorite":
            let song = try song(args["songID"])
            guard let enabled = args["enabled"] as? Bool else { throw AIError.invalidArguments }
            if library.isFavorite(song) != enabled { library.toggleFavorite(song) }
            guard library.isFavorite(song) == enabled else { throw AIError.storage }
            return try json(["status": "completed", "action": "favorite", "song": metadata(song), "enabled": enabled])
        case "playlists":
            return try json(library.playlists.prefix(60).map { ["id": $0.id.uuidString, "name": String($0.displayName().prefix(150)), "count": library.songs(in: $0).count] as [String: Any] })
        case "playlist_create":
            let name = try nonempty(args["name"]), songs = try resolve(args, allowEmpty: true)
            let playlist = library.createPlaylist(name: name)
            for song in songs { library.addSong(song, to: playlist) }
            guard let saved = library.playlists.first(where: { $0.id == playlist.id }), Set(saved.songIDs) == Set(songs.map(\.id)) else { throw AIError.storage }
            return try json(["status": "created", "playlistID": saved.id.uuidString, "name": saved.name, "count": saved.songIDs.count])
        case "playlist_edit":
            let index = try playlistIndex(args)
            guard library.playlists[index].smartDefinition == nil else { throw AIError.invalidArguments }
            if operation == "rename" {
                library.playlists[index].name = try nonempty(args["name"])
                library.playlists[index].automaticNameKey = nil
            } else {
                let songs = try resolve(args, allowEmpty: true), playlist = library.playlists[index]
                switch operation {
                case "add": for song in songs { library.addSong(song, to: playlist) }
                case "remove": for song in songs { library.removeSong(song, from: playlist) }
                case "reorder":
                    guard songs.count == playlist.songIDs.count, Set(songs.map(\.id)) == Set(playlist.songIDs) else { throw AIError.invalidArguments }
                    library.playlists[index].songIDs = songs.map(\.id)
                default: throw AIError.invalidArguments
                }
            }
        case "playlist_play":
            return try await play(library.songs(in: library.playlists[try playlistIndex(args)]), shuffle: args["shuffle"] as? Bool ?? false)
        case "playlist_delete": library.deletePlaylist(library.playlists[try playlistIndex(args)])
        case "echo_flow":
            if args["enabled"] as? Bool == true {
                let seed = try args["songID"].map { try song($0) }
                player.startEchoFlow(from: seed)
                guard player.flowActive else { throw AIError.missing }
                try await verifyPlayback()
            } else { player.stopEchoFlow() }
        case "dj_mix": return try await mix(args)
        case "podcast_search":
            let term = args["query"] as? String ?? ""
            return try json(episodes.filter { $0.matches(term) }.prefix(30).map {
                ["id": $0.id, "title": String($0.title.prefix(180)), "show": String($0.show.title.prefix(150)),
                 "position": podcasts.state.listening[$0.id]?.position ?? 0, "downloaded": podcasts.localURL($0.id) != nil] as [String: Any]
            })
        case "podcast_action":
            guard let id = args["episodeID"] as? String, let episode = episodes.first(where: { $0.id == id }) else { throw AIError.missing }
            switch operation {
            case "play": player.playPodcast(episode); try await verifyPlayback()
            case "download":
                podcasts.download(episode)
                guard podcasts.state.pendingDownloads.contains(id) || podcasts.localURL(id) != nil else { throw AIError.storage }
                return try json(["status": podcasts.localURL(id) != nil ? "downloaded" : "download_scheduled"])
            case "cancelDownload": podcasts.cancelDownload(episode)
            case "subscribe": if podcasts.state.shows[episode.show.id] == nil { podcasts.toggleShow(episode.show) }
            case "unsubscribe": if podcasts.state.shows[episode.show.id] != nil { podcasts.toggleShow(episode.show) }
            default: throw AIError.invalidArguments
            }
        case "settings_change": try changeSetting(args)
        case "navigate":
            guard let screen = args["screen"] as? String, let tab = AppTab(rawValue: screen) else { throw AIError.invalidArguments }
            navigation = tab
            return try json(["status": "navigation_scheduled", "screen": screen])
        default: throw AIError.invalidArguments
        }
        return try json(["status": "completed", "action": call.name])
    }
    private var episodes: [PodcastEpisode] {
        var all = podcasts.state.episodes
        for feed in podcasts.state.cachedFeeds.values { for episode in feed { all[episode.id] = episode } }
        return all.values.sorted { $0.id < $1.id }
    }
    private func count(_ song: Song) -> Int { learning.learningData[song.id]?.playCount ?? 0 }
    private func metadata(_ song: Song) -> [String: Any] {
        ["id": song.id.uuidString, "title": String(song.title.prefix(160)), "artist": String(song.artist.prefix(120)),
         "album": String((song.album ?? "").prefix(120)), "genre": String((song.genre ?? "").prefix(80)),
         "plays": count(song), "favorite": library.isFavorite(song)]
    }
    private func song(_ value: Any?) throws -> Song {
        guard let value = value as? String, let id = UUID(uuidString: value), let song = library.song(withID: id) else { throw AIError.missing }
        return song
    }
    private func resolve(_ args: [String: Any], allowEmpty: Bool = false) throws -> [Song] {
        guard let values = args["songIDs"] as? [String], values.count <= 100, allowEmpty || !values.isEmpty,
              Set(values).count == values.count else { throw AIError.invalidArguments }
        return try values.map { try song($0) }
    }
    private func playlistIndex(_ args: [String: Any]) throws -> Int {
        guard let string = args["playlistID"] as? String, let id = UUID(uuidString: string),
              let index = library.playlists.firstIndex(where: { $0.id == id }) else { throw AIError.missing }
        return index
    }
    private func nonempty(_ value: Any?) throws -> String {
        guard let text = value as? String else { throw AIError.invalidArguments }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 150 else { throw AIError.invalidArguments }; return clean
    }
    private func json(_ value: Any) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8) ?? "{}"
    }
    private func play(_ songs: [Song], shuffle: Bool) async throws -> String {
        guard !songs.isEmpty else { throw AIError.missing }
        for song in songs { guard let url = player.getURL(for: song), FileManager.default.fileExists(atPath: url.path) else { throw AIError.missing } }
        let ordered = shuffle ? songs.shuffled() : songs
        player.stopEchoFlow(); player.setShuffle(false)
        player.play(song: ordered[0], url: player.getURL(for: ordered[0])!, queue: ordered)
        if shuffle { player.setShuffle(true) }
        try await verifyPlayback()
        return try json(["status": "playing", "song": metadata(ordered[0]), "count": songs.count])
    }
    private func verifyPlayback() async throws {
        let generation = player.playbackGeneration
        for _ in 0..<100 {
            try Task.checkCancellation()
            guard generation == player.playbackGeneration else { throw CancellationError() }
            if player.playbackErrorKey != nil || player.localPlaybackState == .failed { throw AIError.playback }
            if player.intelligencePlaybackConfirmed { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw AIError.playback
    }
    private func excludedMatch(_ song: Song, _ excluded: [String]) -> Bool {
        let metadata = [song.title, song.artist, song.genre ?? ""].joined(separator: " ")
        return excluded.contains { !$0.isEmpty && (song.id.uuidString == $0 || metadata.localizedStandardContains($0)) }
    }
    private func mix(_ args: [String: Any]) async throws -> String {
        var next = dj
        if let query = args["query"] as? String { next.query = query; next.selectedIDs = [] }
        if let excluded = args["exclude"] as? [String] { next.exclusions = excluded }
        if args["songIDs"] != nil { next.selectedIDs = try resolve(args).map(\.id) }
        let selection = Set(next.selectedIDs)
        let candidates = library.songs.filter { song in
            guard let url = player.getURL(for: song), FileManager.default.fileExists(atPath: url.path) else { return false }
            return AIDJSelection.admits(song, query: next.query, excluded: next.exclusions, selectedIDs: selection)
        }
        let ranked = learning.recommendations(from: candidates, favoriteSongIDs: library.favoriteSongIDs, limit: candidates.count)
        let chosen = AIDJSelection.preferUnplayed(ranked, recent: Set(next.recent), current: player.currentSong?.id, limit: args["limit"] as? Int ?? 30)
        guard !chosen.isEmpty else { throw AIError.missing }
        player.stopEchoFlow()
        if args["startNow"] as? Bool == true || player.currentSong == nil { _ = try await play(chosen, shuffle: false) }
        else { player.replaceIntelligenceUpcoming(chosen) }
        player.startEchoFlow(allowedSongIDs: Set(candidates.map(\.id)), preserveCurrent: true)
        next.recent = Array((next.recent + chosen.map(\.id)).suffix(100)); dj = next
        UserDefaults.standard.set(try JSONEncoder().encode(next), forKey: "echo.intelligence.dj.v1")
        return try json(["status": "dj_queue_updated", "count": chosen.count, "query": next.query, "excluded": next.exclusions])
    }
    private func changeSetting(_ args: [String: Any]) throws {
        guard let value = args["value"] as? String else { throw AIError.invalidArguments }
        switch args["setting"] as? String {
        case "appearance":
            guard ["system", "light", "dark", "custom"].contains(value) else { throw AIError.invalidArguments }
            EchoTheme.shared.mode = value
        case "equalizer":
            guard let preset = EqualizerPreset(rawValue: value), preset != .custom else { throw AIError.invalidArguments }
            EqualizerSettings.shared.select(preset); EqualizerSettings.shared.setEnabled(true)
        case "crossfade":
            guard let seconds = Double(value), seconds.isFinite, seconds == 0 || (1...12).contains(seconds) else { throw AIError.invalidArguments }
            UserDefaults.standard.set(seconds == 0 ? "direct" : "crossfade", forKey: AudioSettings.transitionKey)
            if seconds > 0 { UserDefaults.standard.set(seconds, forKey: AudioSettings.crossfadeKey) }
            NotificationCenter.default.post(name: AudioSettings.didChange, object: nil)
        case "mono":
            guard ["true", "false"].contains(value) else { throw AIError.invalidArguments }
            UserDefaults.standard.set(value == "true", forKey: AudioSettings.monoKey)
            NotificationCenter.default.post(name: AudioSettings.didChange, object: nil)
        default: throw AIError.invalidArguments
        }
    }
}
