import XCTest

/// Source-contract tests for the physical-device performance sign-off gate
/// (issue #37). These trace the release-readiness gate end to end: the
/// checklist doc, the fail-closed gate script, the tracked evidence record,
/// and the CI job that runs the gate — proving the gate fails while no dated
/// device measurement exists and would pass only once one is recorded.
///
/// The gate is a bash script, so the execution probes below use `Process`,
/// which is unavailable on iOS. They run wherever Foundation can launch
/// processes (macOS `swift test`, Linux `swift test`); on the iOS simulator
/// the static contract assertions still run and the live gate execution is
/// covered by the CI release-readiness job itself.
final class DeviceSignoffGateContractTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // MARK: - Acceptance criterion 1: self-contained checklist procedure

    func testSignoffChecklistCoversEveryDocumentedBudget() throws {
        let checklist = try read(repoRoot.appendingPathComponent("docs/performance-device-signoff.md"))
        let budgets = try read(repoRoot.appendingPathComponent("docs/performance.md"))

        // Every threshold number in docs/performance.md's Budgets table must
        // appear as an explicit pass/fail threshold in the checklist.
        for token in [
            "16.67 ms", "55 FPS", "2 ms", "5 ms", "8 ms",
            "650", "420", "650 MB", "5 MB/s", "3 second", "60 FPS",
        ] {
            XCTAssertTrue(
                budgets.contains(token),
                "docs/performance.md should carry budget token \(token)."
            )
            XCTAssertTrue(
                checklist.contains(token),
                "Sign-off checklist must restate budget token \(token) as a threshold."
            )
        }

        // The procedure must be self-contained: clean clone -> archive -> device run -> thresholds.
        for step in [
            "git clone",
            "git status --short",
            "xcodebuild archive",
            "Instruments",
            "check_device_signoff.sh",
        ] {
            XCTAssertTrue(
                checklist.contains(step),
                "Sign-off checklist must contain procedure step/marker: \(step)."
            )
        }

        // Canary: removing any threshold from the checklist breaks coverage.
        let withoutGPUBudget = checklist.replacingOccurrences(of: "<= 8 ms/frame", with: "<= TBD")
        XCTAssertFalse(
            withoutGPUBudget.contains("<= 8 ms/frame"),
            "Canary failed: GPU threshold removal was not detected."
        )
    }

    // MARK: - Acceptance criterion 2: gate fails closed while evidence is absent

    func testEvidenceRecordIsPendingSoGateFailsClosed() throws {
        let evidence = try read(repoRoot.appendingPathComponent("docs/performance-device-evidence.md"))
        XCTAssertTrue(
            evidence.contains("SIGN_OFF_DATE: PENDING"),
            "Until the owner device run happens, the sign-off date must stay PENDING."
        )

        #if os(macOS) || os(Linux)
        let result = try runGate(in: repoRoot)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must exit non-zero while no dated device evidence exists."
        )
        XCTAssertTrue(
            result.output.contains("BLOCKED"),
            "Gate must report BLOCKED, not a synthetic pass."
        )
        #endif
    }

    #if os(macOS) || os(Linux)
    func testGatePassesOnlyWithDatedCompleteEvidence() throws {
        let staged = try stagedRepoRoot(suffix: "complete")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        let evidence = completeRecord()
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)
        XCTAssertFalse(
            evidence.contains("PENDING"),
            "Fixture must leave zero placeholder cells for a meaningful pass."
        )

        let result = try runGate(in: staged)
        XCTAssertEqual(
            result.status, 0,
            "Gate must pass once a dated, fully filled evidence record exists. Output: \(result.output)"
        )
        XCTAssertTrue(result.output.contains("PASS"))
    }

    func testGateRejectsMalformedSignOffDate() throws {
        let staged = try stagedRepoRoot(suffix: "malformed")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        let evidence = completeRecord().replacingOccurrences(
            of: "SIGN_OFF_DATE: 2026-10-01", with: "SIGN_OFF_DATE: 01-10-2026"
        )
        XCTAssertFalse(evidence.contains("PENDING"))
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject a non-ISO sign-off date. Output: \(result.output)"
        )
    }

    func testGateRejectsInvalidCalendarDate() throws {
        // Shape-valid but nonexistent date: a Feb-30 sign-off must not unlock
        // release readiness (regression fixture from independent review).
        let staged = try stagedRepoRoot(suffix: "invalid-date")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        let evidence = completeRecord().replacingOccurrences(
            of: "SIGN_OFF_DATE: 2026-10-01", with: "SIGN_OFF_DATE: 2026-02-30"
        )
        XCTAssertFalse(evidence.contains("PENDING"))
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject an ISO-shaped but invalid calendar date. Output: \(result.output)"
        )
    }

    func testGateRejectsFailedMetricRow() throws {
        // A complete record where one metric row reports FAIL (or any
        // non-PASS verdict) must keep the gate closed.
        let staged = try stagedRepoRoot(suffix: "fail-row")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        let fpsRow = "| Sustained FPS (full race) | >= 55 | 58.4 fps | PASS |"
        var evidence = completeRecord()
        XCTAssertTrue(evidence.contains(fpsRow), "Fixture precondition: FPS row exists")
        evidence = evidence.replacingOccurrences(
            of: fpsRow, with: "| Sustained FPS (full race) | >= 55 | 41.0 fps | FAIL |"
        )
        XCTAssertFalse(evidence.contains("PENDING"))
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject a record with a FAIL verdict row. Output: \(result.output)"
        )
    }

    func testGateRejectsDeletedMetricRow() throws {
        // Deleting a required row must not shrink the acceptance surface.
        let staged = try stagedRepoRoot(suffix: "deleted-row")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        let gpuLine = "| GPU p95 | <= 8 ms/frame | 6.1 ms/frame | PASS |\n"
        var evidence = completeRecord()
        XCTAssertTrue(evidence.contains(gpuLine), "Fixture precondition: GPU row exists")
        evidence = evidence.replacingOccurrences(of: gpuLine, with: "")
        XCTAssertFalse(evidence.contains("PENDING"))
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject a record with a deleted required metric row. Output: \(result.output)"
        )
    }

    func testGateRejectsNonNumericMeasurements() throws {
        // Review regression: arbitrary prose in Measured cells with PASS
        // verdicts must not pass — measurements must be plausible values.
        let staged = try stagedRepoRoot(suffix: "prose-measure")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        let gpuRow = "| GPU p95 | <= 8 ms/frame | 6.1 ms/frame | PASS |"
        var evidence = completeRecord()
        XCTAssertTrue(evidence.contains(gpuRow))
        evidence = evidence.replacingOccurrences(
            of: gpuRow, with: "| GPU p95 | <= 8 ms/frame | made up | PASS |"
        )
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject non-numeric measurements on numeric rows. Output: \(result.output)"
        )
    }

    func testGateRejectsBudgetViolatingMeasurement() throws {
        // A PASS verdict on a measurement that itself violates the budget
        // (GPU 12 ms/frame > 8) is internally inconsistent -> block.
        let staged = try stagedRepoRoot(suffix: "over-budget")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        let gpuRow = "| GPU p95 | <= 8 ms/frame | 6.1 ms/frame | PASS |"
        var evidence = completeRecord()
        XCTAssertTrue(evidence.contains(gpuRow))
        evidence = evidence.replacingOccurrences(
            of: gpuRow, with: "| GPU p95 | <= 8 ms/frame | 12 ms/frame | PASS |"
        )
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject measurements that violate their own budget. Output: \(result.output)"
        )
    }

    func testGateRejectsWeakenedThreshold() throws {
        // Editing a Threshold cell to a weaker limit must not pass — the
        // checklist budgets are fixed.
        let staged = try stagedRepoRoot(suffix: "weak-threshold")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        let gpuRow = "| GPU p95 | <= 8 ms/frame | 6.1 ms/frame | PASS |"
        var evidence = completeRecord()
        XCTAssertTrue(evidence.contains(gpuRow))
        evidence = evidence.replacingOccurrences(
            of: gpuRow, with: "| GPU p95 | <= 999 ms/frame | 6.1 ms/frame | PASS |"
        )
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject weakened threshold cells. Output: \(result.output)"
        )
    }

    func testGateRejectsDuplicateMetadataMarker() throws {
        let staged = try stagedRepoRoot(suffix: "dup-marker")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        let marker = "<!-- DEVICE_MODEL: iPhone 16 Pro -->"
        var evidence = completeRecord()
        XCTAssertTrue(evidence.contains(marker))
        evidence = evidence.replacingOccurrences(of: marker, with: marker + "\n" + marker)
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject duplicate metadata markers. Output: \(result.output)"
        )
    }

    func testGateRejectsVerdictOutsideVocabulary() throws {
        let staged = try stagedRepoRoot(suffix: "bad-vocab")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        let thermalRow = "| Thermal state | <= `.fair` | nominal | PASS |"
        var evidence = completeRecord()
        XCTAssertTrue(evidence.contains(thermalRow))
        evidence = evidence.replacingOccurrences(
            of: thermalRow, with: "| Thermal state | <= `.fair` | serious | PASS |"
        )
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject word-valued measurements outside the vocabulary. Output: \(result.output)"
        )
    }

    func testGateRejectsMissingMetadataMarker() throws {
        // Stripping DEVICE_MODEL from an otherwise-complete record must block.
        let staged = try stagedRepoRoot(suffix: "missing-marker")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        var evidence = completeRecord()
        XCTAssertTrue(evidence.contains("DEVICE_MODEL: iPhone 16 Pro"))
        evidence = evidence.replacingOccurrences(
            of: "<!-- DEVICE_MODEL: iPhone 16 Pro -->", with: ""
        )
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must block when a metadata marker is deleted. Output: \(result.output)"
        )
    }

    func testGateRejectsEmptyMeasuredCell() throws {
        let staged = try stagedRepoRoot(suffix: "empty-measured")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        var evidence = completeRecord()
        let gpuRow = "| GPU p95 | <= 8 ms/frame | 6.1 ms/frame | PASS |"
        XCTAssertTrue(evidence.contains(gpuRow))
        evidence = evidence.replacingOccurrences(
            of: gpuRow, with: "| GPU p95 | <= 8 ms/frame | | PASS |"
        )
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject a row with no measured value. Output: \(result.output)"
        )
    }

    func testGateRejectsMalformedVerdict() throws {
        // A verdict that merely contains PASS (e.g. FAILPASS) is not a pass.
        let staged = try stagedRepoRoot(suffix: "malformed-verdict")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        var evidence = completeRecord()
        evidence = evidence.replacingOccurrences(
            of: "| GPU p95 | <= 8 ms/frame | 6.1 ms/frame | PASS |",
            with: "| GPU p95 | <= 8 ms/frame | 60.2 | FAILPASS |"
        )
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject verdicts that are not an exact PASS. Output: \(result.output)"
        )
    }

    func testGateRejectsDuplicateRowMaskingFail() throws {
        // Appending a duplicate PASS row cannot mask the original FAIL row:
        // required rows must appear exactly once.
        let staged = try stagedRepoRoot(suffix: "duplicate-mask")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        var evidence = completeRecord()
        let gpuRow = "| GPU p95 | <= 8 ms/frame | 6.1 ms/frame | PASS |"
        XCTAssertTrue(evidence.contains(gpuRow))
        evidence = evidence.replacingOccurrences(
            of: gpuRow,
            with: "| GPU p95 | <= 8 ms/frame | 12 | FAIL |\n" + gpuRow
        )
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject duplicate rows used to mask a FAIL. Output: \(result.output)"
        )
    }

    func testGateRejectsUnexpectedExtraRow() throws {
        // Injecting an extra row outside the required metric set means the
        // record no longer matches the checklist's acceptance surface.
        let staged = try stagedRepoRoot(suffix: "extra-row")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        var evidence = completeRecord()
        let gpuRow = "| GPU p95 | <= 8 ms/frame | 6.1 ms/frame | PASS |"
        XCTAssertTrue(evidence.contains(gpuRow))
        evidence = evidence.replacingOccurrences(
            of: gpuRow,
            with: gpuRow + "\n| Made-up metric | anything | 1 | PASS |"
        )
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject records with rows outside the required set. Output: \(result.output)"
        )
    }

    func testGateRejectsTableWithoutHeader() throws {
        // Deleting the header/separator must not shrink the acceptance
        // surface — the table structure itself is required.
        let staged = try stagedRepoRoot(suffix: "no-header")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        var evidence = completeRecord()
        let header = "| Metric | Threshold | Measured | Result |\n"
        let separator = "| --- | --- | --- | --- |\n"
        XCTAssertTrue(evidence.contains(header) && evidence.contains(separator))
        evidence = evidence.replacingOccurrences(of: header + separator, with: "")
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject a table missing its header structure. Output: \(result.output)"
        )
    }

    func testGateRejectsIndentedExtraPipeRow() throws {
        let staged = try stagedRepoRoot(suffix: "indented-row")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        var evidence = completeRecord()
        let gpuRow = "| GPU p95 | <= 8 ms/frame | 6.1 ms/frame | PASS |"
        XCTAssertTrue(evidence.contains(gpuRow))
        evidence = evidence.replacingOccurrences(
            of: gpuRow, with: gpuRow + "\n  | sneaky | row | 1 | PASS |"
        )
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject indented pipe rows. Output: \(result.output)"
        )
    }

    func testGateRejectsEmptyMetricNameRow() throws {
        let staged = try stagedRepoRoot(suffix: "empty-name-row")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        var evidence = completeRecord()
        let gpuRow = "| GPU p95 | <= 8 ms/frame | 6.1 ms/frame | PASS |"
        XCTAssertTrue(evidence.contains(gpuRow))
        evidence = evidence.replacingOccurrences(
            of: gpuRow, with: gpuRow + "\n| | x | y | PASS |"
        )
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject pipe rows with an empty metric name. Output: \(result.output)"
        )
    }

    func testGateRejectsWrongUnitMeasurement() throws {
        // Units are per-metric: an FPS cell carrying "58.4 MB" is not a
        // frame-rate measurement even though the number passes a bound.
        let staged = try stagedRepoRoot(suffix: "wrong-unit")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        let fpsRow = "| Sustained FPS (full race) | >= 55 | 58.4 fps | PASS |"
        var evidence = completeRecord()
        XCTAssertTrue(evidence.contains(fpsRow))
        evidence = evidence.replacingOccurrences(
            of: fpsRow, with: "| Sustained FPS (full race) | >= 55 | 58.4 MB | PASS |"
        )
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject measurements carrying the wrong unit. Output: \(result.output)"
        )
    }

    func testGateRejectsConcatenatedUnits() throws {
        let staged = try stagedRepoRoot(suffix: "concat-unit")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        let fpsRow = "| Sustained FPS (full race) | >= 55 | 58.4 fps | PASS |"
        var evidence = completeRecord()
        XCTAssertTrue(evidence.contains(fpsRow))
        evidence = evidence.replacingOccurrences(
            of: fpsRow, with: "| Sustained FPS (full race) | >= 55 | 58.4 msfps | PASS |"
        )
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject concatenated unit suffixes. Output: \(result.output)"
        )
    }

    func testGateRejectsCodeFencedTable() throws {
        // A fenced (non-rendered) table is not a record.
        let staged = try stagedRepoRoot(suffix: "fenced")
        let evidenceURL = staged.appendingPathComponent("docs/performance-device-evidence.md")
        var evidence = completeRecord()
        let header = "| Metric | Threshold | Measured | Result |"
        XCTAssertTrue(evidence.contains(header))
        evidence = evidence.replacingOccurrences(of: header, with: "```\n" + header)
        evidence = evidence.replacingOccurrences(
            of: "| Thermal state | <= `.fair` | nominal | PASS |",
            with: "| Thermal state | <= `.fair` | nominal | PASS |\n```"
        )
        try evidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try runGate(in: staged)
        XCTAssertNotEqual(
            result.status, 0,
            "Gate must reject measurement tables hidden in code fences. Output: \(result.output)"
        )
    }

    func testGateFailsClosedWhenEvidenceFileIsMissing() throws {
        let staged = try stagedRepoRoot(suffix: "missing")
        try FileManager.default.removeItem(
            at: staged.appendingPathComponent("docs/performance-device-evidence.md")
        )

        let result = try runGate(in: staged)
        XCTAssertNotEqual(result.status, 0, "Gate must block when the evidence file is deleted.")
        XCTAssertTrue(result.output.contains("BLOCKED"))
    }
    #endif

    // MARK: - Acceptance criterion 3: existing simulator lanes unchanged

    func testReleaseGateJobIsDispatchAndTagOnly() throws {
        let workflow = try read(repoRoot.appendingPathComponent(".github/workflows/ci.yml"))

        XCTAssertTrue(
            workflow.contains("release-readiness:"),
            "CI must carry a release-readiness gate job."
        )
        XCTAssertTrue(
            workflow.contains("bash scripts/check_device_signoff.sh"),
            "The release-readiness job must execute the sign-off gate."
        )
        XCTAssertTrue(
            workflow.contains("if: github.event_name == 'workflow_dispatch' || startsWith(github.ref, 'refs/tags/v')"),
            "The gate must fire only on dispatch/tag so PR and push simulator lanes stay unchanged."
        )

        // The two existing simulator lanes must remain PR/push-triggered as before.
        let coreTestsRange = try XCTUnwrap(
            workflow.range(of: "core-tests:"),
            "Swift package tests lane missing."
        )
        let iosBuildRange = try XCTUnwrap(
            workflow.range(of: "ios-build:"),
            "iOS build lane missing."
        )
        let gateRange = try XCTUnwrap(
            workflow.range(of: "release-readiness:"),
            "Release gate lane missing."
        )
        XCTAssertLessThan(coreTestsRange.lowerBound, gateRange.lowerBound)
        XCTAssertLessThan(iosBuildRange.lowerBound, gateRange.lowerBound)
    }

    func testReleaseRunbookPointsAtTheGate() throws {
        let releaseRunbook = try read(repoRoot.appendingPathComponent("docs/release.md"))
        XCTAssertTrue(
            releaseRunbook.contains("scripts/check_device_signoff.sh"),
            "Release runbook must reference the sign-off gate command."
        )
        XCTAssertTrue(
            releaseRunbook.contains("docs/performance-device-signoff.md"),
            "Release runbook must link the checklist procedure."
        )
    }

    // MARK: - Helpers

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// The pending evidence record with every placeholder replaced by a
    /// dated, all-PASS measurement with per-metric values inside their
    /// checklist budgets — the only shape the gate may accept.
    private func completeRecord() -> String {
        guard var evidence = try? read(repoRoot.appendingPathComponent("docs/performance-device-evidence.md")) else {
            return ""
        }
        let replacements: [(String, String)] = [
            ("SIGN_OFF_DATE: PENDING", "SIGN_OFF_DATE: 2026-10-01"),
            ("DEVICE_MODEL: PENDING", "DEVICE_MODEL: iPhone 16 Pro"),
            ("IOS_VERSION: PENDING", "IOS_VERSION: 26.5"),
            ("BUILD_COMMIT: PENDING", "BUILD_COMMIT: 0123456"),
            ("Sign-off status: PENDING", "Sign-off status: RECORDED"),
            (">= 55 | PENDING | PENDING |", ">= 55 | 58.4 fps | PASS |"),
            ("<= 16.67 ms | PENDING | PENDING |", "<= 16.67 ms | 15.9 ms | PASS |"),
            ("<= 2 ms/frame | PENDING | PENDING |", "<= 2 ms/frame | 1.4 ms/frame | PASS |"),
            ("<= 5 ms/frame | PENDING | PENDING |", "<= 5 ms/frame | 3.2 ms/frame | PASS |"),
            ("<= 8 ms/frame | PENDING | PENDING |", "<= 8 ms/frame | 6.1 ms/frame | PASS |"),
            ("<= 650 | PENDING | PENDING |", "<= 650 | 612 | PASS |"),
            ("<= 420 | PENDING | PENDING |", "<= 420 | 388 | PASS |"),
            ("| 14 | PENDING | PENDING |", "| 14 | 14 | PASS |"),
            ("< 650 MB | PENDING | PENDING |", "< 650 MB | 480 MB | PASS |"),
            ("no sustained growth | PENDING | PENDING |", "no sustained growth | none | PASS |"),
            ("< 5 MB/s | PENDING | PENDING |", "< 5 MB/s | 2.1 MB/s | PASS |"),
            ("< 3 s | PENDING | PENDING |", "< 3 s | 1.8 s | PASS |"),
            ("<= `.fair` | PENDING | PENDING |", "<= `.fair` | nominal | PASS |"),
        ]
        for (needle, value) in replacements {
            evidence = evidence.replacingOccurrences(of: needle, with: value)
        }
        return evidence
    }

    #if os(macOS) || os(Linux)
    private struct GateResult {
        let status: Int32
        let output: String
    }

    /// Copies the gate surface (script + docs) into a throwaway root so a test
    /// can mutate the evidence record without touching the real tree.
    private func stagedRepoRoot(suffix: String) throws -> URL {
        let fm = FileManager.default
        let staged = fm.temporaryDirectory
            .appendingPathComponent("nr37-\(suffix)-\(UUID().uuidString)")
        try fm.createDirectory(at: staged.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try fm.createDirectory(at: staged.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try fm.copyItem(
            at: repoRoot.appendingPathComponent("scripts/check_device_signoff.sh"),
            to: staged.appendingPathComponent("scripts/check_device_signoff.sh")
        )
        for doc in ["performance-device-evidence.md", "performance-device-signoff.md", "performance.md"] {
            try fm.copyItem(
                at: repoRoot.appendingPathComponent("docs/\(doc)"),
                to: staged.appendingPathComponent("docs/\(doc)")
            )
        }
        addTeardownBlock { try? fm.removeItem(at: staged) }
        return staged
    }

    private func runGate(in root: URL) throws -> GateResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/check_device_signoff.sh"]
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return GateResult(status: process.terminationStatus, output: output)
    }
    #endif
}
