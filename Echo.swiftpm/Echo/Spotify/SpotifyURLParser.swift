import Foundation

enum SpotifyContentType {
    case track
    case album
    case playlist
}

struct SpotifyReference {
    let type: SpotifyContentType
    let id: String
    let url: URL
}

enum SpotifyURLParser {

    static func parse(_ input: String) -> SpotifyReference? {
        let value = input.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if value.hasPrefix("spotify:") {
            return parseURI(value)
        }

        guard
            let url = URL(string: value),
            let host = url.host?.lowercased()
        else {
            return nil
        }

        guard host == "open.spotify.com" ||
              host == "spotify.com"
        else {
            return nil
        }

        let components = url.pathComponents

        guard components.count >= 3 else {
            return nil
        }

        let typeString = components[1]
        let id = components[2]

        let type: SpotifyContentType

        switch typeString {
        case "track":
            type = .track

        case "album":
            type = .album

        case "playlist":
            type = .playlist

        default:
            return nil
        }

        return SpotifyReference(
            type: type,
            id: id,
            url: url
        )
    }

    private static func parseURI(
        _ uri: String
    ) -> SpotifyReference? {

        let parts = uri.split(separator: ":")

        guard parts.count == 3,
              parts[0] == "spotify"
        else {
            return nil
        }

        let type: SpotifyContentType

        switch parts[1] {
        case "track":
            type = .track

        case "album":
            type = .album

        case "playlist":
            type = .playlist

        default:
            return nil
        }

        let id = String(parts[2])

        guard let url = URL(
            string:
                "https://open.spotify.com/\(parts[1])/\(id)"
        ) else {
            return nil
        }

        return SpotifyReference(
            type: type,
            id: id,
            url: url
        )
    }
}
