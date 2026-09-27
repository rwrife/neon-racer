import XCTest

final class NeonRacerUITests: XCTestCase {
    @MainActor
    func testLaunchesRaceFromMainMenu() {
        let app = XCUIApplication()
        app.launchArguments.append("UITestSkipTutorial")
        app.launchArguments.append("UITestDisableRunRecovery")
        app.launch()
        dismissRunRecoveryIfPresent(app)

        XCTAssertTrue(app.staticTexts["NEON RACER"].waitForExistence(timeout: 5))
        app.buttons["START ENGINE"].tap()
        XCTAssertTrue(app.buttons["Pause race"].waitForExistence(timeout: 5))
        app.buttons["Pause race"].tap()
        XCTAssertTrue(app.staticTexts["RACE PAUSED"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["RETURN TO TITLE"].waitForExistence(timeout: 5))
        app.buttons["RETURN TO TITLE"].tap()
        app.buttons["Return to Title"].tap()
        XCTAssertTrue(app.staticTexts["NEON RACER"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsAndResetRequireConfirmation() {
        let app = XCUIApplication()
        app.launchArguments.append("UITestSkipTutorial")
        app.launchArguments.append("UITestDisableRunRecovery")
        app.launch()
        dismissRunRecoveryIfPresent(app)

        app.buttons["SETTINGS"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        let resetButton = app.buttons["Reset Player Data"]
        for _ in 0..<3 where !resetButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(resetButton.waitForExistence(timeout: 2))
        resetButton.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 2))
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["START ENGINE"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testFinishResultsAndRetry() {
        let app = XCUIApplication()
        app.launchArguments.append("UITestSkipTutorial")
        app.launchArguments.append("UITestDisableRunRecovery")
        app.launchArguments.append("UITestFinishRace")
        app.launch()
        dismissRunRecoveryIfPresent(app)

        app.buttons["START ENGINE"].tap()
        XCTAssertTrue(app.buttons["COMPLETE TEST RACE"].waitForExistence(timeout: 5))
        app.buttons["COMPLETE TEST RACE"].tap()
        XCTAssertTrue(app.staticTexts["FINISH!"].waitForExistence(timeout: 5))
        app.buttons["RETRY"].tap()
        XCTAssertTrue(app.buttons["Pause race"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLandscapeRaceShowsCriticalHUDValues() {
        let app = XCUIApplication()
        app.launchArguments.append("UITestSkipTutorial")
        app.launchArguments.append("UITestDisableRunRecovery")
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        dismissRunRecoveryIfPresent(app)

        XCTAssertTrue(app.buttons["START ENGINE"].waitForExistence(timeout: 5))
        app.buttons["START ENGINE"].tap()

        XCTAssertTrue(app.staticTexts["SPEED"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SCORE"].exists)
        XCTAssertTrue(app.staticTexts["TIME"].exists)
        XCTAssertTrue(app.staticTexts["BOOST"].exists)
    }

    @MainActor
    func testBackgroundingRaceReturnsToPausedOverlay() {
        let app = XCUIApplication()
        app.launchArguments.append("UITestStartRace")
        app.launchArguments.append("UITestAutoDrive")
        app.launch()

        XCTAssertTrue(app.buttons["Pause race"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(app.staticTexts["RACE PAUSED"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["RESUME"].exists)
        app.buttons["RETURN TO TITLE"].tap()
        app.buttons["Return to Title"].tap()
    }

    @MainActor
    func testFirstRunTutorialAppearsAndCanBeSkipped() {
        let app = XCUIApplication()
        app.launchArguments.append("UITestForceTutorial")
        app.launchArguments.append("UITestDisableRunRecovery")
        app.launch()
        dismissRunRecoveryIfPresent(app)

        XCTAssertTrue(app.staticTexts["NEON RACER"].waitForExistence(timeout: 5))
        app.buttons["START ENGINE"].tap()
        XCTAssertTrue(app.staticTexts["DRIVING TIP"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["FIND YOUR LINE"].exists)
        app.buttons["SKIP"].tap()
        XCTAssertFalse(app.staticTexts["DRIVING TIP"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Pause race"].exists)
    }

    @MainActor
    private func dismissRunRecoveryIfPresent(_ app: XCUIApplication) {
        let discardRun = app.buttons["DISCARD RUN"]
        if discardRun.waitForExistence(timeout: 1) {
            discardRun.tap()
        }
    }
}
