import XCTest

final class ArtistCreditsTests: XCTestCase {
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
