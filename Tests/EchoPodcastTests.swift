import Foundation
import XCTest

final class EchoPodcastTests: XCTestCase {
    private let show = PodcastShow(id: 42, title: "Mysteries", author: "Creator",
        artworkURL: URL(string: "https://example.com/cover.jpg"), feedURL: URL(string: "https://example.com/feed")!)

    func testRSSMetadataCDATAAndDeduplication() throws {
        let xml = """
        <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:content="http://purl.org/rss/1.0/modules/content/">
          <channel><title>Mysteries</title>
            <item><guid>episode-one</guid><title>The first mystery</title>
              <pubDate>Fri, 18 Sep 2026 09:00:00 +0200</pubDate>
              <itunes:duration>1:02:03</itunes:duration>
              <content:encoded><![CDATA[<p>A mysterious &amp; surprising story.</p>]]></content:encoded>
              <enclosure url="https://example.com/one.mp3?token=a&amp;b=c" type="audio/mpeg"/>
            </item>
            <item><guid>episode-one</guid><title>Duplicate</title><enclosure url="https://example.com/other.mp3" type="audio/mpeg"/></item>
            <item><guid>episode-two</guid><title>Older episode</title>
              <pubDate>Thu, 17 Sep 2026 09:00:00 GMT</pubDate><itunes:duration>120</itunes:duration>
              <description>A short description</description><enclosure url="/two.m4a" type="audio/mp4"/>
            </item>
          </channel>
        </rss>
        """
        let episodes = try PodcastFeedParser.parse(Data(xml.utf8), show: show)
        XCTAssertEqual(episodes.count, 2)
        XCTAssertEqual(episodes[0].id, "42:episode-one")
        XCTAssertEqual(episodes[0].duration, 3723)
        XCTAssertEqual(episodes[0].description, "A mysterious & surprising story.")
        XCTAssertNotNil(episodes[0].published)
        XCTAssertNotNil(episodes[1].published)
        XCTAssertEqual(episodes[1].audioURL.absoluteString, "https://example.com/two.m4a")
        XCTAssertEqual(episodes[0].artworkURL, show.artworkURL)
        XCTAssertEqual(try PodcastFeedParser.parse(Data(xml.utf8), show: show)[0].playbackID, episodes[0].playbackID)
    }

    func testMissingGUIDUsesAudioURLAndSkipsNonAudioItems() throws {
        let xml = """
        <rss><channel>
          <item><title>Audio</title><enclosure url="https://example.com/audio.mp3"/></item>
          <item><title>Video</title><enclosure url="https://example.com/video.mp4" type="video/mp4"/></item>
          <item><title>Invalid</title><enclosure url="file:///private/audio.mp3"/></item>
          <item><title>No enclosure</title></item>
        </channel></rss>
        """
        let episodes = try PodcastFeedParser.parse(Data(xml.utf8), show: show)
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes[0].id, "42:https://example.com/audio.mp3")
        XCTAssertNil(episodes[0].duration)
        XCTAssertNil(episodes[0].published)
    }

    func testInvalidFeedsAndDurations() {
        XCTAssertThrowsError(try PodcastFeedParser.parse(Data("<html/>".utf8), show: show))
        XCTAssertThrowsError(try PodcastFeedParser.parse(Data("<rss><channel>".utf8), show: show))
        XCTAssertEqual(PodcastFeedParser.duration(" 42:30 "), 2550)
        for value in ["NaN", "inf", "-2", "bad", "1:2:3:4"] {
            XCTAssertNil(PodcastFeedParser.duration(value))
        }
    }

    func testLibraryRoundTripKeepsSavesIndependentOfDownloads() throws {
        let episode = PodcastEpisode(id: "42:one", show: show, title: "Episode", description: "Description",
            published: nil, duration: 120, audioURL: URL(string: "https://example.com/one.mp3")!, artworkURL: nil)
        var state = PodcastLibraryState()
        state.episodes[episode.id] = episode
        state.savedEpisodeIDs.insert(episode.id)
        state.downloads[episode.id] = "one.mp3"
        state.listening[episode.id] = PodcastListeningState(position: 45, played: false)
        state.downloads.removeValue(forKey: episode.id)
        let restored = try JSONDecoder().decode(PodcastLibraryState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(restored.savedEpisodeIDs.contains(episode.id))
        XCTAssertTrue(restored.shows.isEmpty)
        XCTAssertEqual(restored.listening[episode.id]?.position, 45)
        XCTAssertEqual(restored.episodes[episode.id], episode)
        XCTAssertTrue(restored.downloads.isEmpty)
    }

    func testTabMigrationOnlyChangesOldDefaultAndRemovalPersists() {
        let old = #"{"tabs":["home","library","fetch","search"],"startTab":"home"}"#
        var migrated = TabBarConfiguration.decode(old)
        XCTAssertEqual(migrated.tabs, [.home, .library, .podcasts, .fetch, .search])
        migrated.remove(.podcasts)
        XCTAssertEqual(TabBarConfiguration.decode(migrated.encoded).tabs, [.home, .library, .fetch, .search])
        let custom = #"{"tabs":["search","favorites","home"],"startTab":"search"}"#
        XCTAssertEqual(TabBarConfiguration.decode(custom).tabs, [.search, .favorites, .home])
        XCTAssertEqual(TabBarConfiguration.decode(custom).startTab, .search)
    }
}
