import Foundation

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
final class GameplaySettingsStore {
    private let defaults: UserDefaults
    private let key: String

    private(set) var settings: GameplaySettings {
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

struct PlayerProfile: Codable, Equatable, Sendable {
    var bestScore: Int
    var selectedVehicleID: String
    var tutorialProgress: TutorialProgress
    var preferredInputMethod: DrivingInputMethod

    static let newPlayer = PlayerProfile(
        bestScore: 0,
        selectedVehicleID: "prototype-zero",
        tutorialProgress: .notStarted,
        preferredInputMethod: .touch
    )

    private enum CodingKeys: String, CodingKey {
        case bestScore
        case selectedVehicleID
        case tutorialProgress
        case preferredInputMethod
    }

    init(
        bestScore: Int,
        selectedVehicleID: String,
        tutorialProgress: TutorialProgress,
        preferredInputMethod: DrivingInputMethod
    ) {
        self.bestScore = bestScore
        self.selectedVehicleID = selectedVehicleID
        self.tutorialProgress = tutorialProgress
        self.preferredInputMethod = preferredInputMethod
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bestScore = try container.decode(Int.self, forKey: .bestScore)
        selectedVehicleID = try container.decode(String.self, forKey: .selectedVehicleID)
        tutorialProgress = try container.decodeIfPresent(
            TutorialProgress.self,
            forKey: .tutorialProgress
        ) ?? .notStarted
        preferredInputMethod = try container.decodeIfPresent(
            DrivingInputMethod.self,
            forKey: .preferredInputMethod
        ) ?? .touch
    }
}

actor ProfileStore {
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        fileURL = directory.appendingPathComponent("player-profile.json")
    }

    func load() throws -> PlayerProfile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .newPlayer
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(PlayerProfile.self, from: data)
    }

    func save(_ profile: PlayerProfile) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder().encode(profile)
        try data.write(to: fileURL, options: .atomic)
    }
}
