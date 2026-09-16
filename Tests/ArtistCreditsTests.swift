import XCTest

final class ArtistCreditsTests: XCTestCase {
    func testRepeatedCreditsKeepEverySongAndStructuredCreditsTakePrecedence() {
        let songs = (0..<1_000).map {
            Song(title: "Track \($0)", artist: "Alpha & Beta", fileName: "\($0).mp3")
        }
        let structured = Song(title: "Band", artist: "Alpha & Beta", fileName: "band.mp3",
                              artistNames: ["Alpha & Beta"])
        let groups = ArtistCredits.groups(for: songs + [structured], unknownName: "Unknown")
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.first { $0.name == "Alpha" }?.songs.map(\.id), songs.map(\.id))
        XCTAssertEqual(groups.first { $0.name == "Beta" }?.songs.map(\.id), songs.map(\.id))
        XCTAssertEqual(groups.first { $0.name == "Alpha & Beta" }?.songs.map(\.id), [structured.id])
    }

    func testRegroupAfterEditingAndRemovingSongsDoesNotReuseStaleCredits() {
        var song = Song(title: "Track", artist: "Alpha & Beta", fileName: "track.mp3")
        _ = ArtistCredits.groups(for: [song], unknownName: "Unknown")
        song.artist = "Gamma & Delta"
        XCTAssertEqual(Set(ArtistCredits.groups(for: [song], unknownName: "Unknown").map(\.name)),
                       ["Gamma", "Delta"])
        XCTAssertTrue(ArtistCredits.groups(for: [], unknownName: "Unknown").isEmpty)
    }

    func testLargeLibraryGroupingPerformance() {
        let songs = (0..<10_000).map {
            Song(title: "Track \($0)", artist: "Artist \($0 % 200) & Guest", fileName: "\($0).mp3")
        }
        measure {
            let groups = ArtistCredits.groups(for: songs, unknownName: "Unknown")
            XCTAssertEqual(groups.count, 201)
            XCTAssertEqual(groups.first { $0.name == "Guest" }?.songs.count, 10_000)
        }
    }

    func testCollaborationAppearsUnderEveryArtist() {
        let collaboration = Song(title: "Together", artist: "AC/DC, Michael Jackson & Prince", fileName: "together.mp3")
        let solo = Song(title: "Solo", artist: "Michael Jackson", fileName: "solo.mp3")
        let groups = ArtistCredits.groups(for: [solo, collaboration], unknownName: "Unknown")
        XCTAssertEqual(Set(groups.map(\.name)), ["AC/DC", "Michael Jackson", "Prince"])
        XCTAssertEqual(groups.first { $0.name == "Michael Jackson" }?.songs.map(\.id), [solo.id, collaboration.id])
        XCTAssertEqual(groups.first { $0.name == "AC/DC" }?.songs.map(\.id), [collaboration.id])
        XCTAssertEqual(groups.first { $0.name == "Prince" }?.songs.map(\.id), [collaboration.id])
    }

    func testDuplicatesAndCasingDoNotDuplicateArtistsOrSongs() {
        let song = Song(title: "Together", artist: "Prince & prince, PRINCE", fileName: "test.mp3")
        let groups = ArtistCredits.groups(for: [song, song], unknownName: "Unknown")
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.songs.count, 1)
    }

    func testSlashAndKnownCompoundArtistNamesStayIntact() {
        XCTAssertEqual(ArtistCredits.names(in: "AC/DC"), ["AC/DC"])
        XCTAssertEqual(ArtistCredits.names(in: "Earth, Wind & Fire, Prince"), ["Earth, Wind & Fire", "Prince"])
        XCTAssertEqual(ArtistCredits.names(in: "Simon & Garfunkel"), ["Simon & Garfunkel"])
        XCTAssertEqual(ArtistCredits.names(in: "Tyler, The Creator & Prince"), ["Tyler, The Creator", "Prince"])
    }

    func testFeaturedArtistsAndSeparators() {
        XCTAssertEqual(ArtistCredits.names(in: "Alpha feat. Beta; Gamma"), ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(ArtistCredits.names(in: "Alpha (feat. Beta)"), ["Alpha", "Beta"])
        XCTAssertEqual(ArtistCredits.names(in: "Alpha x Beta / Gamma"), ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(ArtistCredits.names(in: "Alpha&Beta"), ["Alpha", "Beta"])
    }

    func testStructuredCreditsPreserveUnusualBandNames() {
        let song = Song(title: "Together", artist: "An Unknown & Band, Guest", fileName: "test.mp3",
                        artistNames: ["An Unknown & Band", "Guest"])
        XCTAssertEqual(ArtistCredits.names(for: song), ["An Unknown & Band", "Guest"])
    }

    func testBlankCreditsUseUnknownArtist() {
        let song = Song(title: "Untitled", artist: " , & ; ", fileName: "test.mp3")
        let groups = ArtistCredits.groups(for: [song], unknownName: "Unknown")
        XCTAssertEqual(groups.first?.name, "Unknown")
        XCTAssertEqual(groups.first?.songs.map(\.id), [song.id])
    }
}
