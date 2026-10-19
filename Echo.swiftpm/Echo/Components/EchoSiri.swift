import Foundation
import AppIntents


// ============================================================
// MARK: - Errors
// ============================================================

enum EchoSiriError: LocalizedError {
    case songNotFound, playlistNotFound, playlistEmpty, audioFileMissing, nothingPlaying
    case localMusicRequired, operationFailed, commandNotUnderstood, invalidDuration

    var localizationKey: String {
        switch self {
        case .songNotFound: "siri_error_song"
        case .playlistNotFound: "siri_error_playlist"
        case .playlistEmpty: "siri_error_empty"
        case .audioFileMissing: "siri_error_audio"
        case .nothingPlaying: "siri_error_current"
        case .localMusicRequired: "siri_error_local"
        case .operationFailed: "siri_error_failed"
        case .commandNotUnderstood: "siri_error_command"
        case .invalidDuration: "siri_error_duration"
        }
    }
    var errorDescription: String? { EchoSiriText.string(localizationKey) }
}

// ============================================================
// MARK: - Fuzzy Siri Matcher
// ============================================================

enum EchoSiriMatcher {

    static func normalize(
        _ value: String
    ) -> String {

        let folded =
            value
                .folding(
                    options: [
                        .caseInsensitive,
                        .diacriticInsensitive
                    ],
                    locale: .current
                )
                .lowercased()


        let allowed =
            folded.map {
                character -> Character in

                if character.isLetter ||
                    character.isNumber ||
                    character == " " {

                    return character
                }

                return " "
            }


        return String(
            allowed
        )
        .split(
            whereSeparator: {
                $0.isWhitespace
            }
        )
        .joined(
            separator: " "
        )
    }


    static func cleanedRequest(_ value: String) -> String {
        // Siri already extracts the entity parameter. Stripping command words here
        // corrupts titles such as “Play That Song” and “Start Me Up”.
        normalize(value)
    }


    // ========================================================
    // MARK: - Generic Score
    // ========================================================

    static func score(
        candidate: String,
        query: String
    ) -> Int {

        let candidate =
            normalize(
                candidate
            )

        let query =
            cleanedRequest(
                query
            )


        guard
            !candidate.isEmpty,
            !query.isEmpty
        else {
            return 0
        }


        // Exact

        if candidate ==
            query {

            return 1000
        }


        // Prefix

        if candidate.hasPrefix(
            query
        ) {

            return 950
        }


        if query.hasPrefix(
            candidate
        ) {

            return 925
        }


        // Contains

        if candidate.contains(
            query
        ) {

            return 900
        }


        if query.contains(
            candidate
        ) {

            return 875
        }


        // Word overlap

        let candidateWords =
            Set(
                candidate.split(
                    separator: " "
                )
                .map(
                    String.init
                )
            )


        let queryWords =
            Set(
                query.split(
                    separator: " "
                )
                .map(
                    String.init
                )
            )


        let sharedWords =
            candidateWords
                .intersection(
                    queryWords
                )
                .count


        if sharedWords > 0 {

            let maximum =
                max(
                    candidateWords.count,
                    queryWords.count
                )


            if maximum > 0 {

                let ratio =
                    Double(
                        sharedWords
                    )
                    /
                    Double(
                        maximum
                    )


                if ratio >= 0.7 {

                    return
                        750
                        +
                        Int(
                            ratio * 100
                        )
                }
            }
        }


        // Typo / speech-recognition tolerance.

        let similarity =
            stringSimilarity(
                candidate,
                query
            )


        if similarity >= 0.88 {
            return 820
        }

        if similarity >= 0.80 {
            return 720
        }

        if similarity >= 0.72 {
            return 620
        }

        if similarity >= 0.64 &&
            min(
                candidate.count,
                query.count
            ) >= 8 {

            return 520
        }


        return 0
    }


    // ========================================================
    // MARK: - Song Score
    // ========================================================

    static func songScore(
        song: Song,
        query: String
    ) -> Int {

        let titleScore =
            score(
                candidate:
                    song.title,

                query:
                    query
            )


        let artistScore =
            score(
                candidate:
                    song.artist,

                query:
                    query
            )


        let combinedScore =
            score(
                candidate:
                    "\(song.title) \(song.artist)",

                query:
                    query
            )


        let reverseCombinedScore =
            score(
                candidate:
                    "\(song.artist) \(song.title)",

                query:
                    query
            )


        let albumScore =
            song.album.map {

                score(
                    candidate:
                        $0,

                    query:
                        query
                )
            }
            ??
            0


        return max(
            titleScore,
            artistScore - 100,
            combinedScore + 100,
            reverseCombinedScore + 75,
            albumScore - 150
        )
    }


