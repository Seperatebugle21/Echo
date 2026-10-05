import Foundation
import Observation

struct CatalogDownloadResult {
    var queued = 0
    var existing = 0
    var failed = 0
    var message: String {
        String(format: String(localized: "catalog_download_result"), queued, existing, failed)
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
        manager.items.first { OnlineCatalogLogic.identifies(track, urls: [$0.spotifyURL, $0.youtubeURL].compactMap { $0 }) }
    }
    func statusKey(_ track: OnlineMusicTrack) -> String? {
        if localSong(track) != nil { return "catalog_downloaded" }
        if reserved.contains(track.id) { return "catalog_queued" }
        guard let item = queueItem(track) else { return nil }
        switch item.status {
        case .failed: return "catalog_download_failed"
        case .completed: return nil // A removed local file may be downloaded again.
        default: return "catalog_queued"
        }
    }
    func pending(_ tracks: [OnlineMusicTrack]) -> [OnlineMusicTrack] {
        OnlineCatalogLogic.uniqueTracks(tracks).filter { track in
            let status = statusKey(track)
            return status != "catalog_downloaded" && status != "catalog_queued"
        }
    }
    func enqueue(_ tracks: [OnlineMusicTrack], playlistID: UUID? = nil) async -> CatalogDownloadResult {
        busy = true
        defer { busy = false }
        var result = CatalogDownloadResult()
        let unique = OnlineCatalogLogic.uniqueTracks(tracks)
        for (position, track) in unique.enumerated() {
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
