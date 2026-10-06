import SwiftUI
import XCTest
final class EchoThemeTests: XCTestCase {
    @MainActor func testSeparatePalettesFollowSystemRatherThanTextColor() throws {
        let domain = "EchoThemeTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let theme = EchoTheme(defaults: defaults)
        theme.mode = "custom"
        theme.first = "DCEDE6"
        let original = theme.sharedPalette
        XCTAssertFalse(theme.separatePalettes)
        theme.separatePalettes = true
        XCTAssertEqual(theme.light, original); XCTAssertEqual(theme.dark, original)
        var dark = theme.dark
        dark.first = "000000"; dark.second = "364C43"
        dark.gradient = true; dark.direction = "vertical"; dark.whiteText = false
        theme.setPalette(dark, for: .dark)
        XCTAssertNil(theme.colorScheme)
        XCTAssertEqual(theme.palette(for: .dark), dark)
        XCTAssertEqual(theme.palette(for: .light), original)
        let restored = EchoTheme(defaults: defaults)
        XCTAssertTrue(restored.separatePalettes)
        XCTAssertEqual(restored.dark, dark); XCTAssertEqual(restored.light, original)
        restored.separatePalettes = false
        XCTAssertEqual(restored.palette(for: .dark), original)
        XCTAssertEqual(restored.palette(for: .light), original)
        restored.separatePalettes = true
        XCTAssertEqual(restored.palette(for: .dark), dark)
    }
    @MainActor func testThemePreservesLegacyAndPersistsCustom() throws {
        let domain = "EchoThemeTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("dark", forKey: "appearanceMode"); defaults.set("black", forKey: "darkBackgroundStyle")
        let theme = EchoTheme(defaults: defaults)
        XCTAssertEqual(theme.mode, "dark"); XCTAssertEqual(theme.darkStyle, "black")
        theme.mode = "custom"; theme.gradient = true; theme.first = "F4E9D8"; theme.second = "182235"; theme.whiteText = false
        let reloaded = EchoTheme(defaults: defaults)
        XCTAssertTrue(reloaded.gradient); XCTAssertEqual(reloaded.first, "F4E9D8"); XCTAssertEqual(reloaded.colorScheme, .light)
    }
}
