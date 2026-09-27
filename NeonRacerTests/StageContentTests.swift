import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct StageContentTests {
    @Test
    func bundledFixtureDecodesAndValidates() throws {
        let document = try StageContentLoader().loadBundledFixture(named: "neon-harbor")

        #expect(document.schemaVersion == StageContentDocument.currentSchemaVersion)
        #expect(document.stage.id == "neon-harbor")
        #expect(document.stage.route.sections.count == 4)
        #expect(document.stage.route.forks.first?.destinationSectionIDs == ["coast", "tunnel"])
    }

    @Test
    func initialRouteLoadsEntirelyFromBundledContent() throws {
        let document = try StageContentLoader().loadBundledFixture(named: "solar-to-summit")

        #expect(document == InitialRouteContent.bundle.document)
    }

    @Test
    func decodingDiagnosticIncludesSourceAndField() throws {
        var json = try fixtureObject()
        var stage = try #require(json["stage"] as? [String: Any])
        stage.removeValue(forKey: "paletteID")
        json["stage"] = stage

        let error = loadError(json)
        #expect(error.diagnostics.first?.source == "broken-stage.json")
        #expect(error.diagnostics.first?.field == "stage.paletteID")
        #expect(error.diagnostics.first?.code == "decode.missing-key")
    }

    @Test
    func validationRejectsDuplicateIDsMissingLinksAndRanges() throws {
        var json = try fixtureObject()
        var stage = try #require(json["stage"] as? [String: Any])
        var route = try #require(stage["route"] as? [String: Any])
        var sections = try #require(route["sections"] as? [[String: Any]])
        sections[1]["id"] = "launch"
        var links = try #require(sections[0]["links"] as? [[String: Any]])
        links[0]["destinationSectionID"] = "missing-road"
        sections[0]["links"] = links
        route["sections"] = sections
        stage["route"] = route
        json["stage"] = stage
        var traffic = try #require(json["trafficProfiles"] as? [[String: Any]])
        traffic[0]["baseDensity"] = 1.5
        json["trafficProfiles"] = traffic

        let error = loadError(json)
        #expect(error.diagnostics.contains { $0.code == "id.duplicate" && $0.field == "stage.route.sections[1].id" })
        #expect(error.diagnostics.contains { $0.code == "route.missing-link" })
        #expect(error.diagnostics.contains { $0.code == "range.out-of-bounds" && $0.field == "trafficProfiles[0].baseDensity" })
    }

    @Test
    func validationRejectsUnreachableForkAndBudgetOverrun() throws {
        var json = try fixtureObject()
        var budgets = try #require(json["budgets"] as? [String: Any])
        budgets["maximumSections"] = 2
        json["budgets"] = budgets
        var stage = try #require(json["stage"] as? [String: Any])
        var route = try #require(stage["route"] as? [String: Any])
        var sections = try #require(route["sections"] as? [[String: Any]])
        sections[2]["links"] = []
        route["sections"] = sections
        stage["route"] = route
        json["stage"] = stage

        let error = loadError(json)
        #expect(error.diagnostics.contains { $0.code == "route.dead-end" })
        #expect(error.diagnostics.contains { $0.code == "budget.sections" })
    }

    @Test
    func validationRejectsUnknownAndMissingAssets() throws {
        var json = try fixtureObject()
        var traffic = try #require(json["trafficProfiles"] as? [[String: Any]])
        traffic[0]["vehicleAssetIDs"] = ["unknown-car"]
        json["trafficProfiles"] = traffic
        let data = try JSONSerialization.data(withJSONObject: json)
        let loader = StageContentLoader(assetResolver: RejectingAssetResolver())

        let error: StageContentLoadError
        do {
            _ = try loader.load(data: data, source: "asset-stage.json")
            Issue.record("Expected invalid assets to fail")
            return
        } catch let loadError as StageContentLoadError {
            error = loadError
        }

        #expect(error.diagnostics.contains { $0.code == "asset.unknown" && $0.field == "trafficProfiles[0].vehicleAssetIDs[0]" })
        #expect(error.diagnostics.contains { $0.code == "asset.missing-resource" })
    }

    @Test
    func schemaPolicyRejectsOlderAndNewerContent() throws {
        for version in [0, 2] {
            var json = try fixtureObject()
            json["schemaVersion"] = version
            let error = loadError(json)
            #expect(error.diagnostics.first?.field == "schemaVersion")
            #expect(error.diagnostics.first?.code == (version == 0 ? "schema.older" : "schema.newer"))
        }
    }

    private func loadError(_ json: [String: Any]) -> StageContentLoadError {
        do {
            let data = try JSONSerialization.data(withJSONObject: json)
            _ = try StageContentLoader().load(data: data, source: "broken-stage.json")
            Issue.record("Expected content loading to fail")
        } catch let error as StageContentLoadError {
            return error
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        return StageContentLoadError(diagnostics: [])
    }

    private func fixtureObject() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: fixtureData()) as? [String: Any])
    }

    private func fixtureData() -> Data {
        try! Data(contentsOf: fixtureURL)
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NeonRacer/Content/Fixtures/neon-harbor.json")
    }
}

private struct RejectingAssetResolver: ContentAssetResolving {
    func contains(resourceNamed name: String, kind: AssetKind) -> Bool {
        false
    }
}
