import Foundation
import Combine

struct HapticSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var intensity: Double

    static let standard = HapticSettings(isEnabled: true, intensity: 1)
}

struct GameplaySettings: Codable, Equatable, Sendable {
    var haptics: HapticSettings
    var inputRemapping: InputRemapping

    static let standard = GameplaySettings(
        haptics: .standard,
        inputRemapping: .standard
    )
}

@MainActor
final class GameplaySettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private let key: String

    @Published private(set) var settings: GameplaySettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                defaults.set(data, forKey: key)
            }
        }
    }

    init(defaults: UserDefaults = .standard, key: String = "gameplay-settings") {
        self.defaults = defaults
        self.key = key
        settings = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(GameplaySettings.self, from: $0) }
            ?? .standard
    }

    func update(_ update: (inout GameplaySettings) -> Void) {
        update(&settings)
    }

    func reset() {
        settings = .standard
    }
}

@MainActor
final class AudioSettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private let key: String

    @Published private(set) var preferences: AudioPreferences {
        didSet {
            persist()
        }
    }

    init(defaults: UserDefaults = .standard, key: String = "audio.preferences.v1") {
        self.defaults = defaults
        self.key = key
        preferences = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(AudioPreferences.self, from: $0) }
            ?? .standard
    }

    func update(_ update: (inout AudioPreferences) -> Void) {
        var next = preferences
        update(&next)
        preferences = AudioPreferences(
            musicLevel: next.musicLevel,
            effectsLevel: next.effectsLevel,
            isMusicMuted: next.isMusicMuted,
            areEffectsMuted: next.areEffectsMuted
        )
    }

    func reset() {
        preferences = .standard
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: key)
        }
    }
}

struct PlayerProfile: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var bestScore: Int
    var selectedVehicleID: String
    var unlockedVehicleIDs: Set<String>
    var selectedPaletteID: String
    var unlockedPaletteIDs: Set<String>
    var selectedRouteID: String
    var unlockedRouteIDs: Set<String>
    var recordsByRoute: [String: RouteRecord]
    var accomplishments: PlayerAccomplishments
    var tutorialProgress: TutorialProgress
    var preferredInputMethod: DrivingInputMethod

    static let newPlayer = PlayerProfile(
        schemaVersion: currentSchemaVersion,
        bestScore: 0,
        selectedVehicleID: "prototype-zero",
        unlockedVehicleIDs: ["prototype-zero"],
        selectedPaletteID: "synthwave",
        unlockedPaletteIDs: ["synthwave"],
        selectedRouteID: "neon-loop",
        unlockedRouteIDs: ["neon-loop"],
        recordsByRoute: [:],
        accomplishments: .none,
        tutorialProgress: .notStarted,
        preferredInputMethod: .touch
    )

    mutating func record(_ result: RaceResult, routeID: String? = nil) {
        guard result.outcome == .finished else { return }
        let resolvedRouteID = routeID
            ?? ProgressionCatalog.routes.first { $0.displayName == result.routeName }?.id
            ?? selectedRouteID
        accomplishments.completedRaces += 1
        accomplishments.highestScore = max(accomplishments.highestScore, result.score)
        if result.rank == .gold {
            accomplishments.goldFinishes += 1
        }
        bestScore = max(bestScore, result.score)

        var routeRecord = recordsByRoute[resolvedRouteID]
            ?? RouteRecord(bestScore: 0, bestTime: nil)
        routeRecord.bestScore = max(routeRecord.bestScore, result.score)
        routeRecord.bestTime = min(routeRecord.bestTime ?? result.elapsedTime, result.elapsedTime)
        recordsByRoute[resolvedRouteID] = routeRecord
        applyUnlocks()
    }

    mutating func applyUnlocks() {
        unlockedVehicleIDs.formUnion(
            ProgressionCatalog.vehicles
                .filter { $0.unlockRequirement.isSatisfied(by: accomplishments) }
                .map(\.id)
        )
        unlockedPaletteIDs.formUnion(
            ProgressionCatalog.palettes
                .filter { $0.unlockRequirement.isSatisfied(by: accomplishments) }
                .map(\.id)
        )
        unlockedRouteIDs.formUnion(
            ProgressionCatalog.routes
                .filter { $0.unlockRequirement.isSatisfied(by: accomplishments) }
                .map(\.id)
        )
        normalizeSelections()
    }

    mutating func normalizeSelections() {
        unlockedVehicleIDs.insert(ProgressionCatalog.vehicles[0].id)
        unlockedPaletteIDs.insert(ProgressionCatalog.palettes[0].id)
        unlockedRouteIDs.insert(ProgressionCatalog.routes[0].id)
        if !unlockedVehicleIDs.contains(selectedVehicleID) {
            selectedVehicleID = ProgressionCatalog.vehicles[0].id
        }
        if !unlockedPaletteIDs.contains(selectedPaletteID) {
            selectedPaletteID = ProgressionCatalog.palettes[0].id
        }
        if !unlockedRouteIDs.contains(selectedRouteID) {
            selectedRouteID = ProgressionCatalog.routes[0].id
        }
    }
}

