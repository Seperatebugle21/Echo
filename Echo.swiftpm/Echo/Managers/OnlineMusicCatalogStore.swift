import Foundation
import Observation

@MainActor
@Observable
final class OnlineMusicCatalogStore {
    static let shared = OnlineMusicCatalogStore()
    private(set) var knownArtists: [OnlineArtistReference] = []
    private(set) var cachedAlbums: [OnlineMusicAlbum] = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var albumTracks: [String: OnlineTrackCollection] = [:]
    @ObservationIgnored private var discoveryStarted = false
    @ObservationIgnored private var attemptedNames: Set<String> = []
    private var homeIDs: [String] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = OnlineCatalogPersistence.load(from: defaults)
        knownArtists = saved.artists
        cachedAlbums = saved.albums
    }
    func remember(_ artist: OnlineArtistReference) {
        knownArtists.removeAll { $0.id == artist.id }
        knownArtists.append(artist)
        save()
    }
    private func cache(_ albums: [OnlineMusicAlbum]) {
        let changed = Set(albums.map(\.id))
        cachedAlbums.removeAll { changed.contains($0.id) }
        cachedAlbums += albums
        // Bound persistent discovery metadata, never store media or credentials here.
        if cachedAlbums.count > 1000 { cachedAlbums = Array(cachedAlbums.suffix(1000)) }
        save()
        refreshSelection()
    }
    private func save() {
        OnlineCatalogPersistence.save(artists: knownArtists, albums: cachedAlbums, to: defaults)
    }
    func albums(for reference: OnlineArtistReference, includeSongs: Bool = true) async throws -> (OnlineArtistReference, [OnlineMusicAlbum], [OnlineMusicTrack]) {
        let artist: OnlineArtistReference, albums: [OnlineMusicAlbum], songs: [OnlineMusicTrack]
        switch reference.provider {
        case .spotify:
            artist = try await SpotifyAPI.shared.catalogArtist(reference.sourceID)
            albums = try await SpotifyAPI.shared.catalogAlbums(artist)
            songs = []
        case .youtubeMusic:
            let (header, root) = try await YouTubeMusicMetadata.shared.artistHeader(reference.sourceID)
            artist = header
            albums = try await YouTubeMusicMetadata.shared.artistAlbums(root, artist: artist)
            // The songs shelf includes appearances that might not be in album shelves.
            var artistSongs: [OnlineMusicTrack] = []
            for shelf in includeSongs ? YouTubeMusicJSON.nodes("musicShelfRenderer", in: root) : [] {
                let rows = YouTubeMusicJSON.nodes("musicResponsiveListItemRenderer", in: shelf)
                let tracks = rows.compactMap { YouTubeMusicJSON.track($0) }
                guard tracks.contains(where: { OnlineCatalogLogic.belongs($0, to: artist) }) else { continue }
                artistSongs += tracks.filter { OnlineCatalogLogic.belongs($0, to: artist) }
                if let endpoint = YouTubeMusicJSON.nodes("browseEndpoint", in: shelf["bottomEndpoint"] as Any).first,
                   let id = endpoint["browseId"] as? String, id.hasPrefix("VL") {
                    let collection = try await YouTubeMusicMetadata.shared.playlist(id)
                    artistSongs += collection.tracks.filter { OnlineCatalogLogic.belongs($0, to: artist) }
                }
            }
            songs = artistSongs
        }
        remember(artist)
        cache(albums)
        return (artist, albums, OnlineCatalogLogic.uniqueTracks(songs))
    }
    func tracks(for album: OnlineMusicAlbum) async throws -> OnlineTrackCollection {
        if let cached = albumTracks[album.id] { return cached }
        let result: OnlineTrackCollection
        switch album.provider {
        case .spotify: result = try await SpotifyAPI.shared.catalogAlbum(album)
        case .youtubeMusic: result = try await YouTubeMusicMetadata.shared.album(album)
        }
        albumTracks[album.id] = result
        return result
    }
    var homeAlbums: [OnlineMusicAlbum] {
        let allowed = cachedAlbums.filter { $0.provider != .spotify || SpotifyManager.shared.isConnected }
        let byID = Dictionary(allowed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return homeIDs.compactMap { byID[$0] }
    }
    func refreshSelection() {
        let allowed = cachedAlbums.filter { $0.provider != .spotify || SpotifyManager.shared.isConnected }
        homeIDs = OnlineCatalogLogic.refillSelection(homeIDs, available: allowed.map(\.id))
    }
    func discover(localArtistNames: [String]) async {
        refreshSelection()
        guard !discoveryStarted else { return }
        discoveryStarted = true
        defer { discoveryStarted = false }
        let explicit = knownArtists
        for artist in explicit {
            if Task.isCancelled { return }
            guard artist.provider != .spotify || SpotifyManager.shared.isConnected else { continue }
            // Persistent cached releases render immediately; refresh once per process.
            guard attemptedNames.insert(artist.id).inserted else { continue }
            do { _ = try await albums(for: artist, includeSongs: false); refreshSelection() }
            catch is CancellationError { attemptedNames.remove(artist.id); return }
            catch { /* Cached discoveries remain available offline. */ }
        }
        let knownNames = Set(knownArtists.map { OnlineCatalogLogic.normalizedName($0.name) })
        for name in localArtistNames.shuffled() {
            if Task.isCancelled { return }
            let key = OnlineCatalogLogic.normalizedName(name)
            guard !key.isEmpty, !knownNames.contains(key), attemptedNames.insert(key).inserted else { continue }
            do {
                if let artist = try await YouTubeMusicMetadata.shared.searchArtist(name) {
                    _ = try await albums(for: artist, includeSongs: false)
                    refreshSelection()
                }
            } catch is CancellationError { attemptedNames.remove(key); return }
            catch { }
            if homeAlbums.count >= 10 { break }
        }
    }
}

@MainActor
@Observable
final class OnlineArtistCatalogModel {
    var artist: OnlineArtistReference
    private(set) var albums: [OnlineMusicAlbum] = []
    private(set) var tracks: [OnlineMusicTrack] = []
    private(set) var loading = false
    private(set) var complete = false
    private(set) var loadedAlbums = 0
    private(set) var skippedCount = 0
    private(set) var error: String?
    init(artist: OnlineArtistReference) { self.artist = artist }
    func load() async {
        guard !loading, !complete else { return }
        loading = true
        error = nil
        loadedAlbums = 0
        skippedCount = 0
        defer { loading = false }
        do {
            let result = try await OnlineMusicCatalogStore.shared.albums(for: artist)
            artist = result.0
            albums = result.1
            tracks = result.2
            var includedAlbums: [OnlineMusicAlbum] = []
            for album in albums {
                try Task.checkCancellation()
                let collection = try await OnlineMusicCatalogStore.shared.tracks(for: album)
                let memberTracks = collection.tracks.filter { OnlineCatalogLogic.belongs($0, to: artist) }
                if !memberTracks.isEmpty { includedAlbums.append(album) }
                tracks = OnlineCatalogLogic.uniqueTracks(tracks + memberTracks)
                skippedCount += collection.skippedCount
                loadedAlbums += 1
            }
            albums = includedAlbums
            tracks.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            complete = true
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    func retry() async { complete = false; await load() }
}
