import XCTest

final class NeonRacerUITests: XCTestCase {
    @MainActor
    func testLaunchesRaceFromMainMenu() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["NEON RACER"].waitForExistence(timeout: 5))
        app.buttons["START ENGINE"].tap()
        XCTAssertTrue(app.buttons["Exit race"].waitForExistence(timeout: 5))
    }
}

