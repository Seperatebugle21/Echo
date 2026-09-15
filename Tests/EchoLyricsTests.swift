import Foundation
import XCTest

final class EchoLyricsTests: XCTestCase {
    private var previousMusixmatch: Any?
    private var previousGenius: Any?

    override func setUp() {
        super.setUp()
        previousMusixmatch = UserDefaults.standard.object(forKey: "musixmatchApiKey")
        previousGenius = UserDefaults.standard.object(forKey: "geniusAccessToken")
        UserDefaults.standard.set("test-key", forKey: "musixmatchApiKey")
        UserDefaults.standard.set("test-token", forKey: "geniusAccessToken")
    }

    override func tearDown() {
        UserDefaults.standard.set(previousMusixmatch, forKey: "musixmatchApiKey")
        UserDefaults.standard.set(previousGenius, forKey: "geniusAccessToken")
        LyricsURLProtocol.handler = nil
        super.tearDown()
    }

    private func manager() -> LyricsManager {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LyricsURLProtocol.self]
        return LyricsManager(session: URLSession(configuration: config))
    }

    private let song = Song(title: "Paper Lantern", artist: "Example Artist", fileName: "test.wav")

    func testMatchingRejectsVersionsArtistsAndDuration() {
        func score(_ title: String, _ artist: String = "Example Artist", _ duration: Double? = 180) -> Double? {
            LyricsMatching.score(title: "Paper Lantern", artist: "Example Artist", duration: 180,
                                 candidateTitle: title, candidateArtist: artist, candidateDuration: duration)
        }
        XCTAssertNotNil(score("PÁPER LANTERN (Official Audio)"))
        XCTAssertNil(score("Paper Lantern (Live)"))
        XCTAssertNil(score("Paper Lantern (Remix)"))
        XCTAssertNil(score("Paper Lantern", "Another Artist"))
        XCTAssertNil(score("Paper Lantern", "Example Artist", 230))
        XCTAssertNotNil(score("Paper Lantern", "Example Artist", nil))
        XCTAssertNil(score("Paper"))
    }

    func testRealTitleWordsAreNotRemovedAsMetadata() {
        XCTAssertNil(LyricsMatching.score(title: "Video Games", artist: "Example", duration: 100,
            candidateTitle: "Games", candidateArtist: "Example", candidateDuration: 100))
    }

    func testGeniusHTMLPreservesLinesEntitiesAndExcludesControls() throws {
        let html = """
        <h1>Not lyrics</h1><div data-lyrics-container="true"><div class="LyricsHeader-test">Header</div>One &amp; two<br><a>Three <b>four</b></a><span data-exclude-from-selection="true">Ad</span></div>
        <div data-lyrics-container="true">Five &#233;<br/>Six<script>bad()</script></div><footer>Footer</footer>
        """
        XCTAssertEqual(try GeniusLyricsParser.parse(html), "One & two\nThree four\n\nFive é\nSix")
        XCTAssertNil(try GeniusLyricsParser.parse("<html><h1>Access denied</h1></html>"))
        XCTAssertEqual(try GeniusLyricsParser.parse("<div class='lyrics'><p>One<br>Two</p></div>"), "One\nTwo")
    }

    func testSyncedLyricsWinOverMusixmatchPlainText() async {
        LyricsURLProtocol.handler = { request in
            switch request.url!.path {
            case "/ws/1.1/matcher.track.get": return (200, Self.trackJSON)
            case "/ws/1.1/track.lyrics.get": return (200, Self.plainJSON)
            case "/api/get": return (200, Self.lrclibJSON(synced: "[00:01.00]Fixture"))
            default: XCTFail("Unexpected request: \(request.url!.path)"); return (404, "{}")
            }
        }
        let result = await manager().fetchLyrics(for: song, duration: 180)
        XCTAssertEqual(result?.source, .lrclib)
        XCTAssertEqual(result?.syncedLyrics, "[00:01.00]Fixture")
    }

    func testMusixmatchPlainFallbackWhenNoSyncedLyricsExist() async {
        LyricsURLProtocol.handler = { request in
            switch request.url!.path {
            case "/ws/1.1/matcher.track.get": return (200, Self.trackJSON)
            case "/ws/1.1/track.lyrics.get": return (200, Self.plainJSON)
            case "/api/get": return (200, Self.lrclibJSON(synced: nil))
            case "/api/search": return (200, "[]")
            case "/search": return (200, "{\"response\":{\"hits\":[]}}")
            default: return (404, "{}")
            }
        }
        let result = await manager().fetchLyrics(for: song, duration: 180)
        XCTAssertEqual(result?.source, .musixmatch)
        XCTAssertEqual(result?.plainLyrics, "Musixmatch fixture")
    }

    func testManualGeniusUsesPageWithoutSendingToken() async {
        LyricsURLProtocol.handler = { request in
            if request.url?.host == "api.genius.com" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
                return (200, #"{"response":{"hits":[{"result":{"title":"Paper Lantern","artist_names":"Example Artist","full_title":"Paper Lantern","url":"https://genius.com/example-lyrics"}}]}}"#)
            }
            XCTAssertEqual(request.url?.host, "genius.com")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, "<div data-lyrics-container='true'>Test line<br>Second line</div>")
        }
        let result = await manager().fetchLyrics(for: song, duration: 180, provider: .genius)
        XCTAssertEqual(result?.source, .genius)
        XCTAssertEqual(result?.plainLyrics, "Test line\nSecond line")
    }

    func testMissingKeySkipsManualProvider() async {
        UserDefaults.standard.removeObject(forKey: "geniusAccessToken")
        LyricsURLProtocol.handler = { _ in XCTFail("No request expected"); return (500, "{}") }
        let result = await manager().fetchLyrics(for: song, duration: 180, provider: .genius)
        XCTAssertNil(result)
    }

    func testGeniusBlockedPageDoesNotBecomeLyrics() async {
        LyricsURLProtocol.handler = { request in
            if request.url?.host == "api.genius.com" {
                return (200, #"{"response":{"hits":[{"result":{"title":"Paper Lantern","artist_names":"Example Artist","full_title":"Paper Lantern","url":"https://genius.com/example-lyrics"}}]}}"#)
            }
            return (403, "<h1>Access denied</h1>")
        }
        let result = await manager().fetchLyrics(for: song, duration: 180, provider: .genius)
        XCTAssertNil(result)
        XCTAssertFalse(LyricsManager.isGeniusPage(URL(string: "https://genius.com.example.org/page")!))
        XCTAssertFalse(LyricsManager.isGeniusPage(URL(string: "http://genius.com/page")!))
    }

    func testSearchSkipsWrongVersionAndDuration() async {
        LyricsURLProtocol.handler = { request in
            if request.url!.path == "/api/get" { return (404, "{}") }
            XCTAssertEqual(request.url!.path, "/api/search")
            let wrongVersion = Self.lrclibJSON(synced: "[00:01]Wrong").replacingOccurrences(of: "Paper Lantern", with: "Paper Lantern (Live)")
            let wrongDuration = Self.lrclibJSON(synced: "[00:01]Wrong").replacingOccurrences(of: "180", with: "260")
            return (200, "[\(wrongVersion),\(wrongDuration),\(Self.lrclibJSON(synced: "[00:01]Correct"))]")
        }
        let result = await manager().fetchLyrics(for: song, duration: 180, provider: .lrclib)
        XCTAssertEqual(result?.syncedLyrics, "[00:01]Correct")
    }

    func testOldSavedSongsDecodeWithoutSourceFields() throws {
        var original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(song)) as? [String: Any])
        original.removeValue(forKey: "lyricsSource")
        original.removeValue(forKey: "lyricsSourceURL")
        let decoded = try JSONDecoder().decode(Song.self, from: JSONSerialization.data(withJSONObject: original))
        XCTAssertNil(decoded.lyricsSource)
        XCTAssertEqual(decoded.id, song.id)
    }

    private static let trackJSON = #"{"message":{"header":{"status_code":200},"body":{"track":{"track_id":1,"track_name":"Paper Lantern","artist_name":"Example Artist","track_length":180}}}}"#
    private static let plainJSON = #"{"message":{"header":{"status_code":200},"body":{"lyrics":{"lyrics_body":"Musixmatch fixture"}}}}"#
    private static func lrclibJSON(synced: String?) -> String {
        let object: [String: Any] = ["trackName":"Paper Lantern", "artistName":"Example Artist", "duration":180,
                                     "plainLyrics":"LRCLIB fixture", "syncedLyrics":synced as Any? ?? NSNull()]
        return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
}

private final class LyricsURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown)); return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
