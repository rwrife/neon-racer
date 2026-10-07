import XCTest

final class NeonRacerUITests: XCTestCase {
    @MainActor
    func testGarageCarPreviews() {
        let app = XCUIApplication()
        app.launchArguments = ["UITestDisableRunRecovery"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        app.buttons["GARAGE"].tap()
        XCTAssertTrue(app.navigationBars["Garage"].waitForExistence(timeout: 5))
        sleep(2)
        let preview = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        preview.name = "garage-car-previews"
        preview.lifetime = .keepAlways
        add(preview)
    }

    @MainActor
    func testHighQualityRaceOrientation() {
        let app = XCUIApplication()
        app.launchArguments = ["UITestDisableRunRecovery", "UITestStartRace", "UITestHideHUD"]
        app.launchEnvironment["NEON_RACER_QUALITY_TIER"] = "fidelity"
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["Pause race"].waitForExistence(timeout: 10))
        sleep(2)
        let race = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        race.name = "high-quality-race-orientation"
        race.lifetime = .keepAlways
        add(race)
    }

    @MainActor
    func testAppStoreScreenshots() {
        let app = XCUIApplication()
        app.launchArguments.append("UITestDisableRunRecovery")
        app.launchArguments.append("UITestAppStoreScreenshots")
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        dismissRunRecoveryIfPresent(app)

        XCTAssertTrue(app.buttons["RACE"].waitForExistence(timeout: 10))
        let title = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        title.name = "01-title"
        title.lifetime = .keepAlways
        add(title)

        app.buttons["RACE"].tap()
        XCTAssertTrue(app.buttons["Pause race"].waitForExistence(timeout: 10))
        if app.buttons["RESUME"].exists {
            app.buttons["RESUME"].tap()
        }
        sleep(4)
        app.buttons.matching(identifier: "arrow.up").firstMatch.press(forDuration: 2)
        let race = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        race.name = "02-race"
        race.lifetime = .keepAlways
        add(race)
    }

    @MainActor
    func testLaunchesRaceFromMainMenu() {
        let app = XCUIApplication()
        app.launchArguments.append("UITestDisableRunRecovery")
        app.launch()
        dismissRunRecoveryIfPresent(app)

        XCTAssertTrue(app.buttons["RACE"].waitForExistence(timeout: 5))
        app.buttons["RACE"].tap()
        XCTAssertTrue(app.buttons["Pause race"].waitForExistence(timeout: 5))
        app.buttons["Pause race"].tap()
        XCTAssertTrue(app.staticTexts["RACE PAUSED"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["RETURN TO TITLE"].waitForExistence(timeout: 5))
        app.buttons["RETURN TO TITLE"].tap()
        app.buttons["Return to Title"].tap()
        XCTAssertTrue(app.buttons["RACE"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsAndResetRequireConfirmation() {
        let app = XCUIApplication()
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
        XCTAssertTrue(app.buttons["RACE"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testFinishResultsAndRetry() {
        let app = XCUIApplication()
        app.launchArguments.append("UITestDisableRunRecovery")
        app.launchArguments.append("UITestFinishRace")
        app.launch()
        dismissRunRecoveryIfPresent(app)

        app.buttons["RACE"].tap()
        XCTAssertTrue(app.buttons["COMPLETE TEST RACE"].waitForExistence(timeout: 5))
        app.buttons["COMPLETE TEST RACE"].tap()
        XCTAssertTrue(app.staticTexts["FINISH!"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["RACE AGAIN"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["RETURN TO TITLE"].waitForExistence(timeout: 5))
        app.buttons["RACE AGAIN"].tap()
        XCTAssertTrue(app.buttons["Pause race"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLandscapeRaceShowsCriticalHUDValues() {
        let app = XCUIApplication()
        app.launchArguments.append("UITestDisableRunRecovery")
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        dismissRunRecoveryIfPresent(app)

        XCTAssertTrue(app.buttons["RACE"].waitForExistence(timeout: 5))
        app.buttons["RACE"].tap()

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
    func testHardwareKeyboardPausesAndResumesRace() {
        let app = XCUIApplication()
        app.launchArguments.append("UITestStartRace")
        app.launch()

        XCTAssertTrue(app.buttons["Pause race"].waitForExistence(timeout: 5))
        app.typeKey("p", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["RACE PAUSED"].waitForExistence(timeout: 5))

        app.typeKey("p", modifierFlags: [])
        let overlayGone = NSPredicate(format: "exists == false")
        expectation(for: overlayGone, evaluatedWith: app.staticTexts["RACE PAUSED"])
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testTitleShowsOnlyCoreControlsAndRaceHasNoHelpOverlays() {
        let app = XCUIApplication()
        app.launchArguments.append("UITestDisableRunRecovery")
        app.launch()
        dismissRunRecoveryIfPresent(app)

        XCTAssertTrue(app.buttons["RACE"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["TUTORIAL"].exists)
        XCTAssertFalse(app.buttons["GUIDE"].exists)
        XCTAssertTrue(app.buttons["GARAGE"].exists)
        XCTAssertTrue(app.buttons["SETTINGS"].exists)
        XCTAssertFalse(app.buttons["CREDITS"].exists)
        XCTAssertFalse(app.buttons["LEGAL"].exists)
        app.buttons["RACE"].tap()
        XCTAssertTrue(app.buttons["Pause race"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["DRIVING TIP"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testGarageShowsVehicleComparisonAndCustomizationScreen() {
        let app = XCUIApplication()
        app.launchArguments.append("UITestDisableRunRecovery")
        app.launch()
        dismissRunRecoveryIfPresent(app)

        XCTAssertTrue(app.buttons["GARAGE"].waitForExistence(timeout: 5))
        app.buttons["GARAGE"].tap()

        let prototype = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Prototype Zero,")).firstMatch
        let vector = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Vector Sprint,")).firstMatch
        let apex = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Apex Phantom,")).firstMatch
        XCTAssertTrue(prototype.waitForExistence(timeout: 5))
        XCTAssertTrue(vector.exists)
        XCTAssertTrue(apex.exists)
        XCTAssertTrue(prototype.isHittable)
        XCTAssertTrue(vector.isHittable)
        XCTAssertTrue(apex.isHittable)
        XCTAssertTrue((prototype.label).contains("top speed"))
        XCTAssertTrue((vector.label).contains("acceleration"))
        XCTAssertTrue((apex.label).contains("boost"))
        XCTAssertTrue(app.buttons["MODIFY SELECTED CAR"].exists)

        app.buttons["MODIFY SELECTED CAR"].tap()
        XCTAssertTrue(app.staticTexts["Modifications"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["PALETTE & NEON TRIM"].exists)
        XCTAssertTrue(app.staticTexts["RACE ROUTE"].exists)

        let customizationDone = app.navigationBars["Modifications"].buttons["Done"]
        XCTAssertTrue(customizationDone.waitForExistence(timeout: 5))
        customizationDone.tap()
        XCTAssertTrue(app.buttons["MODIFY SELECTED CAR"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func dismissRunRecoveryIfPresent(_ app: XCUIApplication) {
        let discardRun = app.buttons["DISCARD RUN"]
        if discardRun.waitForExistence(timeout: 1) {
            discardRun.tap()
        }
    }
}
