import Foundation

struct AlbumGroup: Identifiable {
    var id: String { LibraryAlbumDestination(name: name, artist: artist).identity }
    let name: String
    let artist: String
    let songs: [Song]
}

enum LibraryAlbums {
    static func contains(_ song: Song, in album: LibraryAlbumDestination) -> Bool {
        destinations(for: song).contains { $0.identity == album.identity }
    }

    /// Reuses library identities and leaves file tags, artist credits and playlist links intact.
    @discardableResult
    static func add(_ songIDs: [UUID], to album: LibraryAlbumDestination, songs: inout [Song]) -> Int {
        guard !album.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        let requested = Set(songIDs)
        let members = songs.filter { contains($0, in: album) }
        var memberIDs = Set(members.map(\.id))
        var recordings = Set(members.map { LibrarySongMatchIndex.Key(title: $0.title, artist: $0.artist) })
        var added = 0
        for index in songs.indices where requested.contains(songs[index].id) {
            let song = songs[index]
            let recording = LibrarySongMatchIndex.Key(title: song.title, artist: song.artist)
            guard song.podcastEpisodeID == nil, !memberIDs.contains(song.id), !recordings.contains(recording) else { continue }
            songs[index].additionalAlbums = LibraryAlbumDestination.unique((song.additionalAlbums ?? []) + [album])
            memberIDs.insert(song.id)
            recordings.insert(recording)
            added += 1
        }
        return added
    }

    private static func destinations(for song: Song) -> [LibraryAlbumDestination] {
        guard song.podcastEpisodeID == nil else { return [] }
        let original = song.album.map { LibraryAlbumDestination(name: $0, artist: song.artist) }
        return LibraryAlbumDestination.unique([original].compactMap { $0 } + (song.additionalAlbums ?? []))
    }

    static func groups(from songs: [Song]) -> [AlbumGroup] {
        struct Group {
            let destination: LibraryAlbumDestination
            var tracks: [Song] = []
            var songIDs: Set<UUID> = []
            var recordings: Set<LibrarySongMatchIndex.Key> = []
        }
        var albums: [String: Group] = [:]
        for song in songs {
            let recording = LibrarySongMatchIndex.Key(title: song.title, artist: song.artist)
            for destination in destinations(for: song) {
                let identity = destination.identity
                guard albums[identity]?.songIDs.contains(song.id) != true,
                      albums[identity]?.recordings.contains(recording) != true else { continue }
                albums[identity, default: Group(destination: destination)].tracks.append(song)
                albums[identity]?.songIDs.insert(song.id)
                albums[identity]?.recordings.insert(recording)
            }
        }
        return albums.values.map { AlbumGroup(name: $0.destination.name, artist: $0.destination.artist, songs: $0.tracks) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
