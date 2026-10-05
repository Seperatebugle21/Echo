import Foundation

/// Public metadata requests only. No Python, media extraction or user credentials.
actor YouTubeMusicMetadata {
    static let shared = YouTubeMusicMetadata()
    private let session: URLSession
    private var clientVersion = "1.20260930.01.00"
    private var visitorData: String?
    private var contextLoaded = false
    init(session: URLSession = .shared) { self.session = session }

    private func loadContext() async throws {
        guard !contextLoaded else { return }
        var request = URLRequest(url: URL(string: "https://music.youtube.com/")!)
        request.timeoutInterval = 20
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let html = String(data: data, encoding: .utf8) {
                func config(_ key: String) -> String? {
                    let pattern = "\"" + key + "\"\\s*:\\s*\"([^\"]+)\""
                    guard let regex = try? NSRegularExpression(pattern: pattern),
                          let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                          let range = Range(match.range(at: 1), in: html) else { return nil }
                    return String(html[range])
                }
                clientVersion = config("INNERTUBE_CLIENT_VERSION") ?? clientVersion
                visitorData = config("VISITOR_DATA")
            }
            contextLoaded = true
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            // A consent/home-page failure does not preclude a public API request.
        }
    }
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

    func request(_ endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        try Task.checkCancellation()
        try await loadContext()
        var payload = body
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": clientVersion, "hl": "en", "gl": "BE"]
        if let visitorData { client["visitorData"] = visitorData }
        payload["context"] = ["client": client, "user": [:]]
        var request = URLRequest(url: URL(string: "https://music.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        for (key, value) in ["Content-Type": "application/json", "User-Agent": Self.userAgent,
                             "Origin": "https://music.youtube.com", "Referer": "https://music.youtube.com/",
                             "X-YouTube-Client-Name": "67", "X-YouTube-Client-Version": clientVersion] {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let visitorData { request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id") }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw MusicCatalogError.network
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw MusicCatalogError.malformed }
        if http.statusCode == 401 || http.statusCode == 403 || http.statusCode == 404 { throw MusicCatalogError.unavailable }
        guard (200..<300).contains(http.statusCode) else { throw MusicCatalogError.network }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw MusicCatalogError.malformed }
        if root["error"] != nil || YouTubeMusicJSON.nodes("alertRenderer", in: root).contains(where: { $0["type"] as? String == "ERROR" }) {
            throw MusicCatalogError.unavailable
        }
        return root
    }

    func song(_ id: String) async throws -> OnlineMusicTrack {
        do {
            let root = try await request("next", body: ["videoId": id])
            if let row = YouTubeMusicJSON.nodes("playlistPanelVideoRenderer", in: root).first(where: { $0["videoId"] as? String == id }),
               let track = YouTubeMusicJSON.track(row) { return track }
        } catch is CancellationError { throw CancellationError() }
        catch { /* Metadata fallback below does not extract any stream URLs. */ }
        do {
            let root = try await request("player", body: ["videoId": id])
            if let detail = root["videoDetails"] as? [String: Any], let title = detail["title"] as? String {
                return OnlineMusicTrack(provider: .youtubeMusic, sourceID: id, title: title, artists: [],
                    artistName: detail["author"] as? String ?? "", artworkURL: YouTubeMusicJSON.artwork(detail),
                    durationMS: (Int(detail["lengthSeconds"] as? String ?? "") ?? 0) * 1000)
            }
        } catch is CancellationError { throw CancellationError() }
        catch { }
        // Public oEmbed can still expose metadata when the Music player is unavailable.
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(id)"), URLQueryItem(name: "format", value: "json")]
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(from: components.url!) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw MusicCatalogError.network
        }
        guard let http = response as? HTTPURLResponse else { throw MusicCatalogError.malformed }
        guard (200..<300).contains(http.statusCode) else { throw MusicCatalogError.unavailable }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let title = json["title"] as? String else { throw MusicCatalogError.malformed }
        return OnlineMusicTrack(provider: .youtubeMusic, sourceID: id, title: title, artists: [],
            artistName: json["author_name"] as? String ?? "", artworkURL: URL(string: json["thumbnail_url"] as? String ?? ""))
    }

    func playlist(_ id: String) async throws -> OnlineTrackCollection {
        let browseID = id.hasPrefix("VL") ? id : "VL" + id
        let root = try await request("browse", body: ["browseId": browseID])
        let header = YouTubeMusicJSON.header(root)
        let page = YouTubeMusicJSON.trackPage(root)
        guard page.recognized else { throw MusicCatalogError.malformed }
        var result = OnlineTrackCollection(title: YouTubeMusicJSON.text(header["title"]), artworkURL: YouTubeMusicJSON.artwork(header), tracks: page.tracks, skippedCount: page.skipped)
        var token = page.continuation
        var seen: Set<String> = []
        while let next = token {
            guard seen.insert(next).inserted else { throw MusicCatalogError.incomplete }
            let response = try await request("browse", body: ["continuation": next])
            let continuation = YouTubeMusicJSON.trackPage(response)
            guard continuation.recognized else { throw MusicCatalogError.incomplete }
            result.tracks += continuation.tracks
            result.skippedCount += continuation.skipped
            token = continuation.continuation
        }
        if result.title.isEmpty { result.title = String(localized: "catalog_playlist") }
        return result
    }

    func artistHeader(_ id: String) async throws -> (OnlineArtistReference, [String: Any]) {
        let root = try await request("browse", body: ["browseId": id])
        let header = YouTubeMusicJSON.header(root)
        let name = YouTubeMusicJSON.text(header["title"])
        guard !name.isEmpty else { throw MusicCatalogError.unavailable }
        return (OnlineArtistReference(provider: .youtubeMusic, sourceID: id, name: name, artworkURL: YouTubeMusicJSON.artwork(header)), root)
    }

    func artistAlbums(_ root: [String: Any], artist: OnlineArtistReference) async throws -> [OnlineMusicAlbum] {
        var albums = YouTubeMusicJSON.albums(root, artist: artist)
        // Follow the explicit albums/singles/appearances shelves, not related artists or videos.
        for shelf in YouTubeMusicJSON.nodes("musicCarouselShelfRenderer", in: root) {
            guard !YouTubeMusicJSON.albums(shelf, artist: artist).isEmpty else { continue }
            let endpoints = YouTubeMusicJSON.nodes("browseEndpoint", in: shelf["header"] as Any)
            guard let endpoint = endpoints.first(where: { $0["params"] != nil }), let browseID = endpoint["browseId"] as? String else { continue }
            var body: [String: Any] = ["browseId": browseID]
            body["params"] = endpoint["params"]
            var response = try await request("browse", body: body)
            albums += YouTubeMusicJSON.albums(response, artist: artist)
            var seen: Set<String> = []
            while let token = YouTubeMusicJSON.continuation(response) {
                guard seen.insert(token).inserted else { throw MusicCatalogError.incomplete }
                response = try await request("browse", body: ["continuation": token])
                albums += YouTubeMusicJSON.albums(response, artist: artist)
            }
        }
        var seen: Set<String> = []
        return albums.filter { seen.insert($0.id).inserted }
    }

    func album(_ album: OnlineMusicAlbum) async throws -> OnlineTrackCollection {
        let root = try await request("browse", body: ["browseId": album.sourceID])
        let header = YouTubeMusicJSON.header(root)
        let albumArtists = YouTubeMusicJSON.artists(header)
        let artists = albumArtists.isEmpty ? album.artists : albumArtists
        var page = YouTubeMusicJSON.trackPage(root, fallbackArtists: artists, album: album.title)
        guard page.recognized else { throw MusicCatalogError.malformed }
        var result = OnlineTrackCollection(title: album.title, artworkURL: album.artworkURL ?? YouTubeMusicJSON.artwork(header), tracks: page.tracks, skippedCount: page.skipped)
        var seen: Set<String> = []
        while let token = page.continuation {
            guard seen.insert(token).inserted else { throw MusicCatalogError.incomplete }
            let response = try await request("browse", body: ["continuation": token])
            page = YouTubeMusicJSON.trackPage(response, fallbackArtists: artists, album: album.title)
            guard page.recognized else { throw MusicCatalogError.incomplete }
            result.tracks += page.tracks
            result.skippedCount += page.skipped
        }
        for index in result.tracks.indices { result.tracks[index].artworkURL = result.tracks[index].artworkURL ?? result.artworkURL }
        return result
    }

    func albumReference(_ id: String) async throws -> OnlineMusicAlbum {
        let root = try await request("browse", body: ["browseId": id])
        let header = YouTubeMusicJSON.header(root)
        let title = YouTubeMusicJSON.text(header["title"])
        guard !title.isEmpty else { throw MusicCatalogError.unavailable }
        let artists = YouTubeMusicJSON.artists(header)
        return OnlineMusicAlbum(provider: .youtubeMusic, sourceID: id, title: title,
            artistName: artists.map(\.name).joined(separator: ", "), artists: artists, artworkURL: YouTubeMusicJSON.artwork(header))
    }

    func searchArtist(_ name: String) async throws -> OnlineArtistReference? {
        let root = try await request("search", body: ["query": name, "params": "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"])
        var matches: [OnlineArtistReference] = []
        for row in YouTubeMusicJSON.nodes("musicResponsiveListItemRenderer", in: root) {
            let candidates = YouTubeMusicJSON.artists(row)
            matches += candidates.filter { OnlineCatalogLogic.normalizedName($0.name) == OnlineCatalogLogic.normalizedName(name) }
        }
        var seen: Set<String> = []
        matches = matches.filter { seen.insert($0.id).inserted }
        return matches.count == 1 ? matches[0] : nil
    }
}

