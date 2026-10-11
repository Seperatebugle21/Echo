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

    private func waitForMiniPlayer() -> XCUIElement {
        let minimized = app.buttons["Open miniplayer"]
        if minimized.exists && minimized.isHittable { minimized.tap() }
        let query = app.buttons.matching(identifier: "mini-player-open")
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 12))
        // Select the rendered gesture surface among the duplicate accessibility
        // elements, then verify its real touch action by opening the full player.
        let candidates = query.allElementsBoundByIndex.filter {
            let frame = $0.frame
            return frame.width > 20 && frame.height > 20 && frame.midY > app.frame.height * 0.65
                && app.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
        }.sorted { $0.frame.width > $1.frame.width }
        for element in query.allElementsBoundByIndex {
            print("MiniPlayer candidate frame: \(element.frame)")
        }
        XCTAssertFalse(candidates.isEmpty, "The real MiniPlayer must be rendered above the tab bar")
        return candidates.first ?? query.firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollTo(_ identifier: String) -> XCUIElement {
        let element = app.buttons[identifier]
        for _ in 0..<24 {
            let dockTop = app.buttons.matching(identifier: "mini-player-open").allElementsBoundByIndex
                .map(\.frame).filter { $0.width > 20 && $0.midY > app.frame.height * 0.65 }
                .map(\.minY).min() ?? app.frame.height - 145
            let viewport = CGRect(x: app.frame.minX, y: app.frame.minY + 140,
                                  width: app.frame.width, height: max(0, dockTop - app.frame.minY - 148))
            let frame = element.exists ? element.frame : .zero
            if frame.width > 0 && viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) && element.isHittable { return element }
            // Short drags can recover when a restored navigation offset places the
            // target above us, and keep gestures inside Home rather than the dock.
            let up = frame.width == 0 || frame.midY > viewport.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: up ? 0.67 : 0.35))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: up ? 0.35 : 0.67))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        capture("home-unreachable-" + identifier)
        print("Unreachable Home control frame: \(element.exists ? element.frame : .zero)")
        XCTFail("Home control was not reachable: \(identifier)")
        return element
    }

    func testIntelligenceUniversePreservesMusicAndReturnsHome() {
        launch()
        startPlayback()
        app.buttons["home-intelligence"].tap()
        let close = app.buttons["intelligence-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Echo Intelligence"].exists)
        XCTAssertFalse(app.staticTexts["The 3D renderer could not start. Conversations remain available."].exists)
        let universe = app.otherElements["Interactive golden universe"]
        if universe.exists {
            universe.swipeLeft()
            universe.doubleTap()
        }
        capture("echo-intelligence-universe")
        XCTAssertTrue(app.buttons["Pause music"].exists)
        close.tap()
        waitForHome()
        waitForLabel("Pause")
    }

    func testSmartVibesSurpriseAndRealQueueOpen() {
        launch()
        scrollTo("smart-vibe-energy").tap()
        capture("home-smart-vibes")
        waitForMiniPlayer().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitForPlayerOpen()
        closePlayer.tap()
        scrollTo("smart-surprise-play").tap()
        capture("home-smart-surprise")
        scrollTo("smart-queue-open").tap()
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Now Playing"].exists)
        capture("home-smart-real-queue")
    }

    func testEchoFlowPauseResumeAndStopPreservePlayback() {
        launch()
        var flow = scrollTo("smart-flow-play")
        flow.tap()
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Pause'"), object: flow)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 8), .completed)
        capture("home-smart-flow-active")
        visibleMiniPlayer().tap()
        waitForPlayerOpen()
        for _ in 0..<6 {
            let next = app.buttons.matching(identifier: "next_track_action").allElementsBoundByIndex.first { $0.isHittable }
            XCTAssertNotNil(next)
            next?.tap()
        }
        closePlayer.tap()
        flow = app.buttons["smart-flow-play"]
        let homeFlow = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: flow)
        XCTAssertEqual(XCTWaiter.wait(for: [homeFlow], timeout: 8), .completed)
        scrollTo("smart-queue-open").tap()
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(app.cells.count, 7, "Flow should refill the real queue after six skips")
        capture("home-smart-flow-refilled-real-queue")
        app.buttons["Close"].tap()
        // Return to the Flow card after verifying the queue below it.
        flow = scrollTo("smart-flow-play")
        flow.tap()
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Play'"), object: flow)
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 8), .completed)
        flow.tap()
        app.buttons["smart-flow-mode"].tap()
        XCTAssertTrue(app.buttons["smart-flow-stop"].waitForExistence(timeout: 5))
        app.buttons["smart-flow-stop"].tap()
        flow = app.buttons["smart-flow-play"]
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Start Echo Flow'"), object: flow)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 8), .completed)
        capture("home-smart-flow-after-stop-before-dock-check")
        waitForMiniPlayer().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitForPlayerOpen()
        XCTAssertTrue(app.buttons["pause_action"].isHittable, "Stopping Flow must keep playback running")
        closePlayer.tap()
        capture("home-smart-flow-stopped-queue-kept")
    }

    func testWeeklyStatisticsAndSmartSectionsAcrossThemes() {
        for theme in ["light", "dark", "custom"] {
            launch(theme: theme)
            startPlayback()
            let statistics = scrollTo("smart-week-open")
            XCTAssertTrue(app.staticTexts["Hidden Gems"].exists, "Concurrent library preparation must publish the completed gem and vibe selections")
            XCTAssertFalse(app.buttons["Refresh Hidden Gems"].exists)
            statistics.tap()
            XCTAssertTrue(app.navigationBars["Your Week in Music"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["Listening time by day"].exists)
            capture("home-smart-statistics-\(theme)")
            app.navigationBars.buttons.firstMatch.tap()
            let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == false"), object: app.navigationBars["Your Week in Music"])
            XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 8), .completed)
            scrollTo("smart-flow-play")
            capture("home-smart-sections-\(theme)")
            scrollTo("smart-queue-open")
            XCTAssertTrue(app.staticTexts["Time Machine"].exists, "The seeded historical counts should expose a real historical collection")
            XCTAssertTrue(app.staticTexts["Albums Worth Revisiting"].exists)
            capture("home-smart-history-and-queue-\(theme)")
        }
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
            let viewport = app.frame.insetBy(dx: 0, dy: 180)
            let artistsVisible = artists.exists && viewport.contains(CGPoint(x: artists.frame.midX, y: artists.frame.midY))
            let songsVisible = songs.exists && viewport.contains(CGPoint(x: songs.frame.midX, y: songs.frame.midY))
            if artistsVisible || songsVisible { break }
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
