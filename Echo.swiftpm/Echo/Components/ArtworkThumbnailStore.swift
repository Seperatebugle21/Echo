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
