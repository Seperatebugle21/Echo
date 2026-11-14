import Foundation


/// Precomputed search data for the Search tab.
///
/// Built once per library change (`MusicLibraryManager.songRevision`) off the
/// main thread, so typing only has to compare the query against words that
/// are already case- and diacritic-folded.
struct LibrarySearchIndex: Sendable {

    struct SongEntry: Sendable {
        let song: Song
        let words: [String]
    }

    struct AlbumEntry: Sendable {
        let album: AlbumGroup
        let name: String
        let artist: String
    }


    let songRevision: UInt64?
    let songs: [SongEntry]
    let albumEntries: [AlbumEntry]

    var albums: [AlbumGroup] {
        albumEntries.map(\.album)
    }


    static let empty =
        LibrarySearchIndex(
            songRevision: nil,
            songs: [],
            albumEntries: []
        )


    private init(
        songRevision: UInt64?,
        songs: [SongEntry],
        albumEntries: [AlbumEntry]
    ) {
        self.songRevision = songRevision
        self.songs = songs
        self.albumEntries = albumEntries
    }


    init(
        songs: [Song],
        revision: UInt64
    ) {

        songRevision = revision

        self.songs = songs.map { song in
            SongEntry(
                song: song,
                words: FuzzySearch.normalizedWords(
                    [song.title, song.artist, song.album]
                )
            )
        }

        albumEntries = LibraryAlbums
            .groups(from: songs)
            .map { album in
                AlbumEntry(
                    album: album,
                    name: LibrarySearch.fold(album.name),
                    artist: LibrarySearch.fold(album.artist)
                )
            }
    }
}


/// The result of one search query.
struct LibrarySearchResults {

    /// The trimmed query these results belong to.
    let query: String
    let songs: [Song]
    let artists: [ArtistGroup]
    let albums: [AlbumGroup]
    let playlists: [Playlist]

    var isEmpty: Bool {
        songs.isEmpty
            && artists.isEmpty
            && albums.isEmpty
            && playlists.isEmpty
    }

    static let empty =
        LibrarySearchResults(
            query: "",
            songs: [],
            artists: [],
            albums: [],
            playlists: []
        )
}


enum LibrarySearch {

    /// Case- and diacritic-insensitive form used for "contains" matching.
    static func fold(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        .lowercased()
    }


    /// Runs the full search. Pure function, safe to call off the main
    /// thread. Stops early (returning partial results) when the calling
    /// task is cancelled because the user typed another character.
    static func search(
        _ query: String,
        in index: LibrarySearchIndex,
        artists: [ArtistGroup],
        playlists: [(playlist: Playlist, name: String)]
    ) -> LibrarySearchResults {

        let queryWords = FuzzySearch.words(in: query)
        let folded = fold(query)

        var songs: [Song] = []

        for entry in index.songs {

            if Task.isCancelled {
                break
            }

            if FuzzySearch.matches(
                queryWords: queryWords,
                candidateWords: entry.words
            ) {
                songs.append(entry.song)
            }
        }


        let matchingArtists =
            artists.filter {
                fold($0.name).contains(folded)
            }

        let albums =
            index.albumEntries
                .filter {
                    $0.name.contains(folded)
                        || $0.artist.contains(folded)
                }
                .map(\.album)

        let matchingPlaylists =
            playlists
                .filter {
                    fold($0.name).contains(folded)
                }
                .map(\.playlist)


        return LibrarySearchResults(
            query: query,
            songs: songs,
            artists: matchingArtists,
            albums: albums,
            playlists: matchingPlaylists
        )
    }
}
