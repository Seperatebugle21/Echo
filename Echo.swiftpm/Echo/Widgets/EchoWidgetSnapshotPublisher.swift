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
                do { try await Task.sleep(for: .milliseconds(150)) }
                catch { return }
                refresh()
            }
        }
    }

    @MainActor private static var pendingUpdate: Task<Void, Never>?
    @MainActor private static var artworkCache: [UUID: (source: Data, thumbnail: Data)] = [:]
    private static let logger = Logger(subsystem: "com.echomusic.app", category: "Widgets")

    @MainActor static func refresh() {
        let library = MusicLibraryManager.shared
        let player = AudioPlayerManager.shared
        let session = HomeSessionManager.shared
        session.prepareIfNeeded(songs: library.songs, favorites: library.favoriteSongs,
            favoriteSongIDs: library.favoriteSongIDs, recommendationManager: RecommendationManager.shared)
        let existing = Dictionary(library.songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let picks = (session.recommendedSongs ?? []).compactMap { existing[$0.id] }.filter {
            guard let url = library.getURL(for: $0) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
        let current = player.currentSong.flatMap { existing[$0.id] }
        let displayed = current ?? library.songs.sorted {
            ($0.lastPlayed ?? $0.dateAdded) > ($1.lastPlayed ?? $1.dateAdded)
        }.first
        let items = Array(picks.prefix(4)).map { item($0, library: library) }
        let snapshot = EchoWidgetSnapshot(updatedAt: Date(), songs: items,
            currentSong: displayed.map { item($0, library: library) },
            isPlaying: current != nil && player.isPlaying)
        let keepIDs = Set(items.map(\.id) + (displayed.map { [$0.id] } ?? []))
        artworkCache = artworkCache.filter { keepIDs.contains($0.key) }
        let previous = EchoWidgetSnapshotStore.load()
        guard snapshot.songs != previous.songs || snapshot.currentSong != previous.currentSong
                || snapshot.isPlaying != previous.isPlaying else { return }
        do {
            try EchoWidgetSnapshotStore.save(snapshot)
            for kind in EchoWidgetKinds.homeScreen { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        } catch {
            logger.error("Widget snapshot failed; check App Group entitlements: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor private static func item(_ song: Song, library: MusicLibraryManager) -> EchoWidgetSongItem {
        var thumbnail: Data?
        if let source = song.coverData ?? song.imageData {
            if let cached = artworkCache[song.id], cached.source == source { thumbnail = cached.thumbnail }
            else if let generated = thumbnailData(from: source) {
                artworkCache[song.id] = (source, generated)
                thumbnail = generated
            }
        }
        return EchoWidgetSongItem(id: song.id, title: song.title, artist: song.artist,
                                  artworkData: thumbnail, isFavorite: library.isFavorite(song))
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
