import Foundation

struct PlayerProfile: Codable, Equatable, Sendable {
    var bestScore: Int
    var selectedVehicleID: String

    static let newPlayer = PlayerProfile(
        bestScore: 0,
        selectedVehicleID: "prototype-zero"
    )
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

