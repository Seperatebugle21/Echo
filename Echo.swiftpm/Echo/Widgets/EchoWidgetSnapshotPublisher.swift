import Foundation
import ImageIO
import UniformTypeIdentifiers
import WidgetKit
import OSLog

enum EchoWidgetSnapshotPublisher {
    static func publish(songs: [Song]) { requestUpdate() }

    // Access managers after initialization, and coalesce consecutive changes.
    static func requestUpdate() {
        Task { @MainActor in
            pendingUpdate?.cancel()
            pendingUpdate = Task { @MainActor in
                // After any song-change animation, and coalescing bursts of changes.
                do { try await Task.sleep(for: .milliseconds(1200)) }
                catch { return }
                refresh()
            }
        }
    }

    @MainActor private static var pendingUpdate: Task<Void, Never>?
    /// Widget thumbnails by song and artwork revision, built off the main thread.
    private static let thumbnails = NSCache<NSString, NSData>()
    private static let logger = Logger(subsystem: "com.echomusic.app", category: "Widgets")

    @MainActor static func refresh() {
        let library = MusicLibraryManager.shared
        let player = AudioPlayerManager.shared
        let session = HomeSessionManager.shared
        session.prepareIfNeeded(songs: library.songs, favorites: library.favoriteSongs,
            favoriteSongIDs: library.favoriteSongIDs, recommendationManager: RecommendationManager.shared)
        let existing = Dictionary(library.songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let picks = (session.recommendedSongs ?? []).compactMap { existing[$0.id] }.filter {
            HomeFileCheck.exists($0, library: library)
        }
        let current = player.currentSong.flatMap { $0.podcastEpisodeID != nil ? $0 : existing[$0.id] }
        let displayed = current ?? library.songs.sorted {
            ($0.lastPlayed ?? $0.dateAdded) > ($1.lastPlayed ?? $1.dateAdded)
        }.first
        // Only cheap, main-thread-bound facts here; artwork, files and WidgetKit run
        // in the background so a widget refresh never costs a frame.
        let pickSongs = Array(picks.prefix(4))
        let favorites = Dictionary((pickSongs + (displayed.map { [$0] } ?? [])).map { song in
            (song.id, song.podcastEpisodeID.map { PodcastStore.shared.state.savedEpisodeIDs.contains($0) }
                ?? library.isFavorite(song))
        }, uniquingKeysWith: { first, _ in first })
        let isPlaying = current != nil && player.isPlaying
        let language = EchoLanguage.current.rawValue
        Task.detached(priority: .utility) {
            let items = pickSongs.map { item($0, favorite: favorites[$0.id] ?? false) }
            let snapshot = EchoWidgetSnapshot(updatedAt: Date(), songs: items,
                currentSong: displayed.map { item($0, favorite: favorites[$0.id] ?? false) },
                isPlaying: isPlaying, language: language)
            let previous = EchoWidgetSnapshotStore.load()
            guard snapshot.songs != previous.songs || snapshot.currentSong != previous.currentSong
                    || snapshot.isPlaying != previous.isPlaying || snapshot.language != previous.language else { return }
            do {
                try EchoWidgetSnapshotStore.save(snapshot)
                for kind in EchoWidgetKinds.homeScreen { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
            } catch {
                logger.error("Widget snapshot failed; check App Group entitlements: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func item(_ song: Song, favorite: Bool) -> EchoWidgetSongItem {
        let key = "\(song.id.uuidString)|\(song.artworkRevision)" as NSString
        var thumbnail = thumbnails.object(forKey: key) as Data?
        if thumbnail == nil, let source = song.coverData ?? song.imageData, let generated = thumbnailData(from: source) {
            thumbnails.setObject(generated as NSData, forKey: key)
            thumbnail = generated
        }
        return EchoWidgetSongItem(id: song.id, title: song.title, artist: song.artist,
            artworkData: thumbnail, isFavorite: favorite)
    }

    private static func thumbnailData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 360
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
