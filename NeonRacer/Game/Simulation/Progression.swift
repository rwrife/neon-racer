import Foundation

struct VehicleDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let tagline: String
    let configurationProfile: DifficultyProfile
    let unlockRequirement: UnlockRequirement

    var configuration: RaceConfiguration {
        RaceConfiguration.configuration(for: configurationProfile)
    }
}

struct GaragePaletteDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let primaryHex: UInt32
    let secondaryHex: UInt32
    let unlockRequirement: UnlockRequirement
}

struct RouteDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let subtitle: String
    let unlockRequirement: UnlockRequirement
}

enum UnlockRequirement: Codable, Equatable, Sendable {
    case starter
    case completedRaces(Int)
    case bestScore(Int)
    case goldFinishes(Int)

    var description: String {
        switch self {
        case .starter:
            return "Available from the start"
        case .completedRaces(let count):
            return "Finish \(count) \(count == 1 ? "race" : "races")"
        case .bestScore(let score):
            return "Score \(score.formatted()) in one race"
        case .goldFinishes(let count):
            return "Earn \(count) gold \(count == 1 ? "finish" : "finishes")"
        }
    }

    func isSatisfied(by accomplishments: PlayerAccomplishments) -> Bool {
        switch self {
        case .starter:
            return true
        case .completedRaces(let count):
            return accomplishments.completedRaces >= count
        case .bestScore(let score):
            return accomplishments.highestScore >= score
        case .goldFinishes(let count):
            return accomplishments.goldFinishes >= count
        }
    }
}

enum ProgressionCatalog {
    static let vehicles = [
        VehicleDefinition(
            id: "prototype-zero",
            displayName: "Prototype Zero",
            tagline: "Balanced street prototype",
            configurationProfile: .standard,
            unlockRequirement: .starter
        ),
        VehicleDefinition(
            id: "vector-sprint",
            displayName: "Vector Sprint",
            tagline: "Responsive precision chassis",
            configurationProfile: .novice,
            unlockRequirement: .completedRaces(3)
        ),
        VehicleDefinition(
            id: "apex-phantom",
            displayName: "Apex Phantom",
            tagline: "Maximum velocity, narrow margins",
            configurationProfile: .expert,
            unlockRequirement: .goldFinishes(2)
        )
    ]

    static let palettes = [
        GaragePaletteDefinition(
            id: "synthwave",
            displayName: "Synthwave",
            primaryHex: 0xFF2D95,
            secondaryHex: 0x22D3EE,
            unlockRequirement: .starter
        ),
        GaragePaletteDefinition(
            id: "solar-flare",
            displayName: "Solar Flare",
            primaryHex: 0xFF8A00,
            secondaryHex: 0xFFE45E,
            unlockRequirement: .completedRaces(1)
        ),
        GaragePaletteDefinition(
            id: "ion-storm",
            displayName: "Ion Storm",
            primaryHex: 0x8B5CF6,
            secondaryHex: 0x34D399,
            unlockRequirement: .bestScore(5_000)
        )
    ]

    static let routes = [
        RouteDefinition(
            id: "neon-loop",
            displayName: "Neon Loop",
            subtitle: "Downtown night circuit",
            unlockRequirement: .starter
        ),
        RouteDefinition(
            id: "skyline-run",
            displayName: "Skyline Run",
            subtitle: "Elevated expressway",
            unlockRequirement: .completedRaces(2)
        ),
        RouteDefinition(
            id: "void-causeway",
            displayName: "Void Causeway",
            subtitle: "Expert high-speed route",
            unlockRequirement: .goldFinishes(1)
        )
    ]

    static func vehicle(id: String) -> VehicleDefinition {
        vehicles.first { $0.id == id } ?? vehicles[0]
    }

    static func palette(id: String) -> GaragePaletteDefinition {
        palettes.first { $0.id == id } ?? palettes[0]
    }

    static func routeGraph(id: String, configuration: RaceConfiguration) -> RouteGraph {
        switch id {
        case "skyline-run":
            themedLinearRoute(
                prefix: "skyline",
                environments: ["neon-city", "violet-skyway", "midnight-peaks"],
                totalDistance: configuration.stageLength * 1.05
            )
        case "void-causeway":
            themedLinearRoute(
                prefix: "void",
                environments: ["midnight-peaks", "ion-storm", "summit-core"],
                totalDistance: configuration.stageLength * 1.12
            )
        default:
            InitialRouteContent.routeGraph()
        }
    }

    private static func themedLinearRoute(
        prefix: String,
        environments: [String],
        totalDistance: Double
    ) -> RouteGraph {
        let stageDistance = totalDistance / Double(environments.count)
        let stages = environments.enumerated().map { index, environment in
            let id = "\(prefix)-\(index + 1)"
            let branches: [RouteBranch]
            if index + 1 < environments.count {
                branches = [
                    RouteBranch(
                        id: "\(id)-continue",
                        direction: .straight,
                        destinationStageID: "\(prefix)-\(index + 2)",
                        previewName: environments[index + 1]
                            .replacingOccurrences(of: "-", with: " ")
                            .capitalized
                    )
                ]
            } else {
                branches = []
            }
            return RouteStage(
                id: id,
                displayName: environment.replacingOccurrences(of: "-", with: " ").capitalized,
                environmentID: environment,
                distance: stageDistance,
                checkpointTimeAward: branches.isEmpty ? 0 : 10,
                branches: branches
            )
        }
        return RouteGraph(
            startStageID: stages[0].id,
            stages: stages,
            forkDecisionDistance: 0,
            minimumForkDecisionTime: 0
        )
    }
}

struct PlayerAccomplishments: Codable, Equatable, Sendable {
    var completedRaces: Int
    var highestScore: Int
    var goldFinishes: Int

    static let none = PlayerAccomplishments(
        completedRaces: 0,
        highestScore: 0,
        goldFinishes: 0
    )
}

struct RouteRecord: Codable, Equatable, Sendable {
    var bestScore: Int
    var bestTime: TimeInterval?
}
