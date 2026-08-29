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

    // Siri already knows the IDs.

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


    // Siri searches by spoken name.

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


    // Suggestions shown by Siri / Shortcuts.

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


    // MARK: Matching

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

            return 100
        }


        if title.hasPrefix(
            search
        ) {

            return 90
        }


        if title.contains(
            search
        ) {

            return 80
        }


        if artist ==
            search {

            return 70
        }


        if artist.contains(
            search
        ) {

            return 60
        }


        return 0
    }


    private func normalize(
        _ value: String
    ) -> String {

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


        return 0
    }


    private func normalize(
        _ value: String
    ) -> String {

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


            // Keep the exact playlist order.

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
// MARK: - Enable Shuffle
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
// MARK: - Disable Shuffle
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
// MARK: - Echo Siri Shortcuts
// ============================================================

struct EchoShortcuts:
    AppShortcutsProvider {

    static var appShortcuts:
        [AppShortcut] {

        // ----------------------------------------------------
        // Play Song
        // ----------------------------------------------------

        AppShortcut(

            intent:
                PlaySongIntent(),

            phrases: [

                "Speel \(\.$song) met \(.applicationName)",

                "Speel \(\.$song) in \(.applicationName)",

                "Start \(\.$song) met \(.applicationName)"
            ],

            shortTitle:
                "Speel nummer",

            systemImageName:
                "play.fill"
        )


        // ----------------------------------------------------
        // Play Playlist
        // ----------------------------------------------------

        AppShortcut(

            intent:
                PlayPlaylistIntent(),

            phrases: [

                "Speel playlist \(\.$playlist) met \(.applicationName)",

                "Speel \(\.$playlist) met \(.applicationName)"
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

                "Zet shuffle aan in \(.applicationName)",

                "Shuffle met \(.applicationName)"
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

                "Zet shuffle uit in \(.applicationName)"
            ],

            shortTitle:
                "Shuffle uit",

            systemImageName:
                "shuffle"
        )


        // ----------------------------------------------------
        // Repeat Current Song
        // ----------------------------------------------------

        AppShortcut(

            intent:
                RepeatCurrentSongIntent(),

            phrases: [

                "Herhaal dit nummer in \(.applicationName)",

                "Herhaal dit liedje in \(.applicationName)"
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

                "Herhaal alles in \(.applicationName)"
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

                "Stop herhalen in \(.applicationName)"
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
