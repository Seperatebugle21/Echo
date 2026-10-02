import SwiftUI
import XCTest
final class EchoThemeTests: XCTestCase {
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
