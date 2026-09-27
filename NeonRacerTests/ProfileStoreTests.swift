import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct ProfileStoreTests {
    @Test
    func newProfileAlwaysContainsStarterContent() {
        let profile = PlayerProfile.newPlayer

        #expect(profile.schemaVersion == PlayerProfile.currentSchemaVersion)
        #expect(profile.unlockedVehicleIDs.contains("prototype-zero"))
        #expect(profile.unlockedPaletteIDs.contains("synthwave"))
        #expect(profile.unlockedRouteIDs.contains("neon-loop"))
    }

    @Test
    func accomplishmentsUnlockContentAndUpdateRouteRecords() {
        var profile = PlayerProfile.newPlayer
        let result = RaceResult(
            state: finishedState(score: 5_100, elapsedTime: 72),
            rank: .gold
        )

        profile.record(result, routeID: "neon-loop")
        profile.record(result, routeID: "neon-loop")
        profile.record(result, routeID: "neon-loop")

        #expect(profile.unlockedVehicleIDs.contains("vector-sprint"))
        #expect(profile.unlockedVehicleIDs.contains("apex-phantom"))
        #expect(profile.unlockedPaletteIDs.contains("ion-storm"))
        #expect(profile.unlockedRouteIDs.contains("void-causeway"))
        #expect(profile.recordsByRoute["neon-loop"]?.bestScore == 5_100)
        #expect(profile.recordsByRoute["neon-loop"]?.bestTime == 72)
    }

    @Test
    func unversionedProfileMigratesAndIsRewritten() async throws {
        let url = try profileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let fixture = """
        {
          "bestScore": 5200,
          "selectedVehicleID": "prototype-zero",
          "preferredInputMethod": "touch"
        }
        """
        try Data(fixture.utf8).write(to: url)
        let store = ProfileStore(fileURL: url)

        let result = await store.load()

        guard case .loaded(let profile, migrated: true) = result else {
            Issue.record("Expected a migrated profile")
            return
        }
        #expect(profile.bestScore == 5_200)
        let rewritten = try JSONDecoder().decode(
            PlayerProfile.self,
            from: Data(contentsOf: url)
        )
        #expect(rewritten.schemaVersion == PlayerProfile.currentSchemaVersion)
    }

    @Test
    func versionOneProfileMigratesWithSafeSelectionDefaults() async throws {
        let url = try profileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let fixture = """
        {
          "schemaVersion": 1,
          "bestScore": 900,
          "selectedVehicleID": "retired-vehicle",
          "tutorialProgress": { "status": "completed" },
          "preferredInputMethod": "keyboard"
        }
        """
        try Data(fixture.utf8).write(to: url)
        let store = ProfileStore(fileURL: url)

        let result = await store.load()

        guard case .loaded(let profile, migrated: true) = result else {
            Issue.record("Expected schema version one to migrate")
            return
        }
        #expect(profile.selectedVehicleID == "prototype-zero")
        #expect(profile.selectedPaletteID == "synthwave")
        #expect(profile.selectedRouteID == "neon-loop")
        #expect(profile.preferredInputMethod == .keyboard)
    }

    @Test
    func corruptProfileRequiresExplicitRecoveryAndPreservesOriginal() async throws {
        let url = try profileURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not-json".utf8).write(to: url)
        let store = ProfileStore(fileURL: url)

        let result = await store.load()
        guard case .recoveryRequired = result else {
            Issue.record("Expected explicit recovery")
            return
        }

        let recovered = try await store.resetPreservingCorruptSave()
        #expect(recovered == .newPlayer)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let preserved = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .contains { $0.lastPathComponent.contains(".corrupt-") }
        #expect(preserved)
    }

    private func profileURL() throws -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = root
            .appendingPathComponent("NeonRacerTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("player-profile.json")
    }

    private func finishedState(score: Double, elapsedTime: TimeInterval) -> RaceState {
        var state = RaceState()
        state.phase = .finished
        state.elapsedTime = elapsedTime
        state.scoreInputs.distancePoints = score
        return state
    }
}
