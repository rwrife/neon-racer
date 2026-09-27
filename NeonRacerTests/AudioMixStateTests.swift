import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct AudioMixStateTests {
    @Test
    func musicAndEffectsMuteIndependentlyWithoutLosingLevels() {
        let preferences = AudioPreferences(
            musicLevel: 0.35,
            effectsLevel: 0.8,
            isMusicMuted: true,
            areEffectsMuted: false
        )

        #expect(preferences.gain(for: .music) == 0)
        #expect(preferences.gain(for: .engine) == 0.8)
        #expect(preferences.musicLevel == 0.35)

        let effectsMuted = AudioPreferences(
            musicLevel: preferences.musicLevel,
            effectsLevel: preferences.effectsLevel,
            isMusicMuted: false,
            areEffectsMuted: true
        )
        #expect(effectsMuted.gain(for: .music) == 0.35)
        #expect(effectsMuted.gain(for: .impacts) == 0)
    }

    @Test
    @MainActor
    func audioSettingsStorePersistsIndependentPreferences() {
        let suiteName = "AudioMixStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = AudioSettingsStore(defaults: defaults, key: "audio-test")
        store.update {
            $0.musicLevel = 0.22
            $0.effectsLevel = 0.91
            $0.isMusicMuted = true
            $0.areEffectsMuted = false
        }

        let reloaded = AudioSettingsStore(defaults: defaults, key: "audio-test")
        #expect(reloaded.preferences.musicLevel == 0.22)
        #expect(reloaded.preferences.effectsLevel == 0.91)
        #expect(reloaded.preferences.isMusicMuted)
        #expect(!reloaded.preferences.areEffectsMuted)
        #expect(reloaded.preferences.gain(for: .music) == 0)
        #expect(reloaded.preferences.gain(for: .engine) == 0.91)
    }

    @Test
    func engineParametersAreBoundedAndSmoothed() {
        var state = AudioMixState()
        state.handle(.raceStarted)
        state.advanceEngine(
            input: EngineAudioInput(
                normalizedRPM: 4,
                normalizedSpeed: 3,
                throttle: 2,
                drift: 2,
                boost: 1,
                offRoad: 2,
                collisionRecovery: -1
            ),
            deltaTime: 1.0 / 120.0
        )

        #expect(state.engine.pitchRate > 0.72)
        #expect(state.engine.pitchRate < 1.76)
        #expect(state.engine.engineGain > 0)
        #expect(state.engine.engineGain < 0.9)
        #expect(state.engine.tireGain > 0)
        #expect(state.engine.tireGain < 0.72)
    }

    @Test
    func pauseBackgroundAndInterruptionGateRendering() {
        var state = AudioMixState()
        state.handle(.raceStarted)
        #expect(state.shouldPlayMusic)
        #expect(state.shouldPlayVehicleAudio)

        state.handle(.racePaused)
        #expect(!state.shouldPlayMusic)
        #expect(!state.shouldPlayVehicleAudio)

        state.handle(.raceResumed)
        state.setApplicationActive(false)
        #expect(!state.shouldRender)

        state.setApplicationActive(true)
        state.setInterrupted(true)
        #expect(!state.shouldRender)

        state.setInterrupted(false)
        #expect(state.shouldPlayVehicleAudio)
    }

    @Test
    func adaptiveEventsChangeSectionsWithoutResettingRaceState() {
        var state = AudioMixState()
        state.handle(.raceStarted)
        #expect(state.musicSection == .countdown)

        state.handle(.checkpoint)
        #expect(state.musicSection == .intense)
        #expect(state.isRaceActive)

        state.handle(.environmentChanged(.tunnel))
        #expect(state.environment == .tunnel)

        state.handle(.finish)
        #expect(state.musicSection == .finish)
        #expect(!state.isRaceActive)

        state.handle(.raceRetried)
        #expect(state.musicSection == .countdown)
        #expect(state.isRaceActive)
    }
}
