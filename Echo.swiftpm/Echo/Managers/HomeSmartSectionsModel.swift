import Foundation
import Observation

@MainActor @Observable
final class HomeSmartSectionsModel {
    static let shared = HomeSmartSectionsModel()
    private(set) var gems: [Song] = []
    private(set) var albums: [AlbumGroup] = []
    private(set) var periods: [HistoricalMusicPeriod] = []
    private(set) var vibes: [MusicVibe: [Song]] = [:]
    private(set) var available: [Song] = []
    private(set) var week = ListeningWeek.calculate(events: [], containing: Date())
    private(set) var previousWeek = ListeningWeek.calculate(events: [], containing: Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date())
    private(set) var errorKey: String?
    var selectedPeriod = 1
    @ObservationIgnored private var fingerprint: [String] = []
    @ObservationIgnored private var albumDay: Date?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var listeningGeneration = 0
    @ObservationIgnored private var seed = UInt64.random(in: 0...UInt64.max)
    @ObservationIgnored private var snapshot: SmartMusicSelection?
    @ObservationIgnored private var lastSurprise: UUID?
    private init() {}

    func prepare(library: MusicLibraryManager) async {
        generation += 1; let token = generation
        let songs = library.songs, favorites = library.favoriteSongIDs
        let selection = RecommendationManager.shared.selectionSnapshot(songs: songs, favorites: favorites, seed: seed)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let result = await Task.detached(priority: .utility) {
            let local = songs.filter { $0.podcastEpisodeID == nil && FileManager.default.fileExists(atPath: documents.appendingPathComponent($0.fileName).path) }
            let signature = local.map { [$0.id.uuidString, $0.title, $0.artist, $0.album ?? "", $0.genre ?? "", String($0.releaseYear ?? 0), $0.fileName].joined(separator: "\u{1F}") } + favorites.map(\.uuidString).sorted()
            let filtered = SmartMusicSelection(songs: local, favorites: selection.favorites, learning: selection.learning, now: selection.now, seed: selection.seed)
            return (local, signature, filtered)
        }.value
        guard !Task.isCancelled, token == generation else { return }
        available = result.0; snapshot = result.2
        let changed = fingerprint != result.1
        if !changed {
            let indexed = Dictionary(uniqueKeysWithValues: result.0.map { ($0.id, $0) })
            gems = gems.compactMap { indexed[$0.id] }
            vibes = vibes.mapValues { $0.compactMap { indexed[$0.id] } }
        }
        fingerprint = result.1
        let day = Calendar.current.startOfDay(for: Date())
        let refreshAlbums = changed || albumDay != day
        guard changed || refreshAlbums else { return }
        let ranked = await Task.detached(priority: .utility) {
            (result.2.ranked(limit: 10, discover: true), Dictionary(uniqueKeysWithValues: MusicVibe.allCases.map { ($0, result.2.vibe($0)) }), result.2.albums())
        }.value
        guard !Task.isCancelled, token == generation else { return }
        if changed { gems = ranked.0; vibes = ranked.1 }
        if refreshAlbums {
            albums = ranked.2; albumDay = day
            // Stable IDs persist the daily ordering, while metadata is resolved from today's library.
            let defaults = UserDefaults.standard
            if defaults.stringArray(forKey: "EchoRevisitAlbumLibraryV1") == fingerprint,
               defaults.object(forKey: "EchoRevisitAlbumDayV1") as? Date == day,
               let ids = defaults.stringArray(forKey: "EchoRevisitAlbumIDsV1") {
                let indexed = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
                albums = ids.compactMap { indexed[$0] }
            }
            defaults.set(day, forKey: "EchoRevisitAlbumDayV1"); defaults.set(albums.map(\.id), forKey: "EchoRevisitAlbumIDsV1")
            defaults.set(fingerprint, forKey: "EchoRevisitAlbumLibraryV1")
        }
    }
    func updateListening() async {
        listeningGeneration += 1; let token = listeningGeneration
        let engine = RecommendationManager.shared, events = engine.listeningEvents
        let now = Date(), previous = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        let daily = engine.dailyCounts, ids = Set(available.map(\.id))
        let result = await Task.detached(priority: .utility) {
            (ListeningWeek.calculate(events: events, containing: now), ListeningWeek.calculate(events: events, containing: previous),
             HistoricalMusicPeriod.available(daily: daily, songIDs: ids, now: now))
        }.value
        guard !Task.isCancelled, token == listeningGeneration else { return }
        week = result.0; previousWeek = result.1; self.periods = result.2
        if !periods.contains(where: { $0.id == selectedPeriod }) { selectedPeriod = periods.first?.id ?? 1 }
    }
    func refreshGems() async {
        guard let snapshot else { return }
        let token = generation
        seed &+= 1
        let refreshed = SmartMusicSelection(songs: snapshot.songs, favorites: snapshot.favorites, learning: snapshot.learning, now: Date(), seed: seed)
        let result = await Task.detached(priority: .utility) { refreshed.ranked(limit: 10, discover: true) }.value
        guard !Task.isCancelled, token == generation else { return }; gems = result
    }
    func play(_ song: Song, queue: [Song]) -> Bool {
        let library = MusicLibraryManager.shared
        guard let current = library.song(withID: song.id), let url = library.getURL(for: current), FileManager.default.fileExists(atPath: url.path) else {
            errorKey = "smart_file_unavailable"; return false
        }
        let valid = queue.compactMap { library.song(withID: $0.id) }.filter {
            library.getURL(for: $0).map { FileManager.default.fileExists(atPath: $0.path) } == true
        }
        let player = AudioPlayerManager.shared
        player.lastPlaybackDirection = .fade; player.play(song: current, url: url, queue: valid.isEmpty ? [current] : valid)
        player.allSongs = available
        errorKey = player.playbackErrorKey; return errorKey == nil
    }
    func surprise(smart: Bool) async -> Song? {
        let player = AudioPlayerManager.shared, library = MusicLibraryManager.shared
        let recent = Array(RecommendationManager.shared.learningData.sorted { ($0.value.lastStartedAt ?? .distantPast) > ($1.value.lastStartedAt ?? .distantPast) }.prefix(10)).map(\.key)
        let excluded = Set(recent + [player.currentSong?.id, lastSurprise].compactMap { $0 })
        var pool = available.filter { !excluded.contains($0.id) }
        if pool.isEmpty { pool = available.filter { $0.id != player.currentSong?.id && $0.id != lastSurprise } }
        if pool.isEmpty { pool = available.filter { $0.id != player.currentSong?.id } }
        if pool.isEmpty { pool = available }
        let snapshot = RecommendationManager.shared.selectionSnapshot(songs: pool, favorites: library.favoriteSongIDs, seed: UInt64.random(in: 0...UInt64.max))
        let song = await Task.detached(priority: .utility) { smart ? snapshot.ranked(limit: min(5, pool.count), discover: true).randomElement() : pool.randomElement() }.value
        guard let song, play(song, queue: [song]) else { return nil }
        lastSurprise = song.id; return song
    }
    func dismissError() { errorKey = nil }
    func reportPlaybackError(_ key: String) { errorKey = key }
}
