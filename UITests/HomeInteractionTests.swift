import XCTest

/// Runs against the real app with the disposable simulator's seeded music library.
final class HomeInteractionTests: XCTestCase {
    private let app = XCUIApplication()
    private var toggle: XCUIElement { app.buttons["home-now-playing-toggle"] }
    private var closePlayer: XCUIElement { app.buttons["Close Now Playing"] }

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(theme: String = "light") {
        app.terminate()
        app.launchArguments = ["-hasCompletedEchoOnboarding", "YES", "-selectedLanguage", "en",
                               "-AppleLanguages", "(en)", "-appearanceMode", theme,
                               "-theme.first", "182235", "-theme.second", "64478C",
                               "-theme.gradient", "YES", "-theme.whiteText", "YES"]
        app.launch()
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
    }

    private func waitForLabel(_ label: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func startPlayback() {
        if toggle.label != "Pause" { toggle.tap() }
        waitForLabel("Pause")
        XCTAssertFalse(closePlayer.exists, "Starting playback must keep Home visible")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHeaderButtonsOpenTheirOwnSheetsDuringPlayback() {
        launch()
        startPlayback()
        app.buttons["home-settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        XCTAssertFalse(closePlayer.exists)
        capture("home-settings-sheet")

        launch()
        startPlayback()
        app.buttons["home-search"].tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(closePlayer.exists)
        capture("home-search-sheet")
    }

    func testSpotlightControlsAndCardHaveSeparateActions() {
        launch()
        startPlayback()
        toggle.tap()
        waitForLabel("Play")
        XCTAssertFalse(closePlayer.exists)
        XCTAssertTrue(app.buttons["home-settings"].isHittable)
        toggle.tap()
        waitForLabel("Pause")
        XCTAssertFalse(closePlayer.exists)
        capture("home-light-playing")

        app.buttons["home-now-playing-card"].tap()
        XCTAssertTrue(closePlayer.waitForExistence(timeout: 8))
        capture("home-card-expanded")
        closePlayer.tap()
        XCTAssertTrue(app.buttons["home-settings"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["home-settings"].isHittable)
    }

    func testMiniPlayerStillOpensAndClosesAfterCardPresentation() {
        launch()
        startPlayback()
        app.buttons["home-now-playing-card"].tap()
        XCTAssertTrue(closePlayer.waitForExistence(timeout: 8))
        closePlayer.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))

        let miniPlayer = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ AND identifier != %@", "Morning light, The North", "home-now-playing-card")
        ).firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(miniPlayer.frame.minY, app.frame.height * 0.6)
        miniPlayer.tap()
        XCTAssertTrue(closePlayer.waitForExistence(timeout: 8))
        closePlayer.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertTrue(miniPlayer.isHittable)

        miniPlayer.swipeUp(velocity: .slow)
        XCTAssertTrue(closePlayer.waitForExistence(timeout: 8))
        closePlayer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        capture("home-mini-player-restored")
    }

    func testDiscoveryKeepsAllEligibleMusicCardsAndThemePreviews() {
        launch()
        for _ in 0..<8 {
            if app.buttons["home-discovery-artists"].exists || app.buttons["home-discovery-songs"].exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["home-discovery-artists"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home-discovery-songs"].waitForExistence(timeout: 5))
        capture("home-discovery-all-music-cards")
        for theme in ["dark", "custom"] {
            launch(theme: theme)
            startPlayback()
            capture("home-\(theme)-playing")
        }
    }
}
