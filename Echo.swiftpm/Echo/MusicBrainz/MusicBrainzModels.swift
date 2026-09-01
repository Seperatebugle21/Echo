import Foundation


// MARK: - Echo Track

struct MusicBrainzTrack:
    Identifiable,
    Hashable,
    Sendable {

    let id: String

    let title: String
    let artist: String
    let album: String

    let durationMS: Int

    let releaseID: String?


    // MARK: - Artwork

    var artworkURL: URL? {

        guard
            let releaseID,
            !releaseID.isEmpty
        else {

            return nil
        }


        return URL(
            string:
                "https://coverartarchive.org/release/\(releaseID)/front-250"
        )
    }


    // MARK: - MusicBrainz URL

    var musicBrainzURL: URL {

        URL(
            string:
                "https://musicbrainz.org/recording/\(id)"
        )
        ??
        URL(
            string:
                "https://musicbrainz.org"
        )!
    }


    // MARK: - Convert To Existing Echo Model

    //
    // Echo's current download flow already accepts SpotifyTrack.
    //
    // The spotifyURL property is effectively only used as a
    // persistent source/reference URL by Fetch.
    //
    // For MusicBrainz tracks we simply store the MusicBrainz URL
    // there, allowing the existing detail/download flow to work
    // without duplicating everything.

    var echoTrack: SpotifyTrack {

        SpotifyTrack(
            id:
                "musicbrainz-\(id)",

            name:
                title,

            artist:
                artist,

            album:
                album,

            durationMS:
                durationMS,

            artworkURL:
                artworkURL,

            spotifyURL:
                musicBrainzURL
        )
    }
}


// MARK: - Search Response

struct MusicBrainzRecordingSearchResponse:
    Decodable,
    Sendable {

    let recordings:
        [MusicBrainzRecording]
}


// MARK: - Recording

struct MusicBrainzRecording:
    Decodable,
    Sendable {

    let id: String
    let title: String

    let length: Int?

    let score: Int?

    let artistCredit:
        [MusicBrainzArtistCredit]?

    let releases:
        [MusicBrainzRelease]?


    enum CodingKeys:
        String,
        CodingKey {

        case id
        case title
        case length
        case score

        case artistCredit =
            "artist-credit"

        case releases
    }


    // MARK: - Convert

    var echoTrack:
        MusicBrainzTrack {

        let artistName =
            resolvedArtist


        let preferredRelease =
            releases?
                .first(
                    where: {
                        release in


                        release.status?
                            .lowercased()
                        ==
                        "official"
                    }
                )
            ??
            releases?.first


        return MusicBrainzTrack(
            id:
                id,

            title:
                title,

            artist:
                artistName,

            album:
                preferredRelease?.title
                ??
                "Unknown Album",

            durationMS:
                length
                ??
                0,

            releaseID:
                preferredRelease?.id
        )
    }


    // MARK: - Artist

    private var resolvedArtist:
        String {

        guard
            let artistCredit,
            !artistCredit.isEmpty
        else {

            return "Unknown Artist"
        }


        var result =
            ""


        for credit in artistCredit {

            result +=
                credit.name


            if let joinphrase =
                credit.joinphrase {

                result +=
                    joinphrase
            }
        }


        let cleaned =
            result
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )


        return cleaned.isEmpty
        ? "Unknown Artist"
        : cleaned
    }
}


// MARK: - Artist Credit

struct MusicBrainzArtistCredit:
    Decodable,
    Sendable {

    let name: String

    let joinphrase:
        String?
}


// MARK: - Release

struct MusicBrainzRelease:
    Decodable,
    Sendable {

    let id: String

    let title: String

    let status:
        String?
}
