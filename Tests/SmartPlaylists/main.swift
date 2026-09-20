import Foundation

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAILED: \(message)") }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now)! }
func song(_ id: Int, _ title: String, added: Int = 0, played: Int? = nil, count: Int? = nil) -> Song {
    var song = Song(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
                    title: title, artist: "Björk", fileName: "\(id).m4a", album: "Debut",
                    dateAdded: daysAgo(added), lastPlayed: played.map(daysAgo))
    song.playCount = count
    return song
}
let fresh = song(1, "Fresh", added: 1)
let old = song(2, "Old favorite", added: 100, played: 60, count: 9)
let recent = song(3, "Recent listen", added: 30, played: 1, count: 2)
let legacy = song(4, "Legacy listen", added: 90, played: 90)
let library = [fresh, old, recent, legacy]
let favorites: Set<UUID> = [old.id, recent.id, fresh.id]

func results(_ config: SmartPlaylistConfiguration, songs: [Song] = library, at date: Date = now) -> [UUID] {
    config.songs(in: songs, favorites: favorites, now: date, calendar: calendar).map(\.id)
}

expect(results(SmartPlaylistPreset.recentlyAdded.configuration) == [fresh.id, recent.id], "recent additions include the exact boundary")
expect(results(SmartPlaylistPreset.topSongs.configuration) == [old.id, recent.id], "top songs exclude unknown and zero counts")
expect(results(SmartPlaylistPreset.forgottenFavorites.configuration) == [old.id], "forgotten favorites require an old recorded listen")
expect(results(SmartPlaylistPreset.undiscovered.configuration) == [fresh.id], "known legacy listens are not never-played")

var config = SmartPlaylistConfiguration(rules: [SmartPlaylistRule(field: .artist, text: " BJÖRK "), SmartPlaylistRule(field: .album, text: "debut")])
expect(results(config).count == 4, "text conditions trim whitespace and ignore case")
config.rules[1].text = "missing"
expect(results(config).isEmpty, "all conditions must match")
config.matchMode = .any
expect(results(config).count == 4, "any mode accepts one matching condition")
config.rules[0].text = " "
expect(!config.isValid && results(config).isEmpty, "blank text conditions cannot be saved or previewed")
config.rules = []
expect(!config.isValid && results(config).isEmpty, "empty rules cannot silently include everything")

config = SmartPlaylistConfiguration(rules: [SmartPlaylistRule(field: .favorite, favorite: false)])
expect(results(config) == [legacy.id], "non-favorite condition")
config.rules = [SmartPlaylistRule(field: .playedWithinDays, number: 30)]
expect(results(config) == [recent.id], "recent listening excludes unknown history")
config.rules = [SmartPlaylistRule(field: .playCountAtMost, number: 2)]
expect(Set(results(config)) == [fresh.id, recent.id, legacy.id], "maximum play count treats missing counts as zero")
config.rules = [SmartPlaylistRule(field: .addedWithinDays, number: 1)]
expect(results(config) == [fresh.id], "rolling dates include exact cutoff")
expect(results(config, at: now.addingTimeInterval(1)).isEmpty, "date membership changes without library mutations")
var future = fresh
future.dateAdded = now.addingTimeInterval(60)
expect(results(config, songs: [future]).isEmpty, "future timestamps are excluded")

let many = (1...120).map { song($0, "Title \($0)", count: $0) }
config = SmartPlaylistConfiguration(rules: [SmartPlaylistRule(field: .playCountAtLeast, number: 1)], sortOrder: .mostPlayed, limit: 25)
let top25 = config.songs(in: many, favorites: [], now: now)
expect(top25.count == 25 && top25.first?.recordedPlayCount == 120 && top25.last?.recordedPlayCount == 96, "limit is applied after ordering")
config.sortOrder = .random
let shuffled = results(config, songs: many)
expect(shuffled == results(config, songs: Array(many.reversed())), "random subset stays stable across collection order changes")
let restoredConfig = try JSONDecoder().decode(SmartPlaylistConfiguration.self, from: JSONEncoder().encode(config))
expect(shuffled == results(restoredConfig, songs: many), "random ordering survives save and reload")
config.randomSeed = "another-seed"
expect(shuffled != results(config, songs: many), "reshuffle changes the order")

// Legacy fixtures deliberately omit the new keys.
let legacySongJSON = """
{"id":"00000000-0000-0000-0000-000000000099","title":"Existing","artist":"Artist","fileName":"existing.mp3","dateAdded":0,"lastPlayed":100}
"""
let decodedSong = try JSONDecoder().decode(Song.self, from: Data(legacySongJSON.utf8))
expect(decodedSong.playCount == nil && decodedSong.recordedPlayCount == 0, "legacy counts remain unknown")
expect(decodedSong.dateAdded == Date(timeIntervalSinceReferenceDate: 0) && decodedSong.lastPlayed == Date(timeIntervalSinceReferenceDate: 100), "migration preserves existing dates")
let legacyPlaylistJSON = """
{"id":"00000000-0000-0000-0000-000000000001","name":"Manual","songIDs":["00000000-0000-0000-0000-000000000099"]}
"""
let manual = try JSONDecoder().decode(Playlist.self, from: Data(legacyPlaylistJSON.utf8))
expect(!manual.isSmart && manual.songIDs == [decodedSong.id], "manual playlists retain their membership")
let smart = Playlist(id: UUID(), name: "Smart", songIDs: [], imageData: Data([1, 2, 3]), smartRules: config)
let mixed = try JSONDecoder().decode([Playlist].self, from: JSONEncoder().encode([manual, smart]))
expect(!mixed[0].isSmart && mixed[1].smartRules == config && mixed[1].imageData == smart.imageData, "mixed playlists round-trip with artwork")

// Playback queue is a value snapshot, never a live view of rule membership.
var changingLibrary = [fresh]
let neverPlayed = SmartPlaylistPreset.undiscovered.configuration
let queue = neverPlayed.songs(in: changingLibrary, favorites: [], now: now)
changingLibrary[0].playCount = 1
changingLibrary[0].lastPlayed = now
expect(neverPlayed.songs(in: changingLibrary, favorites: [], now: now).isEmpty && queue.map(\.id) == [fresh.id], "library changes do not mutate an existing playback queue")

var session = ListeningSession(songID: fresh.id, duration: 200)
expect(!session.sample(position: 99), "less than half does not count")
expect(session.sample(position: 100), "half the track counts")
expect(!session.sample(position: 200), "a session counts only once")
session = ListeningSession(songID: fresh.id, duration: 1000)
expect(!session.sample(position: 239) && session.sample(position: 240), "long tracks count after four minutes")
session = ListeningSession(songID: fresh.id, duration: 200)
expect(!session.sample(position: 10), "short listening does not count")
session.rebase(to: 190)
expect(!session.sample(position: 200), "seeking to the end does not count skipped audio")
expect(session.listened == 20, "only consumed audio contributes")
session.rebase(to: 0)
expect(session.sample(position: 80), "listening can accumulate after seeking backwards")
session = ListeningSession(songID: fresh.id, duration: 200)
expect(!session.sample(position: 30) && !session.sample(position: 30), "paused position contributes no listening time")
expect(session.sample(position: 100), "resuming keeps progress")
session = ListeningSession(songID: fresh.id, duration: 0)
expect(!session.sample(position: 100), "invalid duration cannot count")
print("Passed \(checks) smart playlist and listening checks.")
