import Foundation

enum RenderQualityTier: String, CaseIterable, Codable, Sendable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var steppedDown: Self {
        switch self {
        case .high: .medium
        case .medium: .low
        case .low: .low
        }
    }

    func applyingThermal(_ state: RenderQualityThermalState) -> Self {
        switch state {
        case .nominal:
            self
        case .fair:
            steppedDown
        case .serious, .critical:
            .low
        }
    }

    var cosmeticTier: CosmeticQualityTier {
        switch self {
        case .low: .efficiency
        case .medium: .balanced
        case .high: .fidelity
        }
    }

    init(cosmeticTier: CosmeticQualityTier) {
        switch cosmeticTier {
        case .efficiency: self = .low
        case .balanced: self = .medium
        case .fidelity: self = .high
        }
    }
}

enum RenderQualityPreference: String, CaseIterable, Codable, Sendable, Identifiable {
    case automatic
    case low
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .low: RenderQualityTier.low.displayName
        case .medium: RenderQualityTier.medium.displayName
        case .high: RenderQualityTier.high.displayName
        }
    }

    var explicitTier: RenderQualityTier? {
        switch self {
        case .automatic: nil
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
    }
}

enum RenderQualityThermalState: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }
}

enum RenderAntialiasingQuality: String, Codable, Sendable {
    case none
    case multisampling2X
    case multisampling4X
}

struct RenderQualityDeviceProfile: Equatable, Sendable {
    var physicalMemoryBytes: UInt64
    var thermalState: RenderQualityThermalState
    var isSimulator: Bool

    static func current(processInfo: ProcessInfo = .processInfo) -> Self {
#if targetEnvironment(simulator)
        let isSimulator = true
#else
        let isSimulator = false
#endif
        return Self(
            physicalMemoryBytes: processInfo.physicalMemory,
            thermalState: RenderQualityThermalState(processInfo.thermalState),
            isSimulator: isSimulator
        )
    }
}

struct RenderQualityConfiguration: Equatable, Sendable {
    let tier: RenderQualityTier
    let contentScale: Double
    let bloomEnabled: Bool
    let postProcessingEnabled: Bool
    let particleDensityScale: Double
    let sceneryDensityScale: Double
    let drawDistanceMeters: Double
    let antialiasing: RenderAntialiasingQuality

    static func preset(for tier: RenderQualityTier) -> Self {
        switch tier {
        case .low:
            Self(
                tier: .low,
                contentScale: 0.72,
                bloomEnabled: false,
                postProcessingEnabled: false,
                particleDensityScale: 0.4,
                sceneryDensityScale: 0.55,
                drawDistanceMeters: 560,
                antialiasing: .none
            )
        case .medium:
            Self(
                tier: .medium,
                contentScale: 0.9,
                bloomEnabled: true,
                postProcessingEnabled: false,
                particleDensityScale: 0.7,
                sceneryDensityScale: 0.8,
                drawDistanceMeters: 720,
                antialiasing: .multisampling2X
            )
        case .high:
            Self(
                tier: .high,
                contentScale: 1,
                bloomEnabled: true,
                postProcessingEnabled: true,
                particleDensityScale: 1,
                sceneryDensityScale: 1,
                drawDistanceMeters: 850,
                antialiasing: .multisampling4X
            )
        }
    }

    static func selected(
        preference: RenderQualityPreference,
        deviceProfile: RenderQualityDeviceProfile = .current()
    ) -> Self {
        let baseTier = preference.explicitTier ?? automaticTier(for: deviceProfile)
        var tier = baseTier.applyingThermal(deviceProfile.thermalState)
        if deviceProfile.isSimulator, tier == .high, preference == .automatic {
            tier = .medium
        }
        return preset(for: tier)
    }

    static func automaticTier(for profile: RenderQualityDeviceProfile) -> RenderQualityTier {
        if profile.isSimulator {
            return .medium
        }
        let gib = profile.physicalMemoryBytes / 1_073_741_824
        if gib >= 6 {
            return .high
        }
        if gib >= 4 {
            return .medium
        }
        return .low
    }
}

extension CosmeticQualityConfiguration {
    static func preset(for tier: RenderQualityTier) -> Self {
        preset(for: tier.cosmeticTier)
    }
}
