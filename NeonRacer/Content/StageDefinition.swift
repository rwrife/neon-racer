import Foundation

protocol ContentIdentifiable {
    var id: String { get }
}

struct StageContentDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let stage: StageDefinition
    let palettes: [PaletteDefinition]
    let trafficProfiles: [TrafficProfileDefinition]
    let sceneryProfiles: [SceneryProfileDefinition]
    let weatherProfiles: [WeatherDefinition]
    let musicCues: [MusicCueDefinition]
    let difficulties: [DifficultyDefinition]
    let assets: AssetManifest
    let budgets: ContentBudget
}

struct StageDefinition: Codable, Equatable, Sendable, Identifiable, ContentIdentifiable {
    let id: String
    let displayName: String
    let route: RouteGraphDefinition
    let paletteID: String
    let trafficProfileID: String
    let sceneryProfileID: String
    let weatherProfileID: String
    let musicCueIDs: [String]
    let difficultyIDs: [String]
}

struct RouteGraphDefinition: Codable, Equatable, Sendable {
    let startSectionID: String
    let finishSectionIDs: [String]
    let sections: [RoadSectionDefinition]
    let checkpoints: [CheckpointDefinition]
    let forks: [ForkDefinition]
}

struct RoadSectionDefinition: Codable, Equatable, Sendable, Identifiable, ContentIdentifiable {
    let id: String
    let length: Double
    let curve: CurveDefinition
    let elevation: ElevationDefinition
    let lanes: LaneDefinition
    let laneChanges: [LaneChangeDefinition]
    let links: [RouteLinkDefinition]
}

struct CurveDefinition: Codable, Equatable, Sendable {
    let entry: Double
    let apex: Double
    let exit: Double
}

struct ElevationDefinition: Codable, Equatable, Sendable {
    let startMeters: Double
    let endMeters: Double
    let crestMeters: Double?
}

struct LaneDefinition: Codable, Equatable, Sendable {
    let count: Int
    let width: Double
    let shoulderWidth: Double
}

struct LaneChangeDefinition: Codable, Equatable, Sendable, Identifiable, ContentIdentifiable {
    let id: String
    let at: Double
    let laneCount: Int
}

struct RouteLinkDefinition: Codable, Equatable, Sendable {
    let destinationSectionID: String
    let forkID: String?
}

struct CheckpointDefinition: Codable, Equatable, Sendable, Identifiable, ContentIdentifiable {
    let id: String
    let sectionID: String
    let at: Double
    let order: Int
    let isRequired: Bool
}

struct ForkDefinition: Codable, Equatable, Sendable, Identifiable, ContentIdentifiable {
    let id: String
    let sectionID: String
    let at: Double
    let destinationSectionIDs: [String]
    let defaultDestinationSectionID: String
}

struct TrafficProfileDefinition: Codable, Equatable, Sendable, Identifiable, ContentIdentifiable {
    let id: String
    let baseDensity: Double
    let maximumVehicles: Int
    let minimumHeadway: Double
    let speedRange: ClosedRangeValue<Double>
    let vehicleAssetIDs: [String]
}

struct SceneryProfileDefinition: Codable, Equatable, Sendable, Identifiable, ContentIdentifiable {
    let id: String
    let bands: [SceneryBandDefinition]
}

struct SceneryBandDefinition: Codable, Equatable, Sendable, Identifiable, ContentIdentifiable {
    let id: String
    let side: RoadSide
    let distanceRange: ClosedRangeValue<Double>
    let lateralRange: ClosedRangeValue<Double>
    let spacing: Double
    let assetIDs: [String]
    let maximumInstances: Int
}

enum RoadSide: String, Codable, Equatable, Sendable {
    case left
    case right
    case both
}

struct PaletteDefinition: Codable, Equatable, Sendable, Identifiable, ContentIdentifiable {
    let id: String
    let skyTopHex: String
    let skyBottomHex: String
    let roadHex: String
    let shoulderHex: String
    let laneMarkerHex: String
    let primaryAccentHex: String
    let secondaryAccentHex: String
    let fogHex: String
}

struct WeatherDefinition: Codable, Equatable, Sendable, Identifiable, ContentIdentifiable {
    let id: String
    let kind: WeatherKind
    let intensity: Double
    let visibility: Double
    let roadGrip: Double
    let particleAssetID: String?
}

enum WeatherKind: String, Codable, Equatable, Sendable {
    case clear
    case rain
    case fog
    case dust
}

struct MusicCueDefinition: Codable, Equatable, Sendable, Identifiable, ContentIdentifiable {
    let id: String
    let trigger: MusicCueTrigger
    let assetID: String
    let loop: Bool
    let crossfadeSeconds: Double
}

enum MusicCueTrigger: String, Codable, Equatable, Sendable {
    case stageStart
    case checkpoint
    case finalStretch
    case finish
}

struct DifficultyDefinition: Codable, Equatable, Sendable, Identifiable, ContentIdentifiable {
    let id: String
    let trafficDensityMultiplier: Double
    let opponentSpeedMultiplier: Double
    let timeLimitSeconds: Double
    let checkpointTimeBonusSeconds: Double
    let scoreMultiplier: Double
}

struct AssetManifest: Codable, Equatable, Sendable {
    let entries: [AssetDefinition]
}

struct AssetDefinition: Codable, Equatable, Sendable, Identifiable, ContentIdentifiable {
    let id: String
    let kind: AssetKind
    let resourceName: String
}

enum AssetKind: String, Codable, Equatable, Sendable {
    case image
    case audio
    case particle
    case vehicle
}

struct ContentBudget: Codable, Equatable, Sendable {
    let maximumSections: Int
    let maximumTotalRoadLength: Double
    let maximumSceneryInstances: Int
    let maximumTrafficVehicles: Int

    static let recommended = ContentBudget(
        maximumSections: 256,
        maximumTotalRoadLength: 100_000,
        maximumSceneryInstances: 4_000,
        maximumTrafficVehicles: 64
    )
}

struct ClosedRangeValue<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    let lowerBound: Value
    let upperBound: Value
}
