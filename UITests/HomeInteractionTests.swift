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
        capture("home-after-start-playback")
        XCTAssertFalse(closePlayer.isHittable, "Starting playback must keep Home visible")
        XCTAssertTrue(app.buttons["home-settings"].isHittable)
    }

    private func waitForPlayerOpen() {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: closePlayer)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func waitForHome() {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["home-settings"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func visibleMiniPlayer() -> XCUIElement {
        // SwiftUI can expose the gesture label and its children with the same ID.
        // Select a rendered element; the following tap/drag assertions verify the actual action.
        let query = app.buttons.matching(identifier: "mini-player-open")
        return query.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? query.firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCardCanStartPlaybackAndCloseIntoTheFirstMiniPlayer() {
        launch()
        app.buttons["home-now-playing-card"].tap()
        waitForPlayerOpen()
        closePlayer.tap()
        waitForHome()
        XCTAssertTrue(app.buttons["home-settings"].isHittable)
        let miniPlayer = visibleMiniPlayer()
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(miniPlayer.frame.minY, app.frame.height * 0.6)
        miniPlayer.tap()
        waitForPlayerOpen()
    }

    func testHeaderButtonsOpenTheirOwnSheetsDuringPlayback() {
        launch()
        startPlayback()
        app.buttons["home-settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        XCTAssertFalse(closePlayer.isHittable)
        capture("home-settings-sheet")

        launch()
        startPlayback()
        app.buttons["home-search"].tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(closePlayer.isHittable)
        capture("home-search-sheet")
    }

    func testSpotlightControlsAndCardHaveSeparateActions() {
        launch()
        startPlayback()
        toggle.tap()
        waitForLabel("Play")
        XCTAssertFalse(closePlayer.isHittable)
        XCTAssertTrue(app.buttons["home-settings"].isHittable)
        toggle.tap()
        waitForLabel("Pause")
        XCTAssertFalse(closePlayer.isHittable)
        capture("home-light-playing")

        app.buttons["home-now-playing-card"].tap()
        waitForPlayerOpen()
        capture("home-card-expanded")
        closePlayer.tap()
        waitForHome()
        XCTAssertTrue(app.buttons["home-settings"].isHittable)
    }

    func testMiniPlayerStillOpensAndClosesAfterCardPresentation() {
        launch()
        startPlayback()
        app.buttons["home-now-playing-card"].tap()
        waitForPlayerOpen()
        closePlayer.tap()
        waitForHome()

        var miniPlayer = visibleMiniPlayer()
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(miniPlayer.frame.minY, app.frame.height * 0.6)
        miniPlayer.tap()
        waitForPlayerOpen()
        closePlayer.tap()
        waitForHome()
        miniPlayer = visibleMiniPlayer()

        miniPlayer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        waitForPlayerOpen()
        closePlayer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        waitForHome()
        capture("home-mini-player-restored")
    }

    func testDiscoveryKeepsAllEligibleMusicCardsAndThemePreviews() {
        launch()
        for _ in 0..<8 {
            let artists = app.buttons["home-discovery-artists"]
            let songs = app.buttons["home-discovery-songs"]
            if (artists.exists && artists.isHittable) || (songs.exists && songs.isHittable) { break }
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
