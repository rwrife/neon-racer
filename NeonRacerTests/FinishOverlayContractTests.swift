import XCTest

/// Source-contract tests for the finish sequence (issue #34): after crossing the
/// finish line the road extends obstacle-free to infinity, the car keeps driving
/// automatically, and the stats overlay offers race-again / return-to-title while
/// the cruising 3D scene stays live behind it.
final class FinishOverlayContractTests: XCTestCase {
    func testEndOfRaceResultsOverlayRendersInsideTheLiveRaceScene() throws {
        let race = try source("NeonRacer/Features/Race/RaceView.swift")

        XCTAssertTrue(
            race.contains("if let endingResult"),
            "The race view should present the ending result as an in-scene state."
        )
        XCTAssertTrue(
            race.contains("overlaysRaceScene: true"),
            "The results overlay must not replace the cruising race scene."
        )
        XCTAssertTrue(
            race.contains(".background(.black.opacity(0.58))"),
            "The overlay needs a translucent scrim so stats stay readable over the live scene."
        )
        XCTAssertFalse(
            race.contains("forcedUITestResult"),
            "The finish UI must flow through the same end-of-race path as a real finish."
        )
        XCTAssertTrue(
            race.contains("handleRaceCompleted(scene.completeForUITesting("),
            "The debug finish button must drive the same production end-of-race handler."
        )

        let root = try source("NeonRacer/App/RootView.swift")
        XCTAssertFalse(
            root.contains("case .results"),
            "Root navigation must not swap the race screen out for a separate results destination."
        )
    }

    func testFinishLineCruiseDrivesPresentationAndClearsHazards() throws {
        let scene = try source("NeonRacer/Game/Rendering3D/RaceScene3D.swift")

        XCTAssertTrue(
            scene.contains("finishCruise.begin("),
            "A finished race must start the automatic presentation cruise."
        )
        XCTAssertTrue(
            scene.contains("presentationDistance: finishCruise.isActive"),
            "Road rendering must follow the cruise distance, not the frozen race distance."
        )
        XCTAssertTrue(
            scene.contains("removeCourseHazards()"),
            "The cruise road must be obstacle-free."
        )
    }

    func testRoadExtrapolatesPastTheAuthoredRouteEnd() throws {
        let mapper = try source("NeonRacer/Game/Rendering3D/TrackWorldMapper3D.swift")

        XCTAssertTrue(
            mapper.contains("runDistance > last.runDistance"),
            "Frames beyond the last authored sample must extrapolate toward the horizon."
        )
        XCTAssertTrue(
            mapper.contains("presentationDistance"),
            "The mapper must accept a presentation distance decoupled from race state."
        )
    }

    func testResultsOfferRaceAgainAndReturnToTitle() throws {
        let menu = try source("NeonRacer/Features/MainMenu/MainMenuView.swift")

        XCTAssertTrue(
            menu.contains("\"RACE AGAIN\""),
            "The ending screen must offer racing again."
        )
        XCTAssertTrue(
            menu.contains("\"RETURN TO TITLE\""),
            "The ending screen must offer returning to the title."
        )
    }

    func testRaceAgainRestartsThroughViewIdentityRecreation() throws {
        let root = try source("NeonRacer/App/RootView.swift")

        XCTAssertTrue(
            root.contains("case .race(let runID)"),
            "The race destination must carry a run identity."
        )
        XCTAssertTrue(
            root.contains(".id(runID)"),
            "RaceAgain flows through startRace with a fresh UUID, and the .id modifier "
            + "must recreate the whole race view (and its RaceScene3D + cruise state) "
            + "so a finished cruise can never leak into a new run."
        )
        XCTAssertTrue(
            root.contains("setDestination(.race(UUID()))"),
            "Every race start must mint a fresh run identity."
        )
    }

    private func source(_ relativePath: String) throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)

        return try String(contentsOf: path, encoding: .utf8)
    }
}