struct ProfileRecovery: Equatable, Sendable {
    let message: String
}

enum ProfileLoadResult: Equatable, Sendable {
    case newProfile(PlayerProfile)
    case loaded(PlayerProfile, migrated: Bool)
    case recoveryRequired(ProfileRecovery)
}

actor ProfileStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        fileURL = directory.appendingPathComponent("player-profile.json")
        self.fileManager = fileManager
    }

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() -> ProfileLoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .newProfile(.newPlayer)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try decodeAndMigrate(data)
            if decoded.migrated {
                try save(decoded.profile)
            }
            return .loaded(decoded.profile, migrated: decoded.migrated)
        } catch {
            return .recoveryRequired(
                ProfileRecovery(
                    message: "The local profile could not be read. Reset it to continue. "
                        + "The damaged save will be preserved for recovery."
                )
            )
        }
    }

    func save(_ profile: PlayerProfile) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var currentProfile = profile
        currentProfile.schemaVersion = PlayerProfile.currentSchemaVersion
        currentProfile.normalizeSelections()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(currentProfile)
        try data.write(to: fileURL, options: .atomic)
    }

    func resetPreservingCorruptSave() throws -> PlayerProfile {
        if fileManager.fileExists(atPath: fileURL.path) {
            let formatter = ISO8601DateFormatter()
            let stamp = formatter.string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let recoveryURL = fileURL
                .deletingPathExtension()
                .appendingPathExtension("corrupt-\(stamp).json")
            try fileManager.moveItem(at: fileURL, to: recoveryURL)
        }
        let profile = PlayerProfile.newPlayer
        try save(profile)
        return profile
    }

    private func decodeAndMigrate(_ data: Data) throws -> (profile: PlayerProfile, migrated: Bool) {
        let decoder = JSONDecoder()
        if let version = try? decoder.decode(SchemaProbe.self, from: data).schemaVersion {
            switch version {
            case PlayerProfile.currentSchemaVersion:
                var profile = try decoder.decode(PlayerProfile.self, from: data)
                profile.normalizeSelections()
                return (profile, false)
            case 1:
                let legacy = try decoder.decode(LegacyProfileV1.self, from: data)
                return (legacy.migrated, true)
            default:
                throw ProfileStoreError.unsupportedSchema(version)
            }
        }

        let legacy = try decoder.decode(LegacyUnversionedProfile.self, from: data)
        return (legacy.migrated, true)
    }
}

private struct SchemaProbe: Decodable {
    let schemaVersion: Int
}

private struct LegacyProfileV1: Decodable {
    let schemaVersion: Int
    let bestScore: Int
    let selectedVehicleID: String
    let tutorialProgress: TutorialProgress?
    let preferredInputMethod: DrivingInputMethod?

    var migrated: PlayerProfile {
        migratedProfile(
            bestScore: bestScore,
            selectedVehicleID: selectedVehicleID,
            tutorialProgress: tutorialProgress,
            preferredInputMethod: preferredInputMethod
        )
    }
}

private struct LegacyUnversionedProfile: Decodable {
    let bestScore: Int
    let selectedVehicleID: String
    let tutorialProgress: TutorialProgress?
    let preferredInputMethod: DrivingInputMethod?

    var migrated: PlayerProfile {
        migratedProfile(
            bestScore: bestScore,
            selectedVehicleID: selectedVehicleID,
            tutorialProgress: tutorialProgress,
            preferredInputMethod: preferredInputMethod
        )
    }
}

private enum ProfileStoreError: Error {
    case unsupportedSchema(Int)
}

private func migratedProfile(
    bestScore: Int,
    selectedVehicleID: String,
    tutorialProgress: TutorialProgress?,
    preferredInputMethod: DrivingInputMethod?
) -> PlayerProfile {
    var profile = PlayerProfile.newPlayer
    profile.bestScore = max(0, bestScore)
    profile.accomplishments.highestScore = profile.bestScore
    if ProgressionCatalog.vehicles.contains(where: { $0.id == selectedVehicleID }) {
        profile.unlockedVehicleIDs.insert(selectedVehicleID)
        profile.selectedVehicleID = selectedVehicleID
    }
    profile.tutorialProgress = tutorialProgress ?? .notStarted
    profile.preferredInputMethod = preferredInputMethod ?? .touch
    profile.applyUnlocks()
    return profile
}
