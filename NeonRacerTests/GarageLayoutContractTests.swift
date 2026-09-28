import Foundation
import XCTest

final class GarageLayoutContractTests: XCTestCase {
    func testGarageOverviewRequiresDedicatedCustomizationScreen() throws {
        let source = try garageSource()

        XCTAssertTrue(
            source.contains("private struct GarageCustomizationView"),
            "Garage should move non-car modifications into a dedicated second screen."
        )
        XCTAssertTrue(
            source.contains("MODIFY SELECTED CAR"),
            "Garage overview should include an explicit transition into customization."
        )
        XCTAssertTrue(
            source.contains("VehicleComparisonCard"),
            "Garage overview should compare all cars with compact spec cards on one screen."
        )
    }

    func testOverviewMapsHorizontalMenuActionsToFocusMovement() throws {
        let source = try garageSource()

        XCTAssertTrue(
            focusStep(in: source, target: "moveOverviewFocus(-1)").contains(".menuLeft"),
            "Overview should move focus backwards on menuLeft."
        )
        XCTAssertTrue(
            focusStep(in: source, target: "moveOverviewFocus(1)").contains(".menuRight"),
            "Overview should move focus forwards on menuRight."
        )

        // Canary: dropping menuLeft/menuRight from the mapping must break the
        // exact case list that feeds the focus step.
        let withoutLeft = source.replacingOccurrences(of: ".menuLeft, ", with: "")
        XCTAssertFalse(
            focusStep(in: withoutLeft, target: "moveOverviewFocus(-1)").contains(".menuLeft"),
            "Canary failed: removing the menuLeft mapping was not detected."
        )
        let withoutRight = source.replacingOccurrences(of: ".menuRight, ", with: "")
        XCTAssertFalse(
            focusStep(in: withoutRight, target: "moveOverviewFocus(1)").contains(".menuRight"),
            "Canary failed: removing the menuRight mapping was not detected."
        )
    }

    func testCompactHeightShrinksCarPreviewSoCardsRemainReachable() throws {
        let source = try garageSource()
        let compactBranch = ".frame(height: compactHeight ? 52 : 78)"

        XCTAssertTrue(
            source.contains(compactBranch),
            "Cards should shrink the car preview when the landscape height is compact."
        )

        // Canary: reverting to a fixed preview height must fail this guard.
        let fixedPreview = source.replacingOccurrences(of: compactBranch, with: ".frame(height: 78)")
        XCTAssertFalse(
            fixedPreview.contains(compactBranch),
            "Canary failed: fixed preview height still satisfies the compact-height guard."
        )
    }

    func testComparisonCardAccessibilityLabelIncludesEverySpec() throws {
        let source = try garageSource()
        let summaryStart = try XCTUnwrap(
            source.range(of: "private var accessibilitySummary: String")?.lowerBound,
            "Comparison card accessibility summary missing."
        )
        let summarySource = String(source[summaryStart...])

        for spec in ["top speed", "acceleration", "handling", "boost"] {
            XCTAssertTrue(
                summarySource.contains(spec),
                "Each comparison card label should announce \(spec)."
            )
        }
        XCTAssertTrue(
            source.contains(".accessibilityLabel(accessibilitySummary)"),
            "The comparison card button must use the spec-bearing accessibility summary."
        )
    }

    func testGarageOverviewAvoidsScrollViewBeforeCustomizationScreen() throws {
        let source = try garageSource()
        let customizationMarker = try XCTUnwrap(
            source.range(of: "private struct GarageCustomizationView")?.lowerBound,
            "Dedicated customization screen marker missing."
        )
        let overviewSource = String(source[..<customizationMarker])

        XCTAssertFalse(
            overviewSource.contains("ScrollView"),
            "Overview should fit without scrolling so all car options/specs are visible at once."
        )
    }

    /// Returns the case-list text immediately preceding a focus-step call
    /// (the actions routed to that step), bounded to the 160 characters before it.
    private func focusStep(in source: String, target: String) -> String {
        guard let targetRange = source.range(of: target) else { return "" }
        let windowStart = source.index(
            targetRange.lowerBound,
            offsetBy: -160,
            limitedBy: source.startIndex
        ) ?? source.startIndex
        return String(source[windowStart..<targetRange.lowerBound])
    }

    private func garageSource() throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NeonRacer/Features/Garage/GarageView.swift")

        return try String(contentsOf: path, encoding: .utf8)
    }
}
