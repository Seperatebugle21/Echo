import Foundation

enum SpotifyCatalogJSON {
    static func artwork(_ json: [String: Any]) -> URL? {
        guard let raw = (json["images"] as? [[String: Any]])?.first?["url"] as? String else { return nil }
        return URL(string: raw)
    }
    static func artists(_ json: [String: Any]) -> [OnlineArtistReference] {
        (json["artists"] as? [[String: Any]] ?? []).compactMap {
            guard let id = $0["id"] as? String, let name = $0["name"] as? String else { return nil }
            return OnlineArtistReference(provider: .spotify, sourceID: id, name: name)
        }
    }
    static func album(_ json: [String: Any]) -> OnlineMusicAlbum? {
        guard let id = json["id"] as? String, let title = json["name"] as? String else { return nil }
        let credits = artists(json)
        return OnlineMusicAlbum(provider: .spotify, sourceID: id, title: title,
            artistName: credits.map(\.name).joined(separator: ", "), artists: credits,
            artworkURL: artwork(json), year: (json["release_date"] as? String).map { String($0.prefix(4)) })
    }
    static func track(_ json: [String: Any], album: OnlineMusicAlbum) -> OnlineMusicTrack? {
        guard json["is_playable"] as? Bool != false, json["is_local"] as? Bool != true,
              let id = json["id"] as? String, let title = json["name"] as? String else { return nil }
        let credits = artists(json)
        return OnlineMusicTrack(provider: .spotify, sourceID: id, title: title, artists: credits,
            artistName: credits.map(\.name).joined(separator: ", "), album: album.title,
            artworkURL: album.artworkURL, durationMS: json["duration_ms"] as? Int ?? 0,
            recordingID: (json["external_ids"] as? [String: String])?["isrc"])
    }
}
