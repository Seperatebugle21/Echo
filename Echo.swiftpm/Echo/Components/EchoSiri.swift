import Foundation
import AppIntents


// ============================================================
// MARK: - Errors
// ============================================================

enum EchoSiriError: Error, LocalizedError {

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
            return "Er speelt momenteel geen nummer."
        }
    }
}


// ============================================================
// MARK: - Artist Entity
// ============================================================

@available(iOS 26.0, *)
@AppEntity(schema: .audio.artist)
struct EchoArtistEntity {

    static let defaultQuery =
        EchoArtistQuery()

    let id: String

    var name: String


    init(
        name: String
    ) {

        self.id =
            name
                .folding(
                    options: [
                        .caseInsensitive,
                        .diacriticInsensitive
                    ],
                    locale: .current
                )
                .lowercased()

        self.name =
            name
    }


    var displayRepresentation:
        DisplayRepresentation {

        DisplayRepresentation(
            title: "\(name)"
        )
    }
}


// MARK: Artist Query

@available(iOS 26.0, *)
struct EchoArtistQuery:
    EntityQuery {

    func entities(
        for identifiers: [String]
    ) async throws -> [EchoArtistEntity] {

        await MainActor.run {

            let artists =
                Set(
                    MusicLibraryManager.shared
                        .songs
                        .map {
                            $0.artist
                        }
                )

            return artists
                .map {
                    EchoArtistEntity(
                        name: $0
                    )
                }
                .filter {
                    identifiers.contains(
                        $0.id
                    )
                }
        }
    }
}


// ============================================================
// MARK: - Song Entity
// ============================================================

@available(iOS 26.0, *)
@AppEntity(schema: .audio.song)
struct EchoSongEntity {

    static let defaultQuery =
        EchoSongQuery()


    let id: String


    // Required audio.song schema properties

    var title: String

    var artistName: String

    var composerName: String?

    var albumTitle: String?

    var artists:
        [EchoArtistEntity]

    var album:
        EchoAlbumEntity?

    var composers:
        [EchoArtistEntity]

    var internationalStandardRecordingCode:
        String?


    init(
        song: Song
    ) {

        id =
            song.id.uuidString

        title =
            song.title

        artistName =
            song.artist

        composerName =
            nil

        albumTitle =
            song.album

        artists = [
            EchoArtistEntity(
                name:
                    song.artist
            )
        ]

        if
            let albumName =
                song.album,
            !albumName.isEmpty {

            album =
                EchoAlbumEntity(
                    title:
                        albumName,
                    artist:
                        song.artist
                )

        } else {

            album =
                nil
        }

        composers =
            []

        internationalStandardRecordingCode =
            nil
    }


    var displayRepresentation:
        DisplayRepresentation {

        DisplayRepresentation(
            title:
                "\(title)",
            subtitle:
                "\(artistName)"
        )
    }
}


// ============================================================
// MARK: - Album Entity
// ============================================================

@available(iOS 26.0, *)
@AppEntity(schema: .audio.album)
struct EchoAlbumEntity {

    static let defaultQuery =
        EchoAlbumQuery()


    let id: String

    var title: String

    var artistName: String

    var artists:
        [EchoArtistEntity]

    var universalProductCode:
        String?


    init(
        title: String,
        artist: String
    ) {

        self.id =
            "\(artist)|\(title)"
                .folding(
                    options: [
                        .caseInsensitive,
                        .diacriticInsensitive
                    ],
                    locale:
                        .current
                )
                .lowercased()

        self.title =
            title

        self.artistName =
            artist

        self.artists = [
            EchoArtistEntity(
                name:
                    artist
            )
        ]

        self.universalProductCode =
            nil
    }


    var displayRepresentation:
        DisplayRepresentation {

        DisplayRepresentation(
            title:
                "\(title)",
            subtitle:
                "\(artistName)"
        )
    }
}


// MARK: Album Query

@available(iOS 26.0, *)
struct EchoAlbumQuery:
    EntityQuery {

    func entities(
        for identifiers: [String]
    ) async throws
        -> [EchoAlbumEntity] {

        await MainActor.run {

            var result:
                [EchoAlbumEntity] = []

            var seen =
                Set<String>()


            for song in
                MusicLibraryManager.shared.songs {

                guard
                    let album =
                        song.album,
                    !album.isEmpty

                else {

                    continue
                }


                let entity =
                    EchoAlbumEntity(
                        title:
                            album,
                        artist:
                            song.artist
                    )


                guard seen.insert(
                    entity.id
                ).inserted
                else {

                    continue
                }


                if identifiers.contains(
                    entity.id
                ) {

                    result.append(
                        entity
                    )
                }
            }


            return result
        }
    }
}


