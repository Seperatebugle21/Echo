import Foundation

extension SpotifyAPI {
    func catalogJSON(_ path: String) async throws -> [String: Any] {
        guard SpotifyManager.shared.isConnected else { throw MusicCatalogError.spotifyConnection }
        guard let url = URL(string: path.hasPrefix("https:") ? path : "https://api.spotify.com/v1/" + path),
              url.scheme == "https", url.host == "api.spotify.com" else { throw MusicCatalogError.invalidLink }
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let token = try await SpotifyManager.shared.validAccessToken()
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let data: Data, response: URLResponse
            do { (data, response) = try await URLSession.shared.data(for: request) }
            catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                throw MusicCatalogError.network
            }
            guard let http = response as? HTTPURLResponse else { throw MusicCatalogError.malformed }
            if http.statusCode == 429, attempt < 2 {
                let delay = min(60, max(1, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2))
                try await Task.sleep(for: .seconds(delay))
                continue
            }
            if http.statusCode == 401 { throw MusicCatalogError.spotifyConnection }
            if http.statusCode == 403 || http.statusCode == 404 { throw MusicCatalogError.unavailable }
            guard (200..<300).contains(http.statusCode) else { throw MusicCatalogError.network }
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw MusicCatalogError.malformed }
            return json
        }
        throw MusicCatalogError.network
    }

    func catalogPages(_ path: String) async throws -> [[String: Any]] {
        var next: String? = path
        var seen: Set<String> = [], items: [[String: Any]] = []
        while let page = next {
            guard seen.insert(page).inserted else { throw MusicCatalogError.incomplete }
            let json = try await catalogJSON(page)
            guard let values = json["items"] as? [[String: Any]] else { throw MusicCatalogError.malformed }
            items += values
            next = json["next"] as? String
        }
        return items
    }

    func catalogArtist(_ id: String) async throws -> OnlineArtistReference {
        let json = try await catalogJSON("artists/\(id)")
        guard let name = json["name"] as? String else { throw MusicCatalogError.malformed }
        return OnlineArtistReference(provider: .spotify, sourceID: id, name: name, artworkURL: SpotifyCatalogJSON.artwork(json))
    }

    func catalogAlbums(_ artist: OnlineArtistReference) async throws -> [OnlineMusicAlbum] {
        let items = try await catalogPages("artists/\(artist.sourceID)/albums?include_groups=album,single,appears_on,compilation&limit=10")
        var seen: Set<String> = []
        return items.compactMap(SpotifyCatalogJSON.album).filter { seen.insert($0.id).inserted }
    }

    func catalogAlbum(_ album: OnlineMusicAlbum) async throws -> OnlineTrackCollection {
        let items = try await catalogPages("albums/\(album.sourceID)/tracks?limit=50")
        var tracks: [OnlineMusicTrack] = [], skipped = 0
        for item in items {
            if let track = SpotifyCatalogJSON.track(item, album: album) { tracks.append(track) }
            else { skipped += 1 }
        }
        return OnlineTrackCollection(title: album.title, artworkURL: album.artworkURL, tracks: tracks, skippedCount: skipped)
    }

    func catalogAlbumReference(_ id: String) async throws -> OnlineMusicAlbum {
        let json = try await catalogJSON("albums/\(id)")
        guard let album = SpotifyCatalogJSON.album(json) else { throw MusicCatalogError.malformed }
        return album
    }
}