    // ========================================================
    // MARK: - Levenshtein
    // ========================================================

    static func stringSimilarity(
        _ lhs: String,
        _ rhs: String
    ) -> Double {

        let a =
            Array(
                lhs
            )

        let b =
            Array(
                rhs
            )


        if a.isEmpty &&
            b.isEmpty {

            return 1
        }


        let maximumLength =
            max(
                a.count,
                b.count
            )


        guard maximumLength >
                0
        else {
            return 1
        }


        let distance =
            levenshteinDistance(
                a,
                b
            )


        return
            1
            -
            (
                Double(
                    distance
                )
                /
                Double(
                    maximumLength
                )
            )
    }


    static func levenshteinDistance(
        _ lhs: [Character],
        _ rhs: [Character]
    ) -> Int {

        if lhs.isEmpty {
            return rhs.count
        }

        if rhs.isEmpty {
            return lhs.count
        }


        var previous =
            Array(
                0...rhs.count
            )


        for lhsIndex in
            1...lhs.count {

            var current =
                Array(
                    repeating:
                        0,

                    count:
                        rhs.count + 1
                )


            current[0] =
                lhsIndex


            for rhsIndex in
                1...rhs.count {

                let insertion =
                    current[
                        rhsIndex - 1
                    ]
                    +
                    1


                let deletion =
                    previous[
                        rhsIndex
                    ]
                    +
                    1


                let replacement =
                    previous[
                        rhsIndex - 1
                    ]
                    +
                    (
                        lhs[
                            lhsIndex - 1
                        ]
                        ==
                        rhs[
                            rhsIndex - 1
                        ]
                        ? 0
                        : 1
                    )


                current[
                    rhsIndex
                ] =
                    min(
                        insertion,
                        deletion,
                        replacement
                    )
            }


            previous =
                current
        }


        return previous[
            rhs.count
        ]
    }
}


// ============================================================
// MARK: - Song Entity
// ============================================================

struct EchoSongEntity:
    AppEntity {

    static var typeDisplayRepresentation =
        TypeDisplayRepresentation(
            name:
                "siri_song"
        )


    static var defaultQuery =
        EchoSongQuery()


    let id:
        String


    @Property(
        title:
            "siri_title"
    )
    var title:
        String


    @Property(
        title:
            "siri_artist"
    )
    var artist:
        String


    init(
        id: String,
        title: String,
        artist: String
    ) {

        self.id =
            id

        self.title =
            title

        self.artist =
            artist
    }


    init(
        song: Song
    ) {

        id =
            song.id.uuidString

        title =
            song.title

        artist =
            song.artist
    }


    // Retain existing song UUIDs; playlist destinations use a separate namespace.
    var playlistID: UUID? {
        guard id.hasPrefix("playlist:") else { return nil }
        return UUID(uuidString: String(id.dropFirst("playlist:".count)))
    }

    init(playlist: Playlist) {
        id = "playlist:" + playlist.id.uuidString
        title = playlist.displayName()
        artist = EchoSiriText.string("siri_playlist")
    }

    var displayRepresentation:
        DisplayRepresentation {

        DisplayRepresentation(
            title:
                "\(title)",

            subtitle:
                "\(artist)"
        )
    }
}


// ============================================================
// MARK: - Song Query
// ============================================================

