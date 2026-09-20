import UIKit

/// Decoded artwork survives lazy row recycling and is shared between tabs.
@MainActor
final class PodcastArtworkCache {
    static let shared = PodcastArtworkCache()
    private let images = NSCache<NSURL, UIImage>()
    private var requests: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        images.totalCostLimit = 32 * 1_024 * 1_024
    }

    func cachedImage(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        return images.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        if let request = requests[url] { return await request.value }

        // A disappearing row must not cancel a request another row is using.
        let request = Task<UIImage?, Never> {
            if let data = PodcastStore.shared.artwork(for: url),
               let image = UIImage(data: data) { return image }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let response = response as? HTTPURLResponse,
                      (200...299).contains(response.statusCode) else { return nil }
                return UIImage(data: data)
            } catch {
                return nil
            }
        }
        requests[url] = request
        let image = await request.value
        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            images.setObject(image, forKey: url as NSURL, cost: cost)
        }
        requests[url] = nil
        return image
    }
}