// ============================================================
// MARK: - Song Query
// ============================================================

@available(iOS 26.0, *)
struct EchoSongQuery:
    EntityQuery {

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
}


// ============================================================
// MARK: - Siri Audio Search
// ============================================================

@available(iOS 26.0, *)
extension EchoSongQuery:
    IntentValueQuery {

    func values(
        for audioSearch: AudioSearch
    ) async throws
        -> [EchoSongEntity] {

        switch audioSearch.criteria {

        // Siri understood an actual search.

        case .searchQuery(
            let query
        ):

            return await
                searchEchoLibrary(
                    query
                )


        // Example:
        //
        // "Speel muziek met Echo"
        //
        // Siri isn't requesting a particular song.

        case .unspecified:

            return await MainActor.run {

                Array(
                    MusicLibraryManager.shared
                        .songs
                        .sorted {

                            $0.lastPlayed ??
                                .distantPast
                            >
                            $1.lastPlayed ??
                                .distantPast
                        }
                        .prefix(
                            25
                        )
                )
                .map {

                    EchoSongEntity(
                        song:
                            $0
                    )
                }
            }


        // Echo doesn't currently expose permanent
        // public URLs for songs.

        case .url:

            return []
        }
    }


    // MARK: Search

    private func searchEchoLibrary(
        _ rawQuery: String
    ) async
        -> [EchoSongEntity] {

        let query =
            normalize(
                rawQuery
            )


        guard !query.isEmpty else {

            return []
        }


        return await MainActor.run {

            let songs =
                MusicLibraryManager.shared
                    .songs


            return songs
                .map {
                    song in

                    (
                        song:
                            song,

                        score:
                            score(
                                song:
                                    song,
                                query:
                                    query
                            )
                    )
                }

                .filter {

                    $0.score >
                        0
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


    // MARK: Matching

    private func score(
        song: Song,
        query: String
    ) -> Int {

        let title =
            normalize(
                song.title
            )

        let artist =
            normalize(
                song.artist
            )

        let album =
            normalize(
                song.album ??
                    ""
            )


        // Exact title

        if title ==
            query {

            return 1000
        }


        // Siri may send:
        // "every breath you take by the police"

        let combined =
            "\(title) \(artist)"


        if combined ==
            query {

            return 990
        }


        if
            query.contains(
                title
            ),
            query.contains(
                artist
            ) {

            return 950
        }


        if title.hasPrefix(
            query
        ) {

            return 900
        }


        if title.contains(
            query
        ) {

            return 850
        }


        if query.contains(
            title
        ) {

            return 825
        }


        if artist ==
            query {

            return 700
        }


        if artist.contains(
            query
        ) {

            return 650
        }


        if album ==
            query {

            return 600
        }


        if album.contains(
            query
        ) {

            return 550
        }


        // Check individual words.

        let queryWords =
            Set(
                query.split(
                    separator:
                        " "
                )
                .map(
                    String.init
                )
            )


        let songWords =
            Set(
                "\(title) \(artist)"
                    .split(
                        separator:
                            " "
                    )
                    .map(
                        String.init
                    )
            )


        let matches =
            queryWords
                .intersection(
                    songWords
                )
                .count


        if matches >= 2 {

            return
                300
                +
                (
                    matches
                    *
                    10
                )
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
                        .caseInsensitive,
                        .diacriticInsensitive
                    ],
                    locale:
                        .current
                )
                .lowercased()


        // Remove common Siri filler words.

        let removable = [

            "speel ",
            "play ",
            "nummer ",
            "liedje ",
            "song ",
            "met echo",
            "in echo",
            "via echo"
        ]


        for value in removable {

            result =
                result.replacingOccurrences(
                    of:
                        value,
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

@available(iOS 26.0, *)
@AppEntity(schema: .audio.playlist)
struct EchoPlaylistEntity {

    static let defaultQuery =
        EchoPlaylistQuery()


    let id: String


    // Required playlist schema field

    var title: String


    // Echo owns locally created playlists.

    var owner:
        EchoArtistEntity?

    var createdByMe:
        Bool?

    var curatedForMe:
        Bool?


    init(
        playlist: Playlist
    ) {

        id =
            playlist.id.uuidString

        title =
            playlist.name

        owner =
            nil

        createdByMe =
            true

        curatedForMe =
            false
    }


    var displayRepresentation:
        DisplayRepresentation {

        DisplayRepresentation(
            title:
                "\(title)"
        )
    }
}


// ============================================================
// MARK: - Playlist Query
// ============================================================

@available(iOS 26.0, *)
struct EchoPlaylistQuery:
    EntityQuery {

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
}


// ============================================================
// MARK: - Normal App Shortcut Play Song
//
// Keep this as fallback.
//
// This means Echo still works from Shortcuts even if Siri's
// newer media routing isn't available on a particular device.
// ============================================================

struct PlaySongIntent:
    AudioPlaybackIntent {

    static var title:
        LocalizedStringResource =
        "Speel nummer"


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
        song: EchoSongEntity
    ) {

        self.song =
            song
    }


    @MainActor
    func perform()
        async throws
        -> some IntentResult {

        guard
            let id =
                UUID(
                    uuidString:
                        song.id
                ),

            let found =
                MusicLibraryManager.shared
                    .songs
                    .first(
                        where: {

                            $0.id ==
                                id
                        }
                    )

        else {

            throw EchoSiriError
                .songNotFound
        }


        try play(
            song:
                found,

            queue:
                MusicLibraryManager.shared
                    .songs
        )


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


    @MainActor
    func perform()
        async throws
        -> some IntentResult {

        guard
            let id =
                UUID(
                    uuidString:
                        playlist.id
                ),

            let foundPlaylist =
                MusicLibraryManager.shared
                    .playlists
                    .first(
                        where: {

                            $0.id ==
                                id
                        }
                    )

        else {

            throw EchoSiriError
                .playlistNotFound
        }


        let songs =
            foundPlaylist.songIDs
                .compactMap {
                    songID in

                    MusicLibraryManager.shared
                        .songs
                        .first(
                            where: {

                                $0.id ==
                                    songID
                            }
                        )
                }


        guard let first =
            songs.first

        else {

            throw EchoSiriError
                .playlistEmpty
        }


        try play(
            song:
                first,

            queue:
                songs
        )


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


    @MainActor
    func perform()
        async throws
        -> some IntentResult {

        AudioPlayerManager.shared
            .setShuffle(
                true
            )


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


    @MainActor
    func perform()
        async throws
        -> some IntentResult {

        AudioPlayerManager.shared
            .setShuffle(
                false
            )


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


    @MainActor
    func perform()
        async throws
        -> some IntentResult {

        guard AudioPlayerManager.shared
            .currentSong != nil

        else {

            throw EchoSiriError
                .nothingPlaying
        }


        AudioPlayerManager.shared
            .setRepeatMode(
                .one
            )


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


    @MainActor
    func perform()
        async throws
        -> some IntentResult {

        AudioPlayerManager.shared
            .setRepeatMode(
                .all
            )


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


    @MainActor
    func perform()
        async throws
        -> some IntentResult {

        AudioPlayerManager.shared
            .setRepeatMode(
                .off
            )


        return .result()
    }
}


// ============================================================
// MARK: - Shared Playback
// ============================================================

@MainActor
private func play(
    song: Song,
    queue: [Song]
) throws {

    let library =
        MusicLibraryManager.shared


    guard FileManager.default
        .fileExists(
            atPath:
                library
                    .getURL(
                        for:
                            song
                    )
                    .path
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
            song,

        url:
            library.getURL(
                for:
                    song
            ),

        queue:
            queue
    )
}


// ============================================================
// MARK: - App Shortcuts
// ============================================================

struct EchoShortcuts:
    AppShortcutsProvider {

    static var appShortcuts:
        [AppShortcut] {

        AppShortcut(
            intent:
                PlaySongIntent(),

            phrases: [

                "Speel \(\.$song) met \(.applicationName)",

                "Speel \(\.$song) in \(.applicationName)"
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

                "Speel playlist \(\.$playlist) met \(.applicationName)",

                "Speel \(\.$playlist) met \(.applicationName)"
            ],

            shortTitle:
                "Speel playlist",

            systemImageName:
                "music.note.list"
        )


        AppShortcut(
            intent:
                EnableShuffleIntent(),

            phrases: [

                "Shuffle met \(.applicationName)",

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

                "Zet shuffle uit in \(.applicationName)"
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

                "Herhaal dit nummer in \(.applicationName)",

                "Herhaal dit liedje in \(.applicationName)"
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

                "Herhaal alles in \(.applicationName)"
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

                "Zet herhalen uit in \(.applicationName)"
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
