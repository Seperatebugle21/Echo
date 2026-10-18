import Foundation
import XCTest

final class HomeConfigurationTests: XCTestCase {
    func testSavedOrderAndHiddenSectionsSurviveReload() {
        var configuration = HomeConfiguration.defaults
        configuration.remove(.recentlyPlayed)
        configuration.remove(.nowPlaying)
        configuration.add(.playlists)
        let reversed = Array(configuration.sections.reversed())
        configuration.reorder(reversed)
        XCTAssertEqual(HomeConfiguration.decode(configuration.encoded).sections, reversed)
        XCTAssertFalse(HomeConfiguration.decode(configuration.encoded).sections.contains(.recentlyPlayed))
    }

    func testEverySectionCanBeAddedWithoutAnUpperLimit() {
        var configuration = HomeConfiguration.decode("[\"nowPlaying\",\"quickAccess\"]")
        for section in HomeSection.allCases { configuration.add(section) }
        XCTAssertEqual(configuration.sections.count, HomeSection.allCases.count)
        configuration.add(.albums)
        XCTAssertEqual(configuration.sections.count, HomeSection.allCases.count)
        XCTAssertEqual(HomeConfiguration.decode(configuration.encoded), configuration)
    }

    func testMinimumIsEnforcedButNoSpecificSectionIsRequired() {
        var configuration = HomeConfiguration.defaults
        for section in HomeSection.allCases { configuration.remove(section) }
        XCTAssertEqual(configuration.sections.count, HomeConfiguration.minimumSections)
        XCTAssertFalse(configuration.sections.contains(.nowPlaying))
        let saved = configuration
        configuration.remove(configuration.sections[0])
        XCTAssertEqual(configuration, saved)
    }

    func testCorruptOrUndersizedLayoutsRecoverToDefaults() {
        for text in ["", "broken", "[]", "[\"nowPlaying\"]", "[\"unknown\"]"] {
            XCTAssertEqual(HomeConfiguration.decode(text), .defaults)
        }
    }

    func testUnknownAndDuplicateSectionsDoNotDiscardValidPreferences() {
        let configuration = HomeConfiguration.decode("[\"albums\",\"futureSection\",\"albums\",\"favorites\"]")
        XCTAssertEqual(configuration.sections, [.albums, .favorites])
    }

    func testInvalidReorderCannotRemoveOrDuplicateSections() {
        var configuration = HomeConfiguration.defaults
        configuration.reorder([.albums, .favorites])
        XCTAssertEqual(configuration, .defaults)
        configuration.reorder(Array(repeating: .albums, count: configuration.sections.count))
        XCTAssertEqual(configuration, .defaults)
    }
}