enum YouTubeMusicJSON {
    static func nodes(_ key: String, in value: Any) -> [[String: Any]] {
        if let dict = value as? [String: Any] {
            if let node = dict[key] as? [String: Any] { return [node] }
            return dict.keys.sorted().flatMap { nodes(key, in: dict[$0] as Any) }
        }
        if let array = value as? [Any] { return array.flatMap { nodes(key, in: $0) } }
        return []
    }
    static func text(_ value: Any?) -> String {
        guard let dict = value as? [String: Any] else { return value as? String ?? "" }
        if let simple = dict["simpleText"] as? String { return simple }
        return (dict["runs"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
    }
    static func artwork(_ value: Any) -> URL? {
        func thumbnails(_ value: Any) -> [[String: Any]] {
            if let dict = value as? [String: Any] {
                if let images = dict["thumbnails"] as? [[String: Any]] { return images }
                return dict.keys.sorted().flatMap { thumbnails(dict[$0] as Any) }
            }
            if let array = value as? [Any] { return array.flatMap(thumbnails) }
            return []
        }
        let best = thumbnails(value).max { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }
        guard let raw = best?["url"] as? String else { return nil }
        return URL(string: raw.hasPrefix("//") ? "https:" + raw : raw)
    }
    static func header(_ root: Any) -> [String: Any] {
        for key in ["musicResponsiveHeaderRenderer", "musicDetailHeaderRenderer", "musicImmersiveHeaderRenderer", "musicVisualHeaderRenderer", "musicHeaderRenderer"] {
            if let result = nodes(key, in: root).first { return result }
        }
        return [:]
    }
    static func artists(_ root: Any) -> [OnlineArtistReference] {
        func walk(_ value: Any) -> [OnlineArtistReference] {
            if let dict = value as? [String: Any] {
                if let label = dict["text"] as? String,
                   let endpoint = nodes("browseEndpoint", in: dict).first,
                   let id = endpoint["browseId"] as? String, id.hasPrefix("UC") {
                    return [OnlineArtistReference(provider: .youtubeMusic, sourceID: id, name: label)]
                }
                return dict.keys.sorted().flatMap { walk(dict[$0] as Any) }
            }
            return (value as? [Any] ?? []).flatMap(walk)
        }
        var seen: Set<String> = []
        return walk(root).filter { seen.insert($0.id).inserted }
    }
    static func track(_ row: [String: Any], fallbackArtists: [OnlineArtistReference] = [], album: String? = nil) -> OnlineMusicTrack? {
        if row["isPlayable"] as? Bool == false { return nil }
        let data = row["playlistItemData"] as? [String: Any]
        let watch = nodes("watchEndpoint", in: row).first
        guard let id = row["videoId"] as? String ?? data?["videoId"] as? String ?? watch?["videoId"] as? String, !id.isEmpty else { return nil }
        let columns = nodes("musicResponsiveListItemFlexColumnRenderer", in: row)
        let title = text(row["title"]).isEmpty ? text(columns.first?["text"]) : text(row["title"])
        guard !title.isEmpty else { return nil }
        var credits = artists(row)
        if credits.isEmpty { credits = fallbackArtists }
        let subtitle = text(row["longBylineText"]).isEmpty ? text(columns.dropFirst().first?["text"]) : text(row["longBylineText"])
        let albumColumn = columns.first { nodes("browseEndpoint", in: $0).contains { ($0["browseId"] as? String ?? "").hasPrefix("MPRE") } }
        return OnlineMusicTrack(provider: .youtubeMusic, sourceID: id, title: title, artists: credits,
            artistName: credits.isEmpty ? subtitle : credits.map(\.name).joined(separator: ", "),
            album: album ?? albumColumn.map { text($0["text"]) }, artworkURL: artwork(row))
    }
    static func continuation(_ root: Any) -> String? {
        for key in ["nextContinuationData", "reloadContinuationData", "continuationCommand"] {
            if let value = nodes(key, in: root).first?[key == "continuationCommand" ? "token" : "continuation"] as? String { return value }
        }
        return nil
    }
    static func trackPage(_ root: Any, fallbackArtists: [OnlineArtistReference] = [], album: String? = nil) -> (tracks: [OnlineMusicTrack], skipped: Int, continuation: String?, recognized: Bool) {
        var containers: [[String: Any]] = []
        for key in ["musicPlaylistShelfRenderer", "musicPlaylistShelfContinuation", "musicShelfContinuation", "appendContinuationItemsAction"] {
            containers = nodes(key, in: root)
            if !containers.isEmpty { break }
        }
        if containers.isEmpty { containers = nodes("musicShelfRenderer", in: root) }
        guard !containers.isEmpty else { return ([], 0, nil, false) }
        var tracks: [OnlineMusicTrack] = [], skipped = 0
        for container in containers {
            for row in nodes("musicResponsiveListItemRenderer", in: container) {
                if let parsed = track(row, fallbackArtists: fallbackArtists, album: album) { tracks.append(parsed) }
                else { skipped += 1 }
            }
        }
        return (tracks, skipped, continuation(containers), true)
    }
    static func albums(_ root: Any, artist: OnlineArtistReference) -> [OnlineMusicAlbum] {
        nodes("musicTwoRowItemRenderer", in: root).compactMap { row in
            guard let endpoint = nodes("browseEndpoint", in: row["navigationEndpoint"] as Any).first,
                  let id = endpoint["browseId"] as? String, id.hasPrefix("MPRE") else { return nil }
            let title = text(row["title"])
            guard !title.isEmpty else { return nil }
            let subtitle = text(row["subtitle"])
            let year = subtitle.split(separator: " ").first { $0.count == 4 && Int($0) != nil }.map(String.init)
            return OnlineMusicAlbum(provider: .youtubeMusic, sourceID: id, title: title,
                artistName: artist.name, artists: [artist], artworkURL: artwork(row), year: year)
        }
    }
}
