import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct AccessibilitySettingsTests {
    @Test
    func settingsRoundTripThroughPersistence() throws {
        let suiteName = "AccessibilitySettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = AccessibilitySettingsPersistence(defaults: defaults, key: "test-settings")
        let expected = AccessibilitySettings(
            reduceMotion: true,
            reduceFlashes: true,
            highContrast: true,
            largeHUD: true,
            palette: .blueOrange
        )

        persistence.save(expected)

        #expect(persistence.load() == expected)
    }

    @Test
    func missingAndInvalidDataUseDefaults() throws {
        let suiteName = "AccessibilitySettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = AccessibilitySettingsPersistence(defaults: defaults, key: "test-settings")

        #expect(persistence.load() == .defaults)
        defaults.set(Data("not-json".utf8), forKey: "test-settings")
        #expect(persistence.load() == .defaults)
    }

    @Test
    func olderSettingsPayloadReceivesNewDefaults() throws {
        let decoded = try JSONDecoder().decode(
            AccessibilitySettings.self,
            from: Data(#"{"reduceMotion":true}"#.utf8)
        )

        #expect(decoded.reduceMotion)
        #expect(!decoded.reduceFlashes)
        #expect(!decoded.highContrast)
        #expect(!decoded.largeHUD)
        #expect(decoded.palette == .neon)
    }

    @Test
    func systemReduceMotionCannotBeOverriddenOff() {
        var settings = AccessibilitySettings.defaults
        #expect(settings.resolvedReduceMotion(systemReduceMotion: true))

        settings.reduceMotion = true
        #expect(settings.resolvedReduceMotion(systemReduceMotion: false))
    }

    @Test(arguments: AccessibilityPalette.allCases)
    func palettesKeepReadableTextContrast(choice: AccessibilityPalette) {
        let palette = PaletteComponents.resolve(choice, highContrast: true)

        #expect(palette.text.contrastRatio(with: palette.background) >= 7)
        #expect(palette.primary != palette.secondary)
    }
}
