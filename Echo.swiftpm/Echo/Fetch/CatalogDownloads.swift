import Foundation
import Observation

struct CatalogDownloadResult {
    var queued = 0
    var existing = 0
    var failed = 0
    var addedToAlbum = 0
    var message: String {
        String(format: String(localized: "catalog_download_result"), queued, existing, failed)
    }
    var albumMessage: String {
        String(format: String(localized: "album_completion_result"), queued, addedToAlbum, failed)
    }
}

@MainActor
@Observable
final class CatalogDownloads {
    static let shared = CatalogDownloads()
    private(set) var reserved: Set<String> = []
    private(set) var busy = false
    private let manager = FetchManager.shared
    private let library = MusicLibraryManager.shared

    func localSong(_ track: OnlineMusicTrack) -> Song? {
        library.songMatching(title: track.title, artist: track.artistName)
    }
    func queueItem(_ track: OnlineMusicTrack) -> FetchItem? {
        let matches = manager.items.filter {
            OnlineCatalogLogic.identifies(track, urls: [$0.spotifyURL, $0.youtubeURL].compactMap { $0 }) ||
            LibrarySongMatchIndex.matches(title: track.title, artist: track.artistName, otherTitle: $0.title, otherArtist: $0.artist)
        }
        return matches.first { $0.queueState == .pending } ?? matches.first
    }
    func statusKey(_ track: OnlineMusicTrack) -> String? {
        if localSong(track) != nil { return "catalog_downloaded" }
        if reserved.contains(track.id) { return "catalog_queued" }
        guard let item = queueItem(track) else { return nil }
        switch item.queueState {
        case .failed: return "catalog_download_failed"
        case .completed: return nil // A removed local file may be downloaded again.
        case .pending: return "catalog_queued"
        }
    }
    func pending(_ tracks: [OnlineMusicTrack]) -> [OnlineMusicTrack] {
        OnlineCatalogLogic.uniqueTracks(tracks).filter { track in
            let status = statusKey(track)
            return status != "catalog_downloaded" && status != "catalog_queued"
        }
    }
    func existingCount(_ tracks: [OnlineMusicTrack], toAddTo album: LibraryAlbumDestination) -> Int {
        var snapshot = library.songs
        return LibraryAlbums.add(existingSongIDs(tracks), to: album, songs: &snapshot)
    }

    @discardableResult
    func addExisting(_ tracks: [OnlineMusicTrack], to album: LibraryAlbumDestination) -> Int {
        library.addSongs(existingSongIDs(tracks), toAlbum: album)
    }

    private func existingSongIDs(_ tracks: [OnlineMusicTrack]) -> [UUID] {
        OnlineCatalogLogic.uniqueTracks(tracks).compactMap { localSong($0)?.id }
    }

    func needsAlbumAssignment(_ tracks: [OnlineMusicTrack], to album: LibraryAlbumDestination) -> Bool {
        existingCount(tracks, toAddTo: album) > 0 || tracks.contains { track in
            guard localSong(track) == nil, let item = queueItem(track), item.queueState == .pending else { return false }
            return !item.destinationAlbums.contains { $0.identity == album.identity }
        }
    }

    private func attach(_ album: LibraryAlbumDestination, to item: FetchItem) {
        item.destinationAlbums = LibraryAlbumDestination.unique(item.destinationAlbums + [album])
        FetchDownloadEngine.shared.updateAlbumDestinations(for: item)
    }

    func enqueue(_ tracks: [OnlineMusicTrack], playlistID: UUID? = nil,
                 destinationAlbum: LibraryAlbumDestination? = nil) async -> CatalogDownloadResult {
        guard !busy else { return CatalogDownloadResult() }
        busy = true
        defer { busy = false }
        var result = CatalogDownloadResult()
        if let destinationAlbum { result.addedToAlbum = addExisting(tracks, to: destinationAlbum) }
        let unique = OnlineCatalogLogic.uniqueTracks(tracks)
        for (position, track) in unique.enumerated() {
            if position > 0 && position.isMultiple(of: 10) { await Task.yield() }
            if Task.isCancelled { break }
            if let song = localSong(track) {
                if let playlistID { library.addSong(song, toPlaylistID: playlistID, at: position) }
                result.existing += 1
                continue
            }
            if let item = queueItem(track) {
                switch item.status {
                case .failed, .completed: manager.remove(item)
                default:
                    if let playlistID { item.destinationPlaylistPositions[playlistID] = position }
                    if let destinationAlbum { attach(destinationAlbum, to: item) }
                    result.existing += 1
                    continue
                }
            }
            guard reserved.insert(track.id).inserted else { result.existing += 1; continue }
            do {
                let item: FetchItem
                if track.provider == .spotify {
                    let spotify = SpotifyTrack(id: track.sourceID, name: track.title, artist: track.artistName,
                        album: track.album ?? "", durationMS: track.durationMS, artworkURL: track.artworkURL, spotifyURL: track.sourceURL)
                    switch ApifySettings.shared.downloadMethod {
                    case .spotify:
                        item = FetchItem(spotifyURL: spotify.spotifyURL, title: track.title, artist: track.artistName,
                            album: track.album, artworkURL: track.artworkURL, permissionConfirmed: true)
                    case .youtube:
                        let matches = try await YouTubeAPI.shared.search(title: track.title, artist: track.artistName, maxResults: 1)
                        guard let match = matches.first else { throw MusicCatalogError.unavailable }
                        item = FetchItem(spotifyURL: track.sourceURL, title: track.title, artist: track.artistName,
                            album: track.album, artworkURL: track.artworkURL, youtubeURL: match.videoURL, permissionConfirmed: true)
                    }
                } else {
                    item = FetchItem(spotifyURL: track.sourceURL, title: track.title, artist: track.artistName,
                        album: track.album, artworkURL: track.artworkURL, youtubeURL: track.sourceURL, permissionConfirmed: true)
                }
                if let playlistID { item.destinationPlaylistPositions[playlistID] = position }
                if let destinationAlbum { item.destinationAlbums = [destinationAlbum] }
                manager.addPreparedItem(item)
                result.queued += 1
            } catch { result.failed += 1 }
            reserved.remove(track.id)
        }
        return result
    }
    func importPlaylist(title: String, artworkURL: URL?, tracks: [OnlineMusicTrack]) async -> CatalogDownloadResult {
        var imageData: Data?
        if let artworkURL, let (data, response) = try? await URLSession.shared.data(from: artworkURL),
           let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) { imageData = data }
        let playlist = library.createPlaylist(name: title, imageData: imageData)
        return await enqueue(tracks, playlistID: playlist.id)
    }
}
