import Foundation
import AppIntents


// ============================================================
// MARK: - Errors
// ============================================================

enum EchoSiriError: LocalizedError {

    case songNotFound
    case playlistNotFound
    case playlistEmpty
    case audioFileMissing
    case nothingPlaying

    var errorDescription: String? {

        switch self {

        case .songNotFound:
            return "Ik kan dat nummer niet vinden in Echo."

        case .playlistNotFound:
            return "Ik kan die playlist niet vinden in Echo."

        case .playlistEmpty:
            return "Die playlist bevat geen nummers."

        case .audioFileMissing:
            return "Het audiobestand kon niet worden gevonden."

        case .nothingPlaying:
            return "Er speelt momenteel geen nummer in Echo."
        }
    }
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


    static func cleanedRequest(
        _ value: String
    ) -> String {

        var result =
            normalize(
                value
            )


        let removable = [

            "speel ",
            "play ",
            "start ",
            "nummer ",
            "liedje ",
            "song ",
            "playlist ",
            "afspeellijst ",
            "met echo",
            "op echo",
            "in echo",
            "via echo"
        ]


        for word in removable {

            result =
                result.replacingOccurrences(
                    of: word,
                    with: ""
                )
        }


        return normalize(
            result
        )
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
                "Nummer"
        )


    static var defaultQuery =
        EchoSongQuery()


    let id:
        String


    @Property(
        title:
            "Titel"
    )
    var title:
        String


    @Property(
        title:
            "Artiest"
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

            MusicLibraryManager.shared
                .songs
                .filter {

                    identifiers.contains(
                        $0.id.uuidString
                    )
                }
                .map {

                    EchoSongEntity(
                        song:
                            $0
                    )
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

            MusicLibraryManager.shared
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


    func suggestedEntities()
        async throws
        -> [EchoSongEntity] {

        await MainActor.run {

            Array(
                MusicLibraryManager.shared
                    .songs
                    .prefix(
                        50
                    )
            )
            .map {

                EchoSongEntity(
                    song:
                        $0
                )
            }
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
                "Playlist"
        )


    static var defaultQuery =
        EchoPlaylistQuery()


    let id:
        String


    @Property(
        title:
            "Naam"
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
            playlist.name
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
                            EchoSiriMatcher
                                .score(
                                    candidate:
                                        playlist.name,

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
        "Speel nummer"


    static var description =
        IntentDescription(
            "Speelt een nummer uit je Echo-bibliotheek."
        )


    static var openAppWhenRun =
        false


    @Parameter(
        title:
            "Nummer"
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
        "Speel playlist"


    static var description =
        IntentDescription(
            "Speelt een playlist uit Echo."
        )


    static var openAppWhenRun =
        false


    @Parameter(
        title:
            "Playlist"
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


    func perform()
        async throws
        -> some IntentResult {

        guard let uuid =
            UUID(
                uuidString:
                    playlist.id
            )
        else {

            throw EchoSiriError
                .playlistNotFound
        }


        try await MainActor.run {

            let library =
                MusicLibraryManager.shared


            guard let foundPlaylist =
                library.playlists
                    .first(
                        where: {

                            $0.id ==
                                uuid
                        }
                    )
            else {

                throw EchoSiriError
                    .playlistNotFound
            }


            let songs =
                foundPlaylist.songIDs
                    .compactMap {
                        id in

                        library.songs
                            .first(
                                where: {

                                    $0.id ==
                                        id
                                }
                            )
                    }


            guard
                let first =
                    songs.first,

                let url =
                    library.getURL(
                        for:
                            first
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
                song:
                    first,

                url:
                    url,

                queue:
                    songs
            )
        }


        return .result()
    }
}


// ============================================================
// MARK: - Play Favorites
// ============================================================

struct PlayFavoritesIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "Speel favorieten"


    static var description =
        IntentDescription(
            "Speelt je favoriete nummers in Echo."
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
        "Shuffle aan"


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
        "Shuffle uit"


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
        "Herhaal dit nummer"


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
        "Herhaal alles"


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
        "Herhalen uit"


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

struct EchoShortcuts:
    AppShortcutsProvider {

    static var appShortcuts:
        [AppShortcut] {

        AppShortcut(
            intent:
                PlaySongIntent(),

            phrases: [

                "Speel \(\.$song) op \(.applicationName)",

                "Speel \(\.$song) met \(.applicationName)",

                "Speel \(\.$song) in \(.applicationName)",

                "Start \(\.$song) op \(.applicationName)",

                "Speel nummer \(\.$song) op \(.applicationName)"
            ],

            shortTitle:
                "Speel nummer",

            systemImageName:
                "play.fill"
        )


        AppShortcut(
            intent:
                PlayPlaylistIntent(),

            phrases: [

                "Speel playlist \(\.$playlist) op \(.applicationName)",

                "Speel playlist \(\.$playlist) met \(.applicationName)",

                "Speel \(\.$playlist) op \(.applicationName)",

                "Start playlist \(\.$playlist) op \(.applicationName)"
            ],

            shortTitle:
                "Speel playlist",

            systemImageName:
                "music.note.list"
        )


        AppShortcut(
            intent:
                PlayFavoritesIntent(),

            phrases: [

                "Speel favorieten op \(.applicationName)",

                "Speel mijn favorieten op \(.applicationName)",

                "Start favorieten in \(.applicationName)"
            ],

            shortTitle:
                "Speel favorieten",

            systemImageName:
                "heart.fill"
        )


        AppShortcut(
            intent:
                EnableShuffleIntent(),

            phrases: [

                "Shuffle op \(.applicationName)",

                "Zet shuffle aan op \(.applicationName)",

                "Zet shuffle aan in \(.applicationName)"
            ],

            shortTitle:
                "Shuffle aan",

            systemImageName:
                "shuffle"
        )


        AppShortcut(
            intent:
                DisableShuffleIntent(),

            phrases: [

                "Zet shuffle uit op \(.applicationName)",

                "Shuffle uit op \(.applicationName)"
            ],

            shortTitle:
                "Shuffle uit",

            systemImageName:
                "shuffle"
        )


        AppShortcut(
            intent:
                RepeatCurrentSongIntent(),

            phrases: [

                "Herhaal dit nummer op \(.applicationName)",

                "Herhaal dit liedje op \(.applicationName)",

                "Zet dit nummer op repeat in \(.applicationName)"
            ],

            shortTitle:
                "Herhaal nummer",

            systemImageName:
                "repeat.1"
        )


        AppShortcut(
            intent:
                RepeatAllIntent(),

            phrases: [

                "Herhaal alles op \(.applicationName)",

                "Zet repeat aan op \(.applicationName)"
            ],

            shortTitle:
                "Herhaal alles",

            systemImageName:
                "repeat"
        )


        AppShortcut(
            intent:
                DisableRepeatIntent(),

            phrases: [

                "Zet herhalen uit op \(.applicationName)",

                "Stop herhalen op \(.applicationName)",

                "Zet repeat uit op \(.applicationName)"
            ],

            shortTitle:
                "Herhalen uit",

            systemImageName:
                "repeat"
        )
    }


    static var shortcutTileColor:
        ShortcutTileColor =
        .red
}