struct EchoSongQuery:
    EntityStringQuery {

    func entities(
        for identifiers: [String]
    ) async throws
        -> [EchoSongEntity] {

        await MainActor.run {
            let library = MusicLibraryManager.shared
            return identifiers.compactMap { identifier in
                if identifier.hasPrefix("playlist:"),
                   let id = UUID(uuidString: String(identifier.dropFirst("playlist:".count))),
                   let playlist = library.playlists.first(where: { $0.id == id }) {
                    return EchoSongEntity(playlist: playlist)
                }
                return library.songs.first(where: { $0.id.uuidString == identifier }).map { EchoSongEntity(song: $0) }
            }
        }
    }


    func entities(
        matching string: String
    ) async throws
        -> [EchoSongEntity] {

        let query =
            EchoSiriMatcher
                .cleanedRequest(
                    string
                )


        guard !query.isEmpty
        else {

            return []
        }


        return await MainActor.run {
            let library = MusicLibraryManager.shared
            // Resolve exact playlist names before allowing a similar song to match.
            // Include translated automatic names independently of Echo's UI language.
            let playlistPrefixes = ["playlist ", "afspeellijst ", "de playlist ", "de afspeellijst ", "the playlist ", "la playlist ", "liste de lecture ", "la liste de lecture ", "die playlist ", "wiedergabeliste ", "die wiedergabeliste "]
            let playlistQuery = playlistPrefixes.first(where: { query.hasPrefix($0) })
                .map { String(query.dropFirst($0.count)) }
            func matches(_ name: String) -> [Playlist] {
                library.playlists.filter { playlist in
                    let names = [playlist.name] + ["en", "nl", "fr", "de"].map { playlist.displayName(language: $0) }
                    return names.contains { EchoSiriMatcher.normalize($0) == name }
                }
            }
            let playlists = matches(query)
            if !playlists.isEmpty { return playlists.map { EchoSongEntity(playlist: $0) } }
            if let playlistQuery {
                // An explicit playlist request must never fall back to a song.
                return matches(playlistQuery).map { EchoSongEntity(playlist: $0) }
            }


            return MusicLibraryManager.shared
                .songs
                .map {
                    song in


                    (
                        song:
                            song,

                        score:
                            EchoSiriMatcher
                                .songScore(
                                    song:
                                        song,

                                    query:
                                        query
                                )
                    )
                }
                .filter {

                    $0.score >=
                        500
                }
                .sorted {

                    $0.score >
                        $1.score
                }
                .prefix(
                    25
                )
                .map {

                    EchoSongEntity(
                        song:
                            $0.song
                    )
                }
        }
    }


    func suggestedEntities() async throws -> [EchoSongEntity] {
        await MainActor.run {
            let library = MusicLibraryManager.shared
            return library.playlists.prefix(25).map { EchoSongEntity(playlist: $0) }
                + library.songs.prefix(25).map { EchoSongEntity(song: $0) }
        }
    }
}


// ============================================================
// MARK: - Playlist Entity
// ============================================================

struct EchoPlaylistEntity:
    AppEntity {

    static var typeDisplayRepresentation =
        TypeDisplayRepresentation(
            name:
                "siri_playlist"
        )


    static var defaultQuery =
        EchoPlaylistQuery()


    let id:
        String


    @Property(
        title:
            "siri_name"
    )
    var name:
        String


    init(
        id: String,
        name: String
    ) {

        self.id =
            id

        self.name =
            name
    }


    init(
        playlist: Playlist
    ) {

        id =
            playlist.id.uuidString

        name =
            playlist.displayName()
    }


    var displayRepresentation:
        DisplayRepresentation {

        DisplayRepresentation(
            title:
                "\(name)"
        )
    }
}


// ============================================================
// MARK: - Playlist Query
// ============================================================

struct EchoPlaylistQuery:
    EntityStringQuery {

    func entities(
        for identifiers: [String]
    ) async throws
        -> [EchoPlaylistEntity] {

        await MainActor.run {

            MusicLibraryManager.shared
                .playlists
                .filter {

                    identifiers.contains(
                        $0.id.uuidString
                    )
                }
                .map {

                    EchoPlaylistEntity(
                        playlist:
                            $0
                    )
                }
        }
    }


    func entities(
        matching string: String
    ) async throws
        -> [EchoPlaylistEntity] {

        let query =
            EchoSiriMatcher
                .cleanedRequest(
                    string
                )


        guard !query.isEmpty
        else {

            return []
        }


        return await MainActor.run {

            MusicLibraryManager.shared
                .playlists
                .map {
                    playlist in


                    (
                        playlist:
                            playlist,

                        score:
                            ([playlist.name] + ["en", "nl", "fr", "de"].map { playlist.displayName(language: $0) })
                                .map { EchoSiriMatcher.score(candidate: $0, query: query) }
                                .max() ?? 0
                    )
                }
                .filter {

                    $0.score >=
                        500
                }
                .sorted {

                    $0.score >
                        $1.score
                }
                .prefix(
                    25
                )
                .map {

                    EchoPlaylistEntity(
                        playlist:
                            $0.playlist
                    )
                }
        }
    }


    func suggestedEntities()
        async throws
        -> [EchoPlaylistEntity] {

        await MainActor.run {

            MusicLibraryManager.shared
                .playlists
                .map {

                    EchoPlaylistEntity(
                        playlist:
                            $0
                    )
                }
        }
    }
}


