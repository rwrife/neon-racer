import Foundation

enum AccessibilityPalette: String, Codable, CaseIterable, Identifiable, Sendable {
    case neon
    case blueOrange
    case magentaGreen

    var id: Self { self }

    var displayName: String {
        switch self {
        case .neon: "Classic Neon"
        case .blueOrange: "Blue & Orange"
        case .magentaGreen: "Magenta & Green"
        }
    }
}

struct AccessibilitySettings: Codable, Equatable, Sendable {
    var reduceMotion: Bool
    var reduceFlashes: Bool
    var highContrast: Bool
    var largeHUD: Bool
    var palette: AccessibilityPalette

    static let defaults = AccessibilitySettings(
        reduceMotion: false,
        reduceFlashes: false,
        highContrast: false,
        largeHUD: false,
        palette: .neon
    )

    init(
        reduceMotion: Bool,
        reduceFlashes: Bool,
        highContrast: Bool,
        largeHUD: Bool,
        palette: AccessibilityPalette
    ) {
        self.reduceMotion = reduceMotion
        self.reduceFlashes = reduceFlashes
        self.highContrast = highContrast
        self.largeHUD = largeHUD
        self.palette = palette
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reduceMotion = try container.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        reduceFlashes = try container.decodeIfPresent(Bool.self, forKey: .reduceFlashes) ?? false
        highContrast = try container.decodeIfPresent(Bool.self, forKey: .highContrast) ?? false
        largeHUD = try container.decodeIfPresent(Bool.self, forKey: .largeHUD) ?? false
        palette = try container.decodeIfPresent(AccessibilityPalette.self, forKey: .palette) ?? .neon
    }

    func resolvedReduceMotion(systemReduceMotion: Bool) -> Bool {
        reduceMotion || systemReduceMotion
    }
}

struct AccessibilitySettingsPersistence {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "accessibility-settings") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> AccessibilitySettings {
        guard
            let data = defaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(AccessibilitySettings.self, from: data)
        else {
            return .defaults
        }
        return settings
    }

    func save(_ settings: AccessibilitySettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
