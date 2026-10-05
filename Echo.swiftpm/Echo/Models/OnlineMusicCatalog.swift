import Foundation

enum MusicCatalogProvider: String, Codable, Sendable {
    case spotify, youtubeMusic
    var name: String { self == .spotify ? "Spotify" : "YouTube Music" }
}

struct OnlineArtistReference: Codable, Hashable, Identifiable, Sendable {
    let provider: MusicCatalogProvider
    let sourceID: String
    var name: String
    var artworkURL: URL?
    var id: String { "\(provider.rawValue):\(sourceID)" }
    var sourceURL: URL {
        switch provider {
        case .spotify: URL(string: "https://open.spotify.com/artist/\(sourceID)")!
        case .youtubeMusic: URL(string: "https://music.youtube.com/channel/\(sourceID)")!
        }
    }
}

struct OnlineMusicTrack: Codable, Hashable, Identifiable, Sendable {
    let provider: MusicCatalogProvider
    let sourceID: String
    var title: String
    var artists: [OnlineArtistReference]
    var artistName: String
    var album: String?
    var artworkURL: URL?
    var durationMS: Int = 0
    var recordingID: String?
    var id: String { "\(provider.rawValue):\(sourceID)" }
    var sourceURL: URL {
        switch provider {
        case .spotify: URL(string: "https://open.spotify.com/track/\(sourceID)")!
        case .youtubeMusic: URL(string: "https://music.youtube.com/watch?v=\(sourceID)")!
        }
    }
}

struct OnlineMusicAlbum: Codable, Hashable, Identifiable, Sendable {
    let provider: MusicCatalogProvider
    let sourceID: String
    var title: String
    var artistName: String
    var artists: [OnlineArtistReference]
    var artworkURL: URL?
    var year: String?
    var id: String { "\(provider.rawValue):\(sourceID)" }
}

struct OnlineTrackCollection: Sendable {
    var title: String
    var artworkURL: URL?
    var tracks: [OnlineMusicTrack]
    var skippedCount: Int = 0
}

enum MusicCatalogError: LocalizedError, Equatable {
    case invalidLink, unavailable, empty, malformed, incomplete, spotifyConnection, network
    var errorDescription: String? {
        let key: String
        switch self {
        case .invalidLink: key = "catalog_invalid_link"
        case .unavailable: key = "catalog_unavailable"
        case .empty: key = "catalog_empty"
        case .malformed: key = "catalog_response_changed"
        case .incomplete: key = "catalog_incomplete"
        case .spotifyConnection: key = "catalog_spotify_connection"
        case .network: key = "catalog_network_error"
        }
        return String(localized: String.LocalizationValue(key))
    }
}

enum OnlineCatalogLogic {
    static func uniqueTracks(_ tracks: [OnlineMusicTrack]) -> [OnlineMusicTrack] {
        var ids: Set<String> = [], recordings: Set<String> = []
        return tracks.filter { track in
            guard ids.insert(track.id).inserted else { return false }
            guard let recording = track.recordingID, !recording.isEmpty else { return true }
            return recordings.insert(recording.uppercased()).inserted
        }
    }
    static func belongs(_ track: OnlineMusicTrack, to artist: OnlineArtistReference) -> Bool {
        track.artists.contains { $0.id == artist.id }
    }
    static func matches(_ track: OnlineMusicTrack, query: String) -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || [track.title, track.artistName, track.album ?? ""].contains { $0.localizedStandardContains(value) }
    }
    static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func refillSelection(_ selected: [String], available: [String], limit: Int = 10,
                                shuffle: ([String]) -> [String] = { $0.shuffled() }) -> [String] {
        let valid = Set(available)
        var seen: Set<String> = []
        var result = selected.filter { valid.contains($0) && seen.insert($0).inserted }
        result += shuffle(available.filter { seen.insert($0).inserted }).prefix(max(0, limit - result.count))
        return Array(result.prefix(limit))
    }
}

enum YouTubeMusicReference: Equatable, Sendable {
    case song(String), playlist(String), artist(String), album(String)
    static func parse(_ url: URL) throws -> Self {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              ["music.youtube.com", "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"].contains(url.host?.lowercased() ?? "") else {
            throw MusicCatalogError.invalidLink
        }
        let path = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        func valid(_ id: String) -> Bool { !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") } }
        if url.host?.lowercased() == "youtu.be", let id = path.first, valid(id) { return .song(id) }
        if path.first == "watch", let id = value("v"), valid(id) { return .song(id) }
        if path.first == "playlist", let id = value("list"), valid(id) { return .playlist(id) }
        if path.count == 2, ["channel", "browse"].contains(path[0]), valid(path[1]) {
            if path[1].hasPrefix("UC") { return .artist(path[1]) }
            if path[1].hasPrefix("MPRE") { return .album(path[1]) }
            if path[1].hasPrefix("VL") { return .playlist(String(path[1].dropFirst(2))) }
        }
        if path.count == 2, ["shorts", "embed"].contains(path[0]), valid(path[1]) { return .song(path[1]) }
        throw MusicCatalogError.invalidLink
    }
}
