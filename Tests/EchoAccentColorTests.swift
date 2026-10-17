import Foundation
import XCTest

final class EchoAccentColorTests: XCTestCase {
    func testHexColorsNormalizeWithoutLosingCustomColors() {
        XCTAssertEqual(EchoAccentColor(hex: " #1a80ff \n").hex, "1A80FF")
        XCTAssertEqual(EchoAccentColor(hex: "000000").hex, "000000")
        XCTAssertEqual(EchoAccentColor(hex: "FFFFFF").hex, "FFFFFF")
    }
    func testInvalidStoredColorsFallBackToEchoRed() {
        for hex in ["", "red", "GGGGGG", "12345", "12345678", "+FFFFF", "##123456"] {
            XCTAssertEqual(EchoAccentColor(hex: hex).hex, EchoAccentColor.defaultHex)
        }
    }
    func testSwatchForegroundIsLegibleForDarkAndBrightColors() {
        XCTAssertTrue(EchoAccentColor(hex: "000000").usesWhiteForeground)
        XCTAssertTrue(EchoAccentPreset.indigo.color.usesWhiteForeground)
        XCTAssertFalse(EchoAccentColor(hex: "FFFFFF").usesWhiteForeground)
        XCTAssertFalse(EchoAccentPreset.gold.color.usesWhiteForeground)
    }
    func testPresetsAreDistinctAndIncludeOriginalAccent() {
        let colors = EchoAccentPreset.allCases.map { $0.color.hex }
        XCTAssertEqual(Set(colors).count, colors.count)
        XCTAssertEqual(EchoAccentPreset.red.color.hex, "FF3B30")
        XCTAssertTrue(colors.allSatisfy { $0.count == 6 && UInt32($0, radix: 16) != nil })
    }
}
