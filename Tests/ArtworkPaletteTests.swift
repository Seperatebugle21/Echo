import Foundation
import XCTest

final class ArtworkPaletteTests: XCTestCase {
    private func pixels(_ parts: [(r: UInt8, g: UInt8, b: UInt8, count: Int)]) -> [UInt8] {
        parts.flatMap { part in Array(repeating: [part.r, part.g, part.b, 255], count: part.count).flatMap { $0 } }
    }

    func testAccentIsTheVividColorEvenWhenNotDominant() throws {
        let palette = try XCTUnwrap(ArtworkPalette.from(rgba: pixels([(40, 40, 40, 700), (220, 30, 40, 300)])))
        let accent = try XCTUnwrap(palette.accent)
        XCTAssertGreaterThan(accent.r, 0.7); XCTAssertLessThan(accent.g, 0.3)
    }

    func testGrayscaleArtworkKeepsTheChosenAccent() throws {
        let palette = try XCTUnwrap(ArtworkPalette.from(rgba: pixels([(20, 20, 20, 500), (230, 230, 230, 500)])))
        XCTAssertNil(palette.accent)
        XCTAssertEqual(palette.darkBackground.count, 2)
    }

    func testAccentsAreReadableOnLightAndDarkBackgrounds() throws {
        // Dark navy is hard to read on dark backgrounds; pale yellow on light ones.
        for color: (UInt8, UInt8, UInt8) in [(20, 30, 120), (250, 240, 120), (0, 160, 80)] {
            let palette = try XCTUnwrap(ArtworkPalette.from(rgba: pixels([(color.0, color.1, color.2, 100)])))
            let dark = try XCTUnwrap(palette.accentForDark), light = try XCTUnwrap(palette.accentForLight)
            XCTAssertGreaterThanOrEqual(ArtworkPalette.RGB.contrast(dark, .init(r: 0.1, g: 0.1, b: 0.1)), 3, "\(color)")
            XCTAssertGreaterThanOrEqual(ArtworkPalette.RGB.contrast(light, .init(r: 0.97, g: 0.97, b: 0.97)), 3, "\(color)")
        }
    }

    func testBackgroundsKeepTextLegible() throws {
        let palette = try XCTUnwrap(ArtworkPalette.from(rgba: pixels([(255, 200, 0, 600), (0, 120, 255, 400)])))
        let white = ArtworkPalette.RGB(r: 1, g: 1, b: 1), black = ArtworkPalette.RGB(r: 0, g: 0, b: 0)
        for color in palette.darkBackground { XCTAssertGreaterThanOrEqual(ArtworkPalette.RGB.contrast(color, white), 7) }
        for color in palette.lightBackground { XCTAssertGreaterThanOrEqual(ArtworkPalette.RGB.contrast(color, black), 7) }
        XCTAssertNotEqual(palette.darkBackground[0], palette.darkBackground[1], "two distinct cover colors")
    }

    func testTransparentOrEmptyImagesHaveNoPalette() {
        XCTAssertNil(ArtworkPalette.from(rgba: []))
        XCTAssertNil(ArtworkPalette.from(rgba: [255, 0, 0, 0, 0, 255, 0, 0]))
    }

    func testHSBRoundTrip() {
        let color = ArtworkPalette.RGB(r: 0.2, g: 0.6, b: 0.9)
        let hsb = color.hsb
        let back = ArtworkPalette.RGB(hue: hsb.h, saturation: hsb.s, brightness: hsb.b)
        XCTAssertEqual(back.r, color.r, accuracy: 0.001); XCTAssertEqual(back.g, color.g, accuracy: 0.001); XCTAssertEqual(back.b, color.b, accuracy: 0.001)
    }

    @MainActor func testArtworkSettingsPersist() throws {
        let domain = "ArtworkPaletteTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let theme = EchoTheme(defaults: defaults)
        XCTAssertFalse(theme.accentFromArtwork); XCTAssertFalse(theme.backgroundFromArtwork)
        theme.accentFromArtwork = true; theme.backgroundFromArtwork = true
        let restored = EchoTheme(defaults: defaults)
        XCTAssertTrue(restored.accentFromArtwork); XCTAssertTrue(restored.backgroundFromArtwork)
        XCTAssertNil(restored.artworkPalette)
    }
}
