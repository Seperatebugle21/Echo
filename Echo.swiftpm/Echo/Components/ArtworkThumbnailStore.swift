import SwiftUI
import UIKit
import ImageIO

/// Decode once off the main actor and share prepared pixels between cards and entrance animations.
actor ArtworkThumbnailStore {
    static let shared = ArtworkThumbnailStore()
    private let cache = NSCache<NSData, UIImage>()
    private var pending: [Data: Task<UIImage?, Never>] = [:]

    init() {
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 64
    }

    func thumbnail(_ data: Data?) async -> UIImage? {
        guard let data else { return nil }
        let key = data as NSData
        if let image = cache.object(forKey: key) { return image }
        if let task = pending[data] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            autoreleasepool {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 600,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: pixels)
            }
        }
        pending[data] = task
        let image = await task.value
        pending.removeValue(forKey: data)
        if let image, let pixels = image.cgImage {
            cache.setObject(image, forKey: key, cost: pixels.bytesPerRow * pixels.height)
        }
        return image
    }
}

struct CachedSongArtwork: View {
    let data: Data?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else {
                Rectangle().fill(.thinMaterial)
                    .overlay { Image(systemName: "music.note").font(.title2) }
            }
        }
        .task(id: data) {
            image = nil
            let prepared = await ArtworkThumbnailStore.shared.thumbnail(data)
            guard !Task.isCancelled else { return }
            image = prepared
        }
    }
}

// MARK: - Song artwork by key

/// Identifies one song's artwork at one size without touching the artwork itself.
/// Views key their loading on this instead of on the image bytes, so a redraw never
/// reads a file or compares whole images.
struct SongArtworkKey: Hashable, Sendable {
    let id: UUID
    let revision: Int
    let pixels: Int

    init(_ song: Song, pixels: Int) {
        id = song.id
        revision = song.artworkRevision
        self.pixels = pixels
    }

    var cacheKey: NSString { "\(id.uuidString)|\(revision)|\(pixels)" as NSString }
}

/// Loads songs' covers by key, off the main thread.
enum SongArtworkLoader {
    /// Decoded, display-sized covers. Read synchronously while drawing, so scrolling
    /// back to a row shows its cover in the very first frame.
    static let decoded: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    static func cachedImage(_ key: SongArtworkKey) -> UIImage? {
        decoded.object(forKey: key.cacheKey)
    }

    /// The song's artwork bytes, read off the main thread.
    static func data(for song: Song?) async -> Data? {
        guard let song else { return nil }
        return await Task.detached(priority: .userInitiated) { song.coverData ?? song.imageData }.value
    }

    /// The song's cover at `key.pixels`, read and decoded off the main thread.
    static func image(for song: Song, key: SongArtworkKey) async -> UIImage? {
        if let hit = cachedImage(key) { return hit }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard SongArtworkStore.shared.hasArtwork(for: song.id),
                  let data = song.coverData ?? song.imageData else { return nil }
            return autoreleasepool {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: key.pixels,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: pixels)
            }
        }.value
        if let image, let cg = image.cgImage {
            decoded.setObject(image, forKey: key.cacheKey, cost: cg.bytesPerRow * cg.height)
        }
        return image
    }
}

/// A song's cover, loaded by key off the main thread at the size it is shown.
struct SongCoverImage: View {
    let song: Song
    /// Pixel size of the decoded image: about the point size × 3.
    var pixels: Int = 300
    var symbolFont: Font = .title2
    @State private var image: UIImage?
    @State private var loadedKey: SongArtworkKey?

    var body: some View {
        let key = SongArtworkKey(song, pixels: pixels)
        let shown = loadedKey == key ? image : SongArtworkLoader.cachedImage(key)
        ZStack {
            if let shown {
                Image(uiImage: shown).resizable().scaledToFill()
            } else {
                Rectangle().fill(.thinMaterial)
                    .overlay { Image(systemName: "music.note").font(symbolFont).foregroundStyle(.secondary) }
            }
        }
        .task(id: key) {
            let loaded = await SongArtworkLoader.image(for: song, key: key)
            guard !Task.isCancelled else { return }
            image = loaded
            loadedKey = key
        }
    }
}
