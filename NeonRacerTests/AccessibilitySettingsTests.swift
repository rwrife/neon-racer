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

    @Test
    func audioBindingSettersUseExplicitClosuresNotBoundMethodReferences() throws {
        let testFilePath = URL(fileURLWithPath: #filePath)
        let repoRoot = testFilePath
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let targetPath = repoRoot
            .appendingPathComponent("NeonRacer")
            .appendingPathComponent("Features")
            .appendingPathComponent("Settings")
            .appendingPathComponent("AccessibilitySettingsView.swift")
        let source = try String(contentsOf: targetPath, encoding: .utf8)

        let boundMethodSetterPattern = try Regex(#"set:\s*audio\.set[A-Za-z]+"#)
        let matches = source.matches(of: boundMethodSetterPattern)

        #expect(
            matches.isEmpty,
            "Found \(matches.count) SwiftUI Binding `set:` argument(s) that pass a bound "
                + "@MainActor AudioService method reference directly. This exact shape crashed "
                + "the Xcode 26.6 Swift 6.3.3 compiler during IRGen "
                + "(SIL function $sSbScA_pSgIeAghyg_SbIeAghn_TR). Use an explicit "
                + "`{ audio.setXxx($0) }` closure instead."
        )

        for setterName in ["setMusicLevel", "setMusicMuted", "setEffectsLevel", "setEffectsMuted"] {
            let explicitClosurePattern = "{ audio.\(setterName)($0) }"
            #expect(
                source.contains(explicitClosurePattern),
                "Expected an explicit closure `\(explicitClosurePattern)` wiring \(setterName) "
                    + "into its Binding setter."
            )
        }
    }
}
