import XCTest

final class NeonRacerUITests: XCTestCase {
    @MainActor
    func testLaunchesRaceFromMainMenu() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["NEON RACER"].waitForExistence(timeout: 5))
        app.buttons["START ENGINE"].tap()
        XCTAssertTrue(app.buttons["Pause race"].waitForExistence(timeout: 5))
        app.buttons["Pause race"].tap()
        XCTAssertTrue(app.staticTexts["RACE PAUSED"].waitForExistence(timeout: 2))
        app.buttons["RETURN TO TITLE"].tap()
        app.buttons["Return to Title"].tap()
        XCTAssertTrue(app.staticTexts["NEON RACER"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsAndResetRequireConfirmation() {
        let app = XCUIApplication()
        app.launch()

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
        app.launchArguments.append("UITestFinishRace")
        app.launch()

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
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()

        XCTAssertTrue(app.buttons["START ENGINE"].waitForExistence(timeout: 5))
        app.buttons["START ENGINE"].tap()

        XCTAssertTrue(app.staticTexts["SPEED"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SCORE"].exists)
        XCTAssertTrue(app.staticTexts["TIME"].exists)
        XCTAssertTrue(app.staticTexts["BOOST"].exists)
    }
}