// ============================================================
// MARK: - Play Song
// ============================================================

struct PlaySongIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "siri_play_song_title"


    static var description =
        IntentDescription(
            "siri_play_song_description"
        )


    static var openAppWhenRun =
        false


    @Parameter(
        title:
            "siri_song"
    )
    var song:
        EchoSongEntity


    init() {}


    init(
        song: EchoSongEntity
    ) {

        self.song =
            song
    }


    func perform()
        async throws
        -> some IntentResult {

        if let playlistID = song.playlistID {
            try await MainActor.run { try EchoSiriPlayback.playPlaylist(id: playlistID) }
            return .result()
        }

        guard let uuid =
            UUID(
                uuidString:
                    song.id
            )
        else {

            throw EchoSiriError
                .songNotFound
        }


        try await MainActor.run {

            let library =
                MusicLibraryManager.shared


            guard let found =
                library.songs
                    .first(
                        where: {

                            $0.id ==
                                uuid
                        }
                    )
            else {

                throw EchoSiriError
                    .songNotFound
            }


            guard
                let url =
                    library.getURL(
                        for:
                            found
                    ),

                FileManager.default
                    .fileExists(
                        atPath:
                            url.path
                    )
            else {

                throw EchoSiriError
                    .audioFileMissing
            }


            let audio =
                AudioPlayerManager.shared


            audio.allSongs =
                library.songs


            audio.play(
                song:
                    found,

                url:
                    url,

                queue:
                    library.songs
            )
        }


        return .result()
    }
}


// ============================================================
// MARK: - Play Playlist
// ============================================================

struct PlayPlaylistIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "siri_play_playlist_title"


    static var description =
        IntentDescription(
            "siri_play_playlist_description"
        )


    static var openAppWhenRun =
        false


    @Parameter(
        title:
            "siri_playlist"
    )
    var playlist:
        EchoPlaylistEntity


    init() {}


    init(
        playlist:
            EchoPlaylistEntity
    ) {

        self.playlist =
            playlist
    }


    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: playlist.id) else { throw EchoSiriError.playlistNotFound }
        try await MainActor.run { try EchoSiriPlayback.playPlaylist(id: id) }
        return .result()
    }
}

@MainActor
private enum EchoSiriPlayback {
    static func playPlaylist(id: UUID) throws {
        let library = MusicLibraryManager.shared
        guard let playlist = library.playlists.first(where: { $0.id == id }) else {
            throw EchoSiriError.playlistNotFound
        }
        let songs = library.songs(in: playlist).filter { song in
            library.getURL(for: song).map { FileManager.default.fileExists(atPath: $0.path) } == true
        }
        guard let first = songs.first, let url = library.getURL(for: first) else {
            throw EchoSiriError.playlistEmpty
        }
        let audio = AudioPlayerManager.shared
        audio.allSongs = library.songs
        audio.play(song: first, url: url, queue: songs)
    }
}


// ============================================================
// MARK: - Play Favorites
// ============================================================

struct PlayFavoritesIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "siri_play_favorites_title"


    static var description =
        IntentDescription(
            "siri_favorites_description"
        )


    static var openAppWhenRun =
        false


    func perform()
        async throws
        -> some IntentResult {

        try await MainActor.run {

            let library =
                MusicLibraryManager.shared

            let songs =
                library.favoriteSongs


            guard
                let first = songs.first,
                let url =
                    library.getURL(
                        for: first
                    )
            else {

                throw EchoSiriError
                    .playlistEmpty
            }


            let audio =
                AudioPlayerManager.shared


            audio.allSongs =
                library.songs


            audio.play(
                song: first,
                url: url,
                queue: songs
            )
        }


        return .result()
    }
}


// ============================================================
// MARK: - Shuffle
// ============================================================

struct EnableShuffleIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "siri_shuffle_on_title"


    static var openAppWhenRun =
        false


    func perform()
        async throws
        -> some IntentResult {

        await MainActor.run {

            AudioPlayerManager.shared
                .setShuffle(
                    true
                )
        }


        return .result()
    }
}


