import Foundation
import XCTest

final class EchoCatalogTests: XCTestCase {
    private let artist = OnlineArtistReference(provider: .youtubeMusic, sourceID: "UCartist", name: "Artist")
    private func track(_ id: String, title: String = "Song", recording: String? = nil) -> OnlineMusicTrack {
        OnlineMusicTrack(provider: .youtubeMusic, sourceID: id, title: title, artists: [artist], artistName: artist.name,
                         album: "Album", recordingID: recording)
    }
    private func row(_ id: String?) -> [String: Any] {
        var row: [String: Any] = ["flexColumns": [
            ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Song " + (id ?? "missing")]]]]],
            ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Artist", "navigationEndpoint": ["browseEndpoint": ["browseId": "UCartist"]]]]]]]
        ]]
        if let id { row["playlistItemData"] = ["videoId": id] }
        return ["musicResponsiveListItemRenderer": row]
    }
    private func page(_ ids: [String?], token: String? = nil, key: String = "musicPlaylistShelfRenderer") -> [String: Any] {
        var shelf: [String: Any] = ["contents": ids.map(row)]
        if let token { shelf["continuations"] = [["nextContinuationData": ["continuation": token]]] }
        return [key: shelf]
    }
    private func service(_ handler: @escaping (URLRequest) throws -> (Int, [String: Any])) -> YouTubeMusicMetadata {
        CatalogURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CatalogURLProtocol.self]
        return YouTubeMusicMetadata(session: URLSession(configuration: config))
    }
    override func tearDown() { CatalogURLProtocol.handler = nil; super.tearDown() }
    private func fixture(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "youtube-" + name, withExtension: "json"))
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    func testCapturedPublicResponsesParseTracksArtistAlbumsAndContinuation() throws {
        let song = try fixture("song")
        let selected = try XCTUnwrap(YouTubeMusicJSON.nodes("playlistPanelVideoRenderer", in: song).first)
        let track = try XCTUnwrap(YouTubeMusicJSON.track(selected))
        XCTAssertEqual(track.title, "Never Gonna Give You Up")
        XCTAssertEqual(track.artistName, "Rick Astley")
        XCTAssertGreaterThan(track.durationMS, 0)
        let playlist = YouTubeMusicJSON.trackPage(try fixture("playlist"))
        let next = YouTubeMusicJSON.trackPage(try fixture("playlist-next"))
        XCTAssertTrue(playlist.recognized); XCTAssertTrue(next.recognized)
        XCTAssertEqual(playlist.tracks.count, 2); XCTAssertEqual(next.tracks.count, 2)
        XCTAssertNotNil(playlist.continuation)
        XCTAssertEqual(playlist.tracks[0].sourceID, "hpSrLjc5SMs")
        let artistJSON = try fixture("artist")
        let header = YouTubeMusicJSON.header(artistJSON)
        XCTAssertEqual(YouTubeMusicJSON.text(header["title"]), "Oasis")
        let oasis = OnlineArtistReference(provider: .youtubeMusic, sourceID: "UCmMUZbaYdNH0bEd1PAlAqsA", name: "Oasis")
        XCTAssertEqual(YouTubeMusicJSON.albums(artistJSON, artist: oasis).count, 2)
        XCTAssertEqual(YouTubeMusicJSON.albums(try fixture("artist-albums"), artist: oasis).count, 2)
        let albumJSON = try fixture("album")
        let credits = YouTubeMusicJSON.artists(YouTubeMusicJSON.header(albumJSON))
        let albumPage = YouTubeMusicJSON.trackPage(albumJSON, fallbackArtists: credits, album: "Morning Glory")
        XCTAssertTrue(albumPage.recognized)
        XCTAssertEqual(albumPage.tracks.map(\.title), ["Hello", "Roll With It"])
        XCTAssertTrue(albumPage.tracks.allSatisfy { OnlineCatalogLogic.belongs($0, to: oasis) })
    }
    func testArtistSearchUsesRowEndpointAndRejectsAmbiguousNames() async throws {
        let search = try fixture("artist-search")
        let api = service { _ in (200, search) }
        let match = try await api.searchArtist("Oasis")
        XCTAssertEqual(match?.sourceID, "UCmMUZbaYdNH0bEd1PAlAqsA")
        let title: [String: Any] = ["flexColumns": [["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Oasis"]]]]]]]
        var a = title, b = title
        a["navigationEndpoint"] = ["browseEndpoint": ["browseId": "UCfirst"]]
        b["navigationEndpoint"] = ["browseEndpoint": ["browseId": "UCsecond"]]
        let ambiguous = service { _ in (200, ["items": [["musicResponsiveListItemRenderer": a], ["musicResponsiveListItemRenderer": b]]]) }
        let ambiguousMatch = try await ambiguous.searchArtist("Oasis")
        XCTAssertNil(ambiguousMatch)
    }

    func testSongLinkDoesNotBecomePlaylistAndShareParametersAreIgnored() throws {
        XCTAssertEqual(try YouTubeMusicReference.parse(URL(string: "https://music.youtube.com/watch?v=video123&list=PLother&si=abc")!), .song("video123"))
        XCTAssertEqual(try YouTubeMusicReference.parse(URL(string: "https://music.youtube.com/playlist?list=PLother&si=abc")!), .playlist("PLother"))
        XCTAssertEqual(try YouTubeMusicReference.parse(URL(string: "https://youtu.be/video123?si=abc")!), .song("video123"))
        XCTAssertEqual(try YouTubeMusicReference.parse(URL(string: "https://music.youtube.com/channel/UCartist?si=abc")!), .artist("UCartist"))
        XCTAssertEqual(try YouTubeMusicReference.parse(URL(string: "https://music.youtube.com/browse/MPREalbum")!), .album("MPREalbum"))
        for url in ["https://music.youtube.com.evil.test/watch?v=x", "file://music.youtube.com/watch?v=x", "https://music.youtube.com/playlist", "https://music.youtube.com/watch?v="] {
            XCTAssertThrowsError(try YouTubeMusicReference.parse(URL(string: url)!))
        }
        XCTAssertEqual(SpotifyURLParser.parse("https://open.spotify.com/intl-nl/artist/123?si=test")?.id, "123")
        if case .artist = SpotifyURLParser.parse("spotify:artist:123")?.type {} else { XCTFail("Artist URI not recognized") }
        XCTAssertNil(SpotifyURLParser.parse("https://open.spotify.com.evil.test/artist/123"))
    }
    func testPlaylistPaginationPreservesOrderAndCountsUnavailableRows() async throws {
        let first = page(["first", nil], token: "next")
        let second = page(["second"], key: "musicPlaylistShelfContinuation")
        let api = service { request in
            if request.httpMethod != "POST" { return (200, [:]) }
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertNotNil(body["context"])
            return (200, body["continuation"] == nil ? first : second)
        }
        let result = try await api.playlist("PLtest")
        XCTAssertEqual(result.tracks.map(\.sourceID), ["first", "second"])
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.tracks[0].artists.map(\.sourceID), ["UCartist"])
    }
    func testNewContinuationShapeAndEmptyPlaylist() async throws {
        let first = page(["first"], token: "next")
        let second: [String: Any] = ["onResponseReceivedActions": [["appendContinuationItemsAction": ["continuationItems": [row("second")]]]]]
        let api = service { request in
            if request.httpMethod != "POST" { return (200, [:]) }
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            return (200, body["continuation"] == nil ? first : second)
        }
        let full = try await api.playlist("PLtest")
        XCTAssertEqual(full.tracks.map(\.sourceID), ["first", "second"])
        let empty = page([])
        let emptyAPI = service { _ in (200, empty) }
        let emptyResult = try await emptyAPI.playlist("PLempty")
        XCTAssertTrue(emptyResult.tracks.isEmpty)
    }
    func testRepeatedContinuationFailsInsteadOfClaimingCompleteCatalog() async throws {
        let response = page(["song"], token: "repeat")
        let api = service { _ in (200, response) }
        do { _ = try await api.playlist("PLtest"); XCTFail("Expected incomplete catalog") }
        catch { XCTAssertEqual(error as? MusicCatalogError, .incomplete) }
    }
    func testPrivateAndMalformedPlaylistsAreDifferentFromEmpty() async throws {
        let forbidden = service { request in (request.httpMethod == "POST" ? 403 : 200, [:]) }
        do { _ = try await forbidden.playlist("private"); XCTFail("Expected unavailable") }
        catch { XCTAssertEqual(error as? MusicCatalogError, .unavailable) }
        let malformed = service { _ in (200, ["unexpected": true]) }
        do { _ = try await malformed.playlist("changed"); XCTFail("Expected malformed") }
        catch { XCTAssertEqual(error as? MusicCatalogError, .malformed) }
    }
    func testCancelledRequestIsNotReportedAsMetadataFailure() async {
        let api = service { request in
            if request.httpMethod == "POST" { throw URLError(.cancelled) }
            return (200, [:])
        }
        do { _ = try await api.playlist("PLtest"); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testSongMetadataUsesRequestedVideoAndNotTheRestOfTheQueue() async throws {
        let api = service { _ in (200, ["contents": [
            "playlistPanelVideoRenderer": ["videoId": "song", "title": ["runs": [["text": "Chosen"]]], "longBylineText": ["runs": [["text": "Artist"]]]]
        ]]) }
        let result = try await api.song("song")
        XCTAssertEqual(result.title, "Chosen")
        XCTAssertEqual(result.sourceID, "song")
        XCTAssertEqual(result.artistName, "Artist")
    }
    func testArtistMembershipAndRecordingDeduplicationPreserveDifferentVersions() throws {
        let original = track("original", recording: "GBTEST000001")
        let sameRecording = track("reissue", recording: "gbtest000001")
        let live = track("live", title: "Song (Live)", recording: "GBTEST000002")
        var other = track("other"); other.artists = [OnlineArtistReference(provider: .youtubeMusic, sourceID: "UCother", name: "Artist")]
        let selected = [original, sameRecording, live, original, other].filter { OnlineCatalogLogic.belongs($0, to: artist) }
        XCTAssertEqual(OnlineCatalogLogic.uniqueTracks(selected).map(\.sourceID), ["original", "live"])
        XCTAssertTrue(OnlineCatalogLogic.matches(live, query: "live"))
        XCTAssertTrue(OnlineCatalogLogic.matches(original, query: "album"))
        let saved = try JSONDecoder().decode(OnlineMusicTrack.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(saved, original)
    }
    func testSpotifyCompilationMembershipUsesTrackArtists() {
        let json: [String: Any] = ["id": "compilation", "name": "Compilation", "artists": [["id": "various", "name": "Various Artists"]]]
        let album = SpotifyCatalogJSON.album(json)!
        let included = SpotifyCatalogJSON.track(["id": "song", "name": "Featuring", "artists": [["id": "target", "name": "Target"], ["id": "guest", "name": "Guest"]]], album: album)!
        let excluded = SpotifyCatalogJSON.track(["id": "other", "name": "Other", "artists": [["id": "other", "name": "Other"]]], album: album)!
        let target = OnlineArtistReference(provider: .spotify, sourceID: "target", name: "Target")
        XCTAssertTrue(OnlineCatalogLogic.belongs(included, to: target))
        XCTAssertFalse(OnlineCatalogLogic.belongs(excluded, to: target))
    }
    func testHomeSelectionStaysStableRefillsAndDoesNotInventAlbums() {
        let pick = OnlineCatalogLogic.refillSelection([], available: ["a", "b", "c"], shuffle: { $0 })
        XCTAssertEqual(pick, ["a", "b", "c"])
        XCTAssertEqual(OnlineCatalogLogic.refillSelection(pick, available: ["c", "b", "a"], shuffle: { $0.reversed() }), pick)
        XCTAssertEqual(OnlineCatalogLogic.refillSelection(pick, available: ["b", "c", "d"], shuffle: { $0 }), ["b", "c", "d"])
        XCTAssertEqual(OnlineCatalogLogic.refillSelection([], available: (0..<20).map(String.init), shuffle: { $0 }).count, 10)
        XCTAssertTrue(OnlineCatalogLogic.refillSelection(pick, available: []).isEmpty)
    }
    func testDiscoveryCacheSurvivesRestartWithoutNeedingNetwork() throws {
        let suite = "EchoCatalogTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(OnlineCatalogPersistence.load(from: defaults).albums.isEmpty)
        let album = OnlineMusicAlbum(provider: .youtubeMusic, sourceID: "MPREalbum", title: "Album",
            artistName: artist.name, artists: [artist], artworkURL: URL(string: "https://example.com/cover.jpg"))
        OnlineCatalogPersistence.save(artists: [artist], albums: [album], to: defaults)
        let restored = OnlineCatalogPersistence.load(from: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(restored.artists, [artist]); XCTAssertEqual(restored.albums, [album])
        defaults.set(Data("invalid cache".utf8), forKey: "echo.online.albums.v1")
        XCTAssertTrue(OnlineCatalogPersistence.load(from: defaults).albums.isEmpty)
        XCTAssertEqual(OnlineCatalogPersistence.load(from: defaults).artists, [artist])
    }
    func testLocalAlbumGroupingExcludesMissingAlbumsAndPodcasts() {
        var a = Song(title: "A", artist: "Artist", fileName: "a.mp3", dateAdded: Date())
        a.album = "Album"
        let b = Song(title: "B", artist: "Artist", fileName: "b.mp3", album: "Album")
        var noAlbum = a; noAlbum.album = "  "
        var podcast = a; podcast.podcastEpisodeID = "episode"
        let groups = LibraryAlbums.groups(from: [a, b, noAlbum, podcast])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].songs.map(\.title), ["A", "B"])
    }
}

private final class CatalogURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var storedHandler: ((URLRequest) throws -> (Int, [String: Any]))?
    static var handler: ((URLRequest) throws -> (Int, [String: Any]))? {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var sent = request
            if sent.httpBody == nil, let stream = sent.httpBodyStream {
                stream.open(); defer { stream.close() }
                var body = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    body.append(contentsOf: buffer.prefix(read))
                }
                sent.httpBody = body
            }
            let (status, json) = try Self.handler!(sent)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: json))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
