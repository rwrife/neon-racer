import Foundation

struct StageDefinition: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let palette: PaletteDefinition
    let sections: [RoadSectionDefinition]
}

struct PaletteDefinition: Codable, Equatable, Sendable {
    let skyTopHex: String
    let skyBottomHex: String
    let roadHex: String
    let accentHex: String
}

struct RoadSectionDefinition: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let length: Double
    let curve: Double
    let elevation: Double
}

