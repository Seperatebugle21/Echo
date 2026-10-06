import Foundation

enum FetchURLResolvedContent: Identifiable {
    case spotifyTrack(SpotifyTrack)
    case spotifyPlaylist(SpotifyPlaylist, [SpotifyTrack])
    case youtubeTrack(FetchURLTrackPreview)
    case youtubePlaylist(FetchURLPlaylistPreview)
    case artist(OnlineArtistReference)
    case album(OnlineMusicAlbum)
    var id: String {
        switch self {
        case .spotifyTrack(let track): "spotify-track-\(track.id)"
        case .spotifyPlaylist(let playlist, _): "spotify-playlist-\(playlist.id)"
        case .youtubeTrack(let track): "youtube-track-\(track.id)"
        case .youtubePlaylist(let playlist): "youtube-playlist-\(playlist.id)"
        case .artist(let artist): "artist-\(artist.id)"
        case .album(let album): "album-\(album.id)"
        }
    }
    var title: String {
        switch self {
        case .spotifyTrack(let track): track.name
        case .spotifyPlaylist(let playlist, _): playlist.name
        case .youtubeTrack(let track): track.title
        case .youtubePlaylist(let playlist): playlist.title
        case .artist(let artist): artist.name
        case .album(let album): album.title
        }
    }
    var artworkURL: URL? {
        switch self {
        case .spotifyTrack(let track): track.artworkURL
        case .spotifyPlaylist(let playlist, _): playlist.artworkURL
        case .youtubeTrack(let track): track.artworkURL
        case .youtubePlaylist(let playlist): playlist.artworkURL
        case .artist(let artist): artist.artworkURL
        case .album(let album): album.artworkURL
        }
    }
    var sourceTitle: String {
        switch self {
        case .spotifyTrack, .spotifyPlaylist: "Spotify"
        case .youtubeTrack, .youtubePlaylist: "YouTube Music"
        case .artist(let artist): artist.provider.name
        case .album(let album): album.provider.name
        }
    }
    var isPlaylist: Bool {
        switch self { case .spotifyPlaylist, .youtubePlaylist: true; default: false }
    }
    var trackCount: Int {
        switch self {
        case .spotifyTrack, .youtubeTrack: 1
        case .spotifyPlaylist(_, let tracks): tracks.count
        case .youtubePlaylist(let playlist): playlist.tracks.count
        case .artist, .album: 0
        }
    }
}

struct FetchURLTrackPreview: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let sourceURL: URL
    var artists: [OnlineArtistReference] = []
    var album: String?
    var durationMS: Int = 0
    init(track: OnlineMusicTrack) {
        id = track.sourceID; title = track.title; artist = track.artistName
        artworkURL = track.artworkURL; sourceURL = track.sourceURL
        artists = track.artists; album = track.album; durationMS = track.durationMS
    }
    var catalogTrack: OnlineMusicTrack {
        OnlineMusicTrack(provider: .youtubeMusic, sourceID: id, title: title, artists: artists,
                         artistName: artist, album: album, artworkURL: artworkURL, durationMS: durationMS)
    }
}

struct FetchURLPlaylistPreview: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artworkURL: URL?
    let sourceURL: URL
    let tracks: [FetchURLTrackPreview]
    var skippedCount: Int = 0
}

enum FetchURLResolverError: LocalizedError {
    case invalidURL, unsupportedURL, unsupportedSpotifyType, youtubeMetadataFailed, emptyPlaylist
    var errorDescription: String? {
        switch self {
        case .invalidURL, .unsupportedURL: MusicCatalogError.invalidLink.errorDescription
        case .unsupportedSpotifyType: String(localized: "catalog_unsupported_spotify")
        case .youtubeMetadataFailed: MusicCatalogError.malformed.errorDescription
        case .emptyPlaylist: MusicCatalogError.empty.errorDescription
        }
    }
}

@MainActor
final class FetchURLResolver {
    static let shared = FetchURLResolver()
    private init() {}
    func resolve(_ input: String) async throws -> FetchURLResolvedContent {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reference = SpotifyURLParser.parse(value) { return try await resolveSpotify(reference) }
        guard let url = URL(string: value) else { throw MusicCatalogError.invalidLink }
        switch try YouTubeMusicReference.parse(url) {
        case .song(let id):
            return .youtubeTrack(FetchURLTrackPreview(track: try await YouTubeMusicMetadata.shared.song(id)))
        case .playlist(let id):
            let result = try await YouTubeMusicMetadata.shared.playlist(id)
            return .youtubePlaylist(FetchURLPlaylistPreview(id: id, title: result.title,
                artworkURL: result.artworkURL, sourceURL: url,
                tracks: result.tracks.map { FetchURLTrackPreview(track: $0) }, skippedCount: result.skippedCount))
        case .artist(let id):
            let (artist, _) = try await YouTubeMusicMetadata.shared.artistHeader(id)
            OnlineMusicCatalogStore.shared.remember(artist)
            return .artist(artist)
        case .album(let id):
            return .album(try await YouTubeMusicMetadata.shared.albumReference(id))
        }
    }
    private func resolveSpotify(
        _ reference:
            SpotifyReference
    ) async throws
        -> FetchURLResolvedContent {

        if reference.type == .artist {
            return .artist(OnlineArtistReference(provider: .spotify, sourceID: reference.id, name: ""))
        }
        if reference.type == .album {
            return .album(try await SpotifyAPI.shared.catalogAlbumReference(reference.id))
        }

        let result =
            try await
            SpotifyPublicURLResolver.shared
                .resolve(
                    reference:
                        reference
                )


        switch result {

        case .track(
            let track
        ):

            return
                .spotifyTrack(
                    track
                )


        case .playlist(
            let playlist,
            let tracks
        ):

            var resolvedTracks =
                tracks


            if SpotifyManager.shared
                .isConnected {

                do {

                    let authenticatedTracks =
                        try await
                        SpotifyAPI.shared
                            .getPlaylistTracks(
                                playlistID:
                                    playlist.id
                            )


                    if !authenticatedTracks.isEmpty {

                        resolvedTracks =
                            authenticatedTracks
                    }


                } catch {

                    print(
                        "Spotify authenticated playlist pagination fallback:",
                        error
                    )
                }
            }


            guard !resolvedTracks.isEmpty else {

                throw FetchURLResolverError
                    .emptyPlaylist
            }


            let resolvedPlaylist =
                SpotifyPlaylist(
                    id: playlist.id,
                    name: playlist.name,
                    artworkURL:
                        playlist.artworkURL,
                    spotifyURL:
                        playlist.spotifyURL,
                    trackCount:
                        resolvedTracks.count
                )


            return
                .spotifyPlaylist(
                    resolvedPlaylist,
                    resolvedTracks
                )
        }
    }



}
