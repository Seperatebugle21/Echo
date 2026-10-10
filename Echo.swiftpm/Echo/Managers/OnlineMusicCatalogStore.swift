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
    @ObservationIgnored private var startupDiscovery: Task<Void, Never>?
    @ObservationIgnored private var attemptedNames: Set<String> = []
    private var homeSession: HomeAlbumSession

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = OnlineCatalogPersistence.load(from: defaults)
        knownArtists = saved.artists
        cachedAlbums = saved.albums
        homeSession = HomeAlbumSession(cachedAlbums: saved.albums, spotifyConnected: SpotifyManager.shared.isConnected)
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
    }
    private func save() {
        OnlineCatalogPersistence.save(artists: knownArtists, albums: cachedAlbums, to: defaults)
    }
    func albums(for reference: OnlineArtistReference, includeSongs: Bool = true) async throws -> (OnlineArtistReference, [OnlineMusicAlbum], [OnlineMusicTrack], Int) {
        var unavailable = 0
        let artist: OnlineArtistReference, albums: [OnlineMusicAlbum], songs: [OnlineMusicTrack]
        switch reference.provider {
        case .spotify:
            artist = try await SpotifyAPI.shared.catalogArtist(reference.sourceID)
            albums = try await SpotifyAPI.shared.catalogAlbums(artist)
            songs = []
        case .youtubeMusic:
            let (header, root) = try await YouTubeMusicMetadata.shared.artistHeader(reference.sourceID)
            artist = header
            let releases = try await YouTubeMusicMetadata.shared.artistAlbums(root, artist: artist)
            albums = releases.albums
            unavailable += releases.unavailable
            // The songs shelf includes appearances that might not be in album shelves.
            var artistSongs: [OnlineMusicTrack] = []
            for shelf in includeSongs ? YouTubeMusicJSON.nodes("musicShelfRenderer", in: root) : [] {
                let rows = YouTubeMusicJSON.nodes("musicResponsiveListItemRenderer", in: shelf)
                let tracks = rows.compactMap { YouTubeMusicJSON.track($0) }
                guard tracks.contains(where: { OnlineCatalogLogic.belongs($0, to: artist) }) else { continue }
                artistSongs += tracks.filter { OnlineCatalogLogic.belongs($0, to: artist) }
                if let endpoint = YouTubeMusicJSON.nodes("browseEndpoint", in: shelf["bottomEndpoint"] as Any).first,
                   let id = endpoint["browseId"] as? String, id.hasPrefix("VL") {
                    do {
                        let collection = try await YouTubeMusicMetadata.shared.playlist(id)
                        artistSongs += collection.tracks.filter { OnlineCatalogLogic.belongs($0, to: artist) }
                    } catch is CancellationError { throw CancellationError() }
                    catch { unavailable += 1 }
                }
            }
            songs = artistSongs
        }
        remember(artist)
        cache(albums)
        return (artist, albums, OnlineCatalogLogic.uniqueTracks(songs), unavailable)
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
    var homeAlbums: [OnlineMusicAlbum] { homeSession.albums }

    func prepareHomeIfNeeded(localArtistNames: [String]) {
        guard startupDiscovery == nil else { return }
        // Owned by the process, so leaving Home or changing language cannot restart it.
        startupDiscovery = Task { await discoverAtStartup(localArtistNames: localArtistNames) }
    }

    private func discoverAtStartup(localArtistNames: [String]) async {
        defer {
            homeSession.finishStartupDiscovery(cachedAlbums: cachedAlbums,
                spotifyConnected: SpotifyManager.shared.isConnected)
        }
        // Discovery samples known artists; opening an artist still loads its entire catalog.
        let explicit = Array(knownArtists.shuffled().prefix(6))
        for artist in explicit {
            if Task.isCancelled { return }
            guard artist.provider != .spotify || SpotifyManager.shared.isConnected else { continue }
            // Persistent cached releases render immediately; refresh once per process.
            guard attemptedNames.insert(artist.id).inserted else { continue }
            do { _ = try await albums(for: artist, includeSongs: false) }
            catch is CancellationError { attemptedNames.remove(artist.id); return }
            catch { /* Cached discoveries remain available offline. */ }
        }
        let knownNames = Set(knownArtists.map { OnlineCatalogLogic.normalizedName($0.name) })
        var resolved = 0
        for name in localArtistNames.shuffled().prefix(12) {
            if Task.isCancelled { return }
            let key = OnlineCatalogLogic.normalizedName(name)
            guard !key.isEmpty, !knownNames.contains(key), attemptedNames.insert(key).inserted else { continue }
            do {
                if let artist = try await YouTubeMusicMetadata.shared.searchArtist(name) {
                    _ = try await albums(for: artist, includeSongs: false)
                    resolved += 1
                }
            } catch is CancellationError { attemptedNames.remove(key); return }
            catch { }
            if resolved >= 4 { break }
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
        // A new view task may begin before its canceled predecessor unwinds.
        while loading {
            do { try await Task.sleep(for: .milliseconds(40)) }
            catch { return }
        }
        guard !complete, !Task.isCancelled else { return }
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
            var unavailableAlbums = result.3
            for album in albums {
                try Task.checkCancellation()
                do {
                    let collection = try await OnlineMusicCatalogStore.shared.tracks(for: album)
                    let memberTracks = collection.tracks.filter { OnlineCatalogLogic.belongs($0, to: artist) }
                    tracks = OnlineCatalogLogic.uniqueTracks(tracks + memberTracks)
                    skippedCount += collection.skippedCount
                } catch is CancellationError { throw CancellationError() }
                catch { unavailableAlbums += 1 }
                loadedAlbums += 1
            }
            tracks.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            complete = unavailableAlbums == 0
            if unavailableAlbums > 0 {
                error = String(format: String(localized: "catalog_artist_partial"), unavailableAlbums)
            }
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    func retry() async { complete = false; await load() }
}
