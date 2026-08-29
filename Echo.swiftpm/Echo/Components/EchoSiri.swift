import Foundation
import AppIntents


// ============================================================
// MARK: - Siri Errors
// ============================================================

enum EchoSiriError:
    LocalizedError {

    case songNotFound
    case playlistNotFound
    case playlistEmpty
    case audioFileMissing
    case nothingPlaying


    var errorDescription:
        String? {

        switch self {

        case .songNotFound:

            return
                "Ik kan dat nummer niet vinden in Echo."


        case .playlistNotFound:

            return
                "Ik kan die playlist niet vinden in Echo."


        case .playlistEmpty:

            return
                "Die playlist bevat geen nummers."


        case .audioFileMissing:

            return
                "Het audiobestand van dat nummer kon niet worden gevonden."


        case .nothingPlaying:

            return
                "Er speelt momenteel geen nummer in Echo."
        }
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

        self.id =
            song.id.uuidString

        self.title =
            song.title

        self.artist =
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
        for identifiers:
            [String]
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

        let search =
            normalize(
                string
            )


        return await MainActor.run {

            MusicLibraryManager.shared
                .songs
                .filter {
                    song in


                    let title =
                        normalize(
                            song.title
                        )


                    let artist =
                        normalize(
                            song.artist
                        )


                    return
                        title.contains(
                            search
                        )
                        ||
                        artist.contains(
                            search
                        )
                        ||
                        search.contains(
                            title
                        )
                }
                .sorted {
                    left,
                    right in


                    score(
                        song:
                            left,
                        search:
                            search
                    )
                    >
                    score(
                        song:
                            right,
                        search:
                            search
                    )
                }
                .prefix(
                    25
                )
                .map {

                    EchoSongEntity(
                        song:
                            $0
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


    // MARK: - Search Score

    private func score(
        song: Song,
        search: String
    ) -> Int {

        let title =
            normalize(
                song.title
            )


        let artist =
            normalize(
                song.artist
            )


        if title ==
            search {

            return 1000
        }


        let combination =
            "\(title) \(artist)"


        if combination ==
            search {

            return 950
        }


        if
            search.contains(
                title
            ),
            search.contains(
                artist
            ) {

            return 925
        }


        if title.hasPrefix(
            search
        ) {

            return 900
        }


        if title.contains(
            search
        ) {

            return 850
        }


        if search.contains(
            title
        ) {

            return 825
        }


        if artist ==
            search {

            return 700
        }


        if artist.contains(
            search
        ) {

            return 650
        }


        return 0
    }


    private func normalize(
        _ value: String
    ) -> String {

        var result =
            value
                .folding(
                    options: [
                        .diacriticInsensitive,
                        .caseInsensitive
                    ],

                    locale:
                        .current
                )
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .lowercased()


        let removableWords = [

            "speel ",
            "play ",
            "nummer ",
            "liedje ",
            "song ",
            "met echo",
            "in echo",
            "via echo"
        ]


        for word in removableWords {

            result =
                result.replacingOccurrences(
                    of:
                        word,

                    with:
                        ""
                )
        }


        return result
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
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

        self.id =
            playlist.id.uuidString

        self.name =
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
        for identifiers:
            [String]
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

        let search =
            normalize(
                string
            )


        return await MainActor.run {

            MusicLibraryManager.shared
                .playlists
                .filter {

                    normalize(
                        $0.name
                    )
                    .contains(
                        search
                    )
                    ||
                    search.contains(
                        normalize(
                            $0.name
                        )
                    )
                }
                .sorted {
                    left,
                    right in


                    playlistScore(
                        left.name,

                        search:
                            search
                    )
                    >
                    playlistScore(
                        right.name,

                        search:
                            search
                    )
                }
                .prefix(
                    25
                )
                .map {

                    EchoPlaylistEntity(
                        playlist:
                            $0
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


    private func playlistScore(
        _ value: String,
        search: String
    ) -> Int {

        let value =
            normalize(
                value
            )


        if value ==
            search {

            return 100
        }


        if value.hasPrefix(
            search
        ) {

            return 90
        }


        if value.contains(
            search
        ) {

            return 80
        }


        if search.contains(
            value
        ) {

            return 75
        }


        return 0
    }


    private func normalize(
        _ value: String
    ) -> String {

        var result =
            value
                .folding(
                    options: [
                        .diacriticInsensitive,
                        .caseInsensitive
                    ],

                    locale:
                        .current
                )
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .lowercased()


        let removableWords = [

            "speel ",
            "play ",
            "playlist ",
            "afspeellijst ",
            "met echo",
            "in echo",
            "via echo"
        ]


        for word in removableWords {

            result =
                result.replacingOccurrences(
                    of:
                        word,

                    with:
                        ""
                )
        }


        return result
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
    }
}


// ============================================================
// MARK: - Play Song Intent
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


    static var openAppWhenRun:
        Bool =
        false


    @Parameter(
        title:
            "Nummer"
    )
    var song:
        EchoSongEntity


    init() {}


    init(
        song:
            EchoSongEntity
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


            let audio =
                AudioPlayerManager.shared


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


            guard let url =
                library.getURL(
                    for:
                        found
                )

            else {

                throw EchoSiriError
                    .audioFileMissing
            }


            guard FileManager.default
                .fileExists(
                    atPath:
                        url.path
                )

            else {

                throw EchoSiriError
                    .audioFileMissing
            }


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
// MARK: - Play Playlist Intent
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


    static var openAppWhenRun:
        Bool =
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


            let audio =
                AudioPlayerManager.shared


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


            let playlistSongs =
                foundPlaylist.songIDs
                    .compactMap {
                        songID in


                        library.songs
                            .first(
                                where: {

                                    $0.id ==
                                        songID
                                }
                            )
                    }


            guard let firstSong =
                playlistSongs.first

            else {

                throw EchoSiriError
                    .playlistEmpty
            }


            guard let url =
                library.getURL(
                    for:
                        firstSong
                )

            else {

                throw EchoSiriError
                    .audioFileMissing
            }


            guard FileManager.default
                .fileExists(
                    atPath:
                        url.path
                )

            else {

                throw EchoSiriError
                    .audioFileMissing
            }


            audio.allSongs =
                library.songs


            audio.play(
                song:
                    firstSong,

                url:
                    url,

                queue:
                    playlistSongs
            )
        }


        return .result()
    }
}


// ============================================================
// MARK: - Shuffle On
// ============================================================

struct EnableShuffleIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "Shuffle aan"


    static var openAppWhenRun:
        Bool =
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


// ============================================================
// MARK: - Shuffle Off
// ============================================================

struct DisableShuffleIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "Shuffle uit"


    static var openAppWhenRun:
        Bool =
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
// MARK: - Repeat Current Song
// ============================================================

struct RepeatCurrentSongIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "Herhaal dit nummer"


    static var openAppWhenRun:
        Bool =
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


// ============================================================
// MARK: - Repeat All
// ============================================================

struct RepeatAllIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "Herhaal alles"


    static var openAppWhenRun:
        Bool =
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


// ============================================================
// MARK: - Repeat Off
// ============================================================

struct DisableRepeatIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "Herhalen uit"


    static var openAppWhenRun:
        Bool =
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
// MARK: - Echo Shortcuts
// ============================================================

struct EchoShortcuts:
    AppShortcutsProvider {

    static var appShortcuts:
        [AppShortcut] {

        // ----------------------------------------------------
        // Song
        // ----------------------------------------------------

        AppShortcut(

            intent:
                PlaySongIntent(),

            phrases: [

                "Speel \(\.$song) met \(.applicationName)",

                "Speel \(\.$song) in \(.applicationName)",

                "Speel nummer \(\.$song) met \(.applicationName)",

                "Start \(\.$song) met \(.applicationName)"
            ],

            shortTitle:
                "Speel nummer",

            systemImageName:
                "play.fill"
        )


        // ----------------------------------------------------
        // Playlist
        // ----------------------------------------------------

        AppShortcut(

            intent:
                PlayPlaylistIntent(),

            phrases: [

                "Speel playlist \(\.$playlist) met \(.applicationName)",

                "Speel playlist \(\.$playlist) in \(.applicationName)",

                "Speel \(\.$playlist) met \(.applicationName)",

                "Start playlist \(\.$playlist) met \(.applicationName)"
            ],

            shortTitle:
                "Speel playlist",

            systemImageName:
                "music.note.list"
        )


        // ----------------------------------------------------
        // Shuffle On
        // ----------------------------------------------------

        AppShortcut(

            intent:
                EnableShuffleIntent(),

            phrases: [

                "Shuffle met \(.applicationName)",

                "Zet shuffle aan in \(.applicationName)",

                "Shuffle aan in \(.applicationName)"
            ],

            shortTitle:
                "Shuffle aan",

            systemImageName:
                "shuffle"
        )


        // ----------------------------------------------------
        // Shuffle Off
        // ----------------------------------------------------

        AppShortcut(

            intent:
                DisableShuffleIntent(),

            phrases: [

                "Zet shuffle uit in \(.applicationName)",

                "Shuffle uit in \(.applicationName)"
            ],

            shortTitle:
                "Shuffle uit",

            systemImageName:
                "shuffle"
        )


        // ----------------------------------------------------
        // Repeat Current
        // ----------------------------------------------------

        AppShortcut(

            intent:
                RepeatCurrentSongIntent(),

            phrases: [

                "Herhaal dit nummer in \(.applicationName)",

                "Herhaal dit liedje in \(.applicationName)",

                "Zet dit nummer op repeat in \(.applicationName)"
            ],

            shortTitle:
                "Herhaal nummer",

            systemImageName:
                "repeat.1"
        )


        // ----------------------------------------------------
        // Repeat All
        // ----------------------------------------------------

        AppShortcut(

            intent:
                RepeatAllIntent(),

            phrases: [

                "Herhaal alles in \(.applicationName)",

                "Zet repeat aan in \(.applicationName)"
            ],

            shortTitle:
                "Herhaal alles",

            systemImageName:
                "repeat"
        )


        // ----------------------------------------------------
        // Repeat Off
        // ----------------------------------------------------

        AppShortcut(

            intent:
                DisableRepeatIntent(),

            phrases: [

                "Zet herhalen uit in \(.applicationName)",

                "Stop herhalen in \(.applicationName)",

                "Zet repeat uit in \(.applicationName)"
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