struct DisableShuffleIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "siri_shuffle_off_title"


    static var openAppWhenRun =
        false


    func perform()
        async throws
        -> some IntentResult {

        await MainActor.run {

            AudioPlayerManager.shared
                .setShuffle(
                    false
                )
        }


        return .result()
    }
}


// ============================================================
// MARK: - Repeat
// ============================================================

struct RepeatCurrentSongIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "siri_repeat_one_title"


    static var openAppWhenRun =
        false


    func perform()
        async throws
        -> some IntentResult {

        try await MainActor.run {

            let audio =
                AudioPlayerManager.shared


            guard audio.currentSong !=
                    nil
            else {

                throw EchoSiriError
                    .nothingPlaying
            }


            audio.setRepeatMode(
                .one
            )
        }


        return .result()
    }
}


struct RepeatAllIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "siri_repeat_all_title"


    static var openAppWhenRun =
        false


    func perform()
        async throws
        -> some IntentResult {

        await MainActor.run {

            AudioPlayerManager.shared
                .setRepeatMode(
                    .all
                )
        }


        return .result()
    }
}


struct DisableRepeatIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "siri_repeat_off_title"


    static var openAppWhenRun =
        false


    func perform()
        async throws
        -> some IntentResult {

        await MainActor.run {

            AudioPlayerManager.shared
                .setRepeatMode(
                    .off
                )
        }


        return .result()
    }
}


// ============================================================
// MARK: - Shortcuts
// ============================================================

struct EchoShortcuts: AppShortcutsProvider {
    // Apple's limit is ten automatically discoverable App Shortcuts. Additional
    // intents remain available as actions in Shortcuts, including free-form commands.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlaySongIntent(), phrases: [
            "Play \(\.$song) in \(.applicationName)",
            "Start \(\.$song) with \(.applicationName)"
        ], shortTitle: "siri_play_song_title", systemImageName: "play.fill")
        AppShortcut(intent: PlayPlaylistIntent(), phrases: [
            "Play playlist \(\.$playlist) in \(.applicationName)",
            "Start playlist \(\.$playlist) with \(.applicationName)"
        ], shortTitle: "siri_play_playlist_title", systemImageName: "music.note.list")
        AppShortcut(intent: PlayFavoritesIntent(), phrases: [
            "Play favorites in \(.applicationName)",
            "Play my favorites with \(.applicationName)"
        ], shortTitle: "siri_play_favorites_title", systemImageName: "heart.fill")
        AppShortcut(intent: EnableShuffleIntent(), phrases: [
            "Shuffle in \(.applicationName)",
            "Shuffle this song in \(.applicationName)",
            "Turn shuffle on in \(.applicationName)"
        ], shortTitle: "siri_shuffle_on_title", systemImageName: "shuffle")
        AppShortcut(intent: DisableShuffleIntent(), phrases: [
            "Turn shuffle off in \(.applicationName)",
            "Disable shuffle in \(.applicationName)"
        ], shortTitle: "siri_shuffle_off_title", systemImageName: "shuffle")
        AppShortcut(intent: RepeatCurrentSongIntent(), phrases: [
            "Repeat this song in \(.applicationName)",
            "Loop this track in \(.applicationName)"
        ], shortTitle: "siri_repeat_one_title", systemImageName: "repeat.1")
        AppShortcut(intent: RepeatAllIntent(), phrases: [
            "Repeat all in \(.applicationName)"
        ], shortTitle: "siri_repeat_all_title", systemImageName: "repeat")
        AppShortcut(intent: DisableRepeatIntent(), phrases: [
            "Stop repeating in \(.applicationName)",
            "Turn repeat off in \(.applicationName)"
        ], shortTitle: "siri_repeat_off_title", systemImageName: "repeat")
        AppShortcut(intent: StartEchoFlowIntent(), phrases: [
            "Start flow in \(.applicationName)",
            "Start flow from this song in \(.applicationName)",
            "Flow with \(.applicationName)"
        ], shortTitle: "siri_flow_title", systemImageName: "waveform")
        AppShortcut(intent: FavoriteCurrentSongIntent(), phrases: [
            "Favorite this song in \(.applicationName)",
            "Like this song in \(.applicationName)"
        ], shortTitle: "siri_favorite_title", systemImageName: "heart")
    }
    static var shortcutTileColor: ShortcutTileColor = .red
}
