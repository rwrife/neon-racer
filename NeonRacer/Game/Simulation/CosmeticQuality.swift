import Foundation

enum CosmeticQualityTier: String, CaseIterable, Codable, Sendable {
    case efficiency
    case balanced
    case fidelity
}

struct CosmeticQualityConfiguration: Equatable, Sendable {
    let tier: CosmeticQualityTier
    let expensiveEffectsEnabled: Bool
    let particleDensityScale: Double
    let sceneryDensityScale: Double
    let renderTargetScale: Double
    let glowScale: Double

    static let efficiency = CosmeticQualityConfiguration(
        tier: .efficiency,
        expensiveEffectsEnabled: false,
        particleDensityScale: 0.4,
        sceneryDensityScale: 0.55,
        renderTargetScale: 0.75,
        glowScale: 0.35
    )

    static let balanced = CosmeticQualityConfiguration(
        tier: .balanced,
        expensiveEffectsEnabled: true,
        particleDensityScale: 0.7,
        sceneryDensityScale: 0.8,
        renderTargetScale: 0.9,
        glowScale: 0.7
    )

    static let fidelity = CosmeticQualityConfiguration(
        tier: .fidelity,
        expensiveEffectsEnabled: true,
        particleDensityScale: 1,
        sceneryDensityScale: 1,
        renderTargetScale: 1,
        glowScale: 1
    )

    static func preset(for tier: CosmeticQualityTier) -> Self {
        switch tier {
        case .efficiency: .efficiency
        case .balanced: .balanced
        case .fidelity: .fidelity
        }
    }

    static var environmentDefault: Self {
        guard let value = ProcessInfo.processInfo.environment["NEON_RACER_QUALITY_TIER"],
              let tier = CosmeticQualityTier(rawValue: value.lowercased()) else {
            return .balanced
        }
        return preset(for: tier)
    }
}
