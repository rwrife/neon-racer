import AVFoundation
import AudioToolbox
import Combine
import os

@MainActor
final class AudioService: NSObject, ObservableObject {
    enum Event {
        case interruptionBegan
        case interruptionEnded
        case routeChanged
    }

    @Published private(set) var preferences: AudioPreferences

    private let engine = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()
    private var masterLimiter: AVAudioUnitEffect?
    private let musicLayerMixer = AVAudioMixerNode()
    private let musicEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let musicBassPlayer = AVAudioPlayerNode()
    private let musicArpeggioPlayer = AVAudioPlayerNode()
    private let musicPadPlayer = AVAudioPlayerNode()
    private let musicDrumPlayer = AVAudioPlayerNode()
    private let musicPulsePlayer = AVAudioPlayerNode()
    private let engineLayerMixer = AVAudioMixerNode()
    private let enginePlayer = AVAudioPlayerNode()
    private let engineHarmonicPlayer = AVAudioPlayerNode()
    private let engineBoostPlayer = AVAudioPlayerNode()
    private let tirePlayer = AVAudioPlayerNode()
    private let ambienceCityPlayer = AVAudioPlayerNode()
    private let ambienceCoastPlayer = AVAudioPlayerNode()
    private let ambienceDesertPlayer = AVAudioPlayerNode()
    private let ambienceTunnelPlayer = AVAudioPlayerNode()
    private let engineRate = AVAudioUnitVarispeed()
    private var buses: [AudioBus: AVAudioMixerNode] = [:]
    private var oneShotPlayers: [AudioBus: [AVAudioPlayerNode]] = [:]
    private var oneShotCursor: [AudioBus: Int] = [:]
    private var cueBuffers: [ProceduralAudio.Cue: AVAudioPCMBuffer] = [:]
    private var mixState: AudioMixState
    private var engineLayers = EngineLayerMix()
    private var ambienceLayers = AmbienceLayerMix()
    private var isConfigured = false
    private let settingsStore: AudioSettingsStore
    private var eventHandler: ((Event) -> Void)?

    init(defaults: UserDefaults = .standard, settingsStore: AudioSettingsStore? = nil) {
        let resolvedStore = settingsStore ?? AudioSettingsStore(defaults: defaults)
        self.settingsStore = resolvedStore
        preferences = resolvedStore.preferences
        mixState = AudioMixState(preferences: resolvedStore.preferences)
        super.init()
        observeAudioSession()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func beginObserving(_ eventHandler: @escaping (Event) -> Void) {
        self.eventHandler = eventHandler
    }

    func endObserving() {
        eventHandler = nil
    }

    func start() throws {
        configureIfNeeded()
        guard isConfigured, mixState.shouldRender else { return }

        try configureSession()
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        startContinuousPlayersIfNeeded()
        applyMix()
    }

    func stop() {
        applySilentMix()
        engine.pause()
        deactivateSession()
    }

    func handle(_ event: AudioEvent) {
        mixState.handle(event)
        do {
            try start()
        } catch {
            Logger.audio.error("Failed to start audio for event: \(error.localizedDescription)")
        }
        playOneShot(for: event)
        applyMix()
    }

    func updateEngine(_ input: EngineAudioInput, deltaTime: TimeInterval) {
        mixState.advanceEngine(input: input, deltaTime: deltaTime)
        engineLayers.advance(input: input, deltaTime: deltaTime)
        ambienceLayers.advance(target: mixState.environment, deltaTime: deltaTime)
        applyMix()
    }

    func setMusicLevel(_ level: Double) {
        updatePreferences {
            $0.musicLevel = min(max(level, 0), 1)
        }
    }

    func setEffectsLevel(_ level: Double) {
        updatePreferences {
            $0.effectsLevel = min(max(level, 0), 1)
        }
    }

    func setMusicMuted(_ muted: Bool) {
        updatePreferences { $0.isMusicMuted = muted }
    }

    func setEffectsMuted(_ muted: Bool) {
        updatePreferences { $0.areEffectsMuted = muted }
    }

    func setApplicationActive(_ active: Bool) {
        mixState.setApplicationActive(active)
        if active {
            resumeAfterSuspension()
        } else {
            suspend()
        }
    }

    private func updatePreferences(_ update: (inout AudioPreferences) -> Void) {
        settingsStore.update(update)
        preferences = settingsStore.preferences
        mixState.setPreferences(preferences)
        applyMix()
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        engine.attach(masterMixer)
        if let limiter = Self.makeMasterLimiter() {
            masterLimiter = limiter
            engine.attach(limiter)
            engine.connect(masterMixer, to: limiter, format: format)
            engine.connect(limiter, to: engine.mainMixerNode, format: format)
        } else {
            masterMixer.outputVolume = 0.68
            engine.connect(masterMixer, to: engine.mainMixerNode, format: format)
            Logger.audio.error("No Apple limiter audio unit was available; using conservative master headroom")
        }

        for bus in AudioBus.allCases {
            let mixer = AVAudioMixerNode()
            buses[bus] = mixer
            engine.attach(mixer)
            engine.connect(mixer, to: masterMixer, format: format)
        }

        configureMusicGraph(format: format)
        configureVehicleGraph(format: format)
        configureAmbienceGraph(format: format)
        configureOneShotGraph(format: format)
        configureContinuousBuffers(format: format)
        configureCueBuffers(format: format)

        musicEQ.bands[0].filterType = .lowPass
        musicEQ.bands[0].frequency = 12_000
        musicEQ.bands[0].bypass = false
        masterMixer.outputVolume = masterLimiter == nil ? 0.68 : 0.78
        engine.mainMixerNode.outputVolume = 1

        isConfigured = true
    }

    private static func makeMasterLimiter() -> AVAudioUnitEffect? {
        for subtype in [kAudioUnitSubType_PeakLimiter, kAudioUnitSubType_DynamicsProcessor] {
            let description = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: subtype,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            guard !AVAudioUnitComponentManager.shared().components(matching: description).isEmpty else {
                continue
            }
            return AVAudioUnitEffect(audioComponentDescription: description)
        }
        return nil
    }

    private func configureMusicGraph(format: AVAudioFormat) {
        engine.attach(musicLayerMixer)
        engine.attach(musicEQ)
        for player in musicPlayers {
            engine.attach(player)
            engine.connect(player, to: musicLayerMixer, format: format)
        }
        engine.connect(musicLayerMixer, to: musicEQ, format: format)
        engine.connect(musicEQ, to: buses[.music]!, format: format)
    }

    private func configureVehicleGraph(format: AVAudioFormat) {
        engine.attach(engineLayerMixer)
        engine.attach(engineRate)
        for player in [enginePlayer, engineHarmonicPlayer] {
            engine.attach(player)
            engine.connect(player, to: engineLayerMixer, format: format)
        }
        engine.connect(engineLayerMixer, to: engineRate, format: format)
        engine.connect(engineRate, to: buses[.engine]!, format: format)
        connect(engineBoostPlayer, to: .engine, format: format)
        connect(tirePlayer, to: .tires, format: format)
    }

    private func configureAmbienceGraph(format: AVAudioFormat) {
        for player in ambiencePlayers.map(\.player) {
            connect(player, to: .ambience, format: format)
        }
    }

    private func configureOneShotGraph(format: AVAudioFormat) {
        for bus in [AudioBus.impacts, .ui, .voice] {
            let pool = (0..<4).map { _ in AVAudioPlayerNode() }
            oneShotPlayers[bus] = pool
            oneShotCursor[bus] = 0
            for player in pool {
                connect(player, to: bus, format: format)
            }
        }
    }

    private func configureContinuousBuffers(format: AVAudioFormat) {
        for stem in ProceduralAudio.MusicStem.allCases {
            musicPlayer(for: stem).scheduleBuffer(
                ProceduralAudio.musicStem(stem, format: format),
                at: nil,
                options: .loops
            )
        }
        enginePlayer.scheduleBuffer(
            ProceduralAudio.engine(format: format, layer: .fundamental),
            at: nil,
            options: .loops
        )
        engineHarmonicPlayer.scheduleBuffer(
            ProceduralAudio.engine(format: format, layer: .harmonics),
            at: nil,
            options: .loops
        )
        engineBoostPlayer.scheduleBuffer(
            ProceduralAudio.engine(format: format, layer: .boostWhine),
            at: nil,
            options: .loops
        )
        tirePlayer.scheduleBuffer(
            ProceduralAudio.noise(format: format, color: .bright),
            at: nil,
            options: .loops
        )
        for ambience in ambiencePlayers {
            ambience.player.scheduleBuffer(
                ProceduralAudio.ambience(format: format, environment: ambience.environment),
                at: nil,
                options: .loops
            )
        }
    }

    private func configureCueBuffers(format: AVAudioFormat) {
        for cue in ProceduralAudio.Cue.allCases {
            cueBuffers[cue] = ProceduralAudio.cue(cue, format: format)
        }
    }

    private func connect(
        _ player: AVAudioPlayerNode,
        to bus: AudioBus,
        format: AVAudioFormat
    ) {
        engine.attach(player)
        engine.connect(player, to: buses[bus]!, format: format)
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    private func startContinuousPlayersIfNeeded() {
        continuousPlayers.forEach {
            if !$0.isPlaying {
                $0.play()
            }
        }
    }

    private func applyMix() {
        guard isConfigured else { return }
        let rendering = mixState.shouldRender
        let vehicle = mixState.shouldPlayVehicleAudio
        let musicGain = rendering && mixState.shouldPlayMusic
            ? preferences.gain(for: .music) * mixState.musicSectionGain()
            : 0
        let effectsGain = rendering ? preferences.gain(for: .impacts) : 0

        buses[.music]?.outputVolume = Float(musicGain)
        buses[.engine]?.outputVolume = Float(
            vehicle ? preferences.gain(for: .engine) * mixState.engine.engineGain : 0
        )
        buses[.tires]?.outputVolume = Float(
            vehicle ? preferences.gain(for: .tires) * mixState.engine.tireGain : 0
        )
        buses[.ambience]?.outputVolume = Float(
            rendering ? preferences.gain(for: .ambience) * mixState.engine.ambienceGain : 0
        )
        for bus in [AudioBus.impacts, .ui, .voice] {
            buses[bus]?.outputVolume = Float(effectsGain * busHeadroom(bus))
        }

        applyMusicLayerMix(for: mixState.musicSection)
        applyVehicleLayerMix(isPlaying: vehicle)
        applyAmbienceMix(isRendering: rendering)
        engineRate.rate = Float(mixState.engine.pitchRate)
        musicEQ.bands[0].frequency = musicCutoff(for: mixState.musicSection)
    }

    private func applyMusicLayerMix(for section: AdaptiveMusicSection) {
        let gains = musicLayerGains(for: section)
        musicBassPlayer.volume = Float(gains.bass)
        musicArpeggioPlayer.volume = Float(gains.arpeggio)
        musicPadPlayer.volume = Float(gains.pad)
        musicDrumPlayer.volume = Float(gains.drums)
        musicPulsePlayer.volume = Float(gains.pulse)
    }

    private func applyVehicleLayerMix(isPlaying: Bool) {
        guard isPlaying else {
            enginePlayer.volume = 0
            engineHarmonicPlayer.volume = 0
            engineBoostPlayer.volume = 0
            tirePlayer.volume = 0
            return
        }

        enginePlayer.volume = Float(engineLayers.fundamental)
        engineHarmonicPlayer.volume = Float(engineLayers.harmonics)
        engineBoostPlayer.volume = Float(engineLayers.boostWhine)
        tirePlayer.volume = Float(engineLayers.tireBrightness)
    }

    private func applyAmbienceMix(isRendering: Bool) {
        for ambience in ambiencePlayers {
            let level = isRendering ? ambienceLayers.level(for: ambience.environment) : 0
            ambience.player.volume = Float(level * ambience.headroom)
        }
    }

    private func busHeadroom(_ bus: AudioBus) -> Double {
        switch bus {
        case .impacts: 0.84
        case .voice: 0.82
        case .ui: 0.64
        default: 1
        }
    }

    private func musicCutoff(for section: AdaptiveMusicSection) -> Float {
        switch section {
        case .menu: 5_500
        case .countdown: 7_500
        case .racing: 11_000
        case .intense: 16_000
        case .finish: 9_000
        case .failure: 2_600
        }
    }

    private func musicLayerGains(for section: AdaptiveMusicSection) -> MusicLayerGains {
        switch section {
        case .menu:
            MusicLayerGains(bass: 0.25, arpeggio: 0.18, pad: 0.75, drums: 0.08, pulse: 0)
        case .countdown:
            MusicLayerGains(bass: 0.42, arpeggio: 0.22, pad: 0.7, drums: 0.18, pulse: 0.82)
        case .racing:
            MusicLayerGains(bass: 0.82, arpeggio: 0.55, pad: 0.7, drums: 0.72, pulse: 0.15)
        case .intense:
            MusicLayerGains(bass: 0.95, arpeggio: 0.88, pad: 0.82, drums: 0.98, pulse: 0.36)
        case .finish:
            MusicLayerGains(bass: 0.48, arpeggio: 0.35, pad: 0.92, drums: 0.3, pulse: 0.2)
        case .failure:
            MusicLayerGains(bass: 0.18, arpeggio: 0.08, pad: 0.58, drums: 0.04, pulse: 0)
        }
    }

    private func playOneShot(for event: AudioEvent) {
        let cue: (AudioBus, ProceduralAudio.Cue)?
        switch event {
        case .checkpoint: cue = (.voice, .checkpoint)
        case .pass: cue = (.ui, .pass)
        case .nearMiss: cue = (.ui, .nearMiss)
        case .combo: cue = (.ui, .combo)
        case .boost: cue = (.impacts, .boost)
        case let .crash(severity): cue = (.impacts, ProceduralAudio.Cue.crashCue(for: severity))
        case .finish: cue = (.voice, .finish)
        case .failure: cue = (.voice, .failure)
        case .uiConfirm, .raceStarted, .raceRetried: cue = (.ui, .confirm)
        case .showMenu, .racePaused, .raceResumed, .raceExited, .environmentChanged:
            cue = nil
        }
        guard let (bus, sound) = cue,
              let buffer = cueBuffers[sound],
              let player = nextOneShotPlayer(for: bus) else {
            return
        }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
    }

    private func nextOneShotPlayer(for bus: AudioBus) -> AVAudioPlayerNode? {
        guard let players = oneShotPlayers[bus], !players.isEmpty else { return nil }
        let cursor = oneShotCursor[bus, default: 0]
        oneShotCursor[bus] = (cursor + 1) % players.count
        return players[cursor % players.count]
    }

    private func suspend() {
        applySilentMix()
        engine.pause()
        deactivateSession()
    }

    private func applySilentMix() {
        buses.values.forEach { $0.outputVolume = 0 }
        continuousPlayers.forEach { $0.volume = 0 }
    }

    private func resumeAfterSuspension() {
        guard !mixState.isInterrupted, mixState.shouldRender else { return }
        do {
            try start()
        } catch {
            Logger.audio.error("Failed to resume audio after session change: \(error.localizedDescription)")
        }
    }

    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        } catch {
            Logger.audio.error("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            Logger.audio.error("Audio interruption notification was missing its type")
            return
        }

        switch type {
        case .began:
            mixState.setInterrupted(true)
            suspend()
            eventHandler?(.interruptionBegan)
        case .ended:
            mixState.setInterrupted(false)
            let lifecycleObserver = eventHandler
            lifecycleObserver?(.interruptionEnded)
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if lifecycleObserver == nil, options.contains(.shouldResume) {
                resumeAfterSuspension()
            } else {
                applyMix()
            }
        @unknown default:
            Logger.audio.error("Received unknown audio interruption type: \(rawType)")
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else {
            Logger.audio.error("Audio route notification was missing its reason")
            return
        }
        Logger.audio.info("Audio route changed: \(String(describing: reason), privacy: .public)")
        if reason == .oldDeviceUnavailable {
            suspend()
            eventHandler?(.routeChanged)
        } else if reason == .newDeviceAvailable || reason == .categoryChange {
            resumeAfterSuspension()
        }
    }

    @objc private func handleEngineConfigurationChange() {
        resumeAfterSuspension()
    }
}

private extension AudioService {
    var musicPlayers: [AVAudioPlayerNode] {
        [musicBassPlayer, musicArpeggioPlayer, musicPadPlayer, musicDrumPlayer, musicPulsePlayer]
    }

    var continuousPlayers: [AVAudioPlayerNode] {
        musicPlayers
            + [enginePlayer, engineHarmonicPlayer, engineBoostPlayer, tirePlayer]
            + ambiencePlayers.map(\.player)
    }

    var ambiencePlayers: [(environment: AudioEnvironment, player: AVAudioPlayerNode, headroom: Double)] {
        [
            (.city, ambienceCityPlayer, 0.9),
            (.coast, ambienceCoastPlayer, 0.8),
            (.desert, ambienceDesertPlayer, 0.75),
            (.tunnel, ambienceTunnelPlayer, 0.86)
        ]
    }

    func musicPlayer(for stem: ProceduralAudio.MusicStem) -> AVAudioPlayerNode {
        switch stem {
        case .bass: musicBassPlayer
        case .arpeggio: musicArpeggioPlayer
        case .pad: musicPadPlayer
        case .drums: musicDrumPlayer
        case .countdownPulse: musicPulsePlayer
        }
    }
}

private extension Logger {
    static let audio = Logger(subsystem: "com.neonracer.app", category: "Audio")
}

private struct MusicLayerGains {
    var bass: Double
    var arpeggio: Double
    var pad: Double
    var drums: Double
    var pulse: Double
}

private struct EngineLayerMix {
    var fundamental = 0.72
    var harmonics = 0.22
    var boostWhine = 0.0
    var tireBrightness = 0.65

    mutating func advance(input: EngineAudioInput, deltaTime: TimeInterval) {
        let rpm = input.normalizedRPM.clamped(to: 0...1)
        let throttle = input.throttle.clamped(to: 0...1)
        let boost = input.boost.clamped(to: 0...1)
        let drift = input.drift.clamped(to: 0...1)
        let offRoad = input.offRoad.clamped(to: 0...1)
        let recovery = input.collisionRecovery.clamped(to: 0...1)
        let target = EngineLayerMix(
            fundamental: 0.58 + throttle * 0.22 + recovery * 0.08,
            harmonics: 0.16 + rpm * 0.46 + throttle * 0.14,
            boostWhine: boost * 0.78,
            tireBrightness: 0.48 + drift * 0.34 + offRoad * 0.18
        )
        let attack = smoothingFactor(deltaTime: deltaTime, timeConstant: 0.055)
        let release = smoothingFactor(deltaTime: deltaTime, timeConstant: 0.16)
        fundamental = smooth(fundamental, target.fundamental, attack: attack, release: release)
        harmonics = smooth(harmonics, target.harmonics, attack: attack, release: release)
        boostWhine = smooth(boostWhine, target.boostWhine, attack: attack, release: release)
        tireBrightness = smooth(tireBrightness, target.tireBrightness, attack: attack, release: release)
    }

    private func smoothingFactor(deltaTime: TimeInterval, timeConstant: TimeInterval) -> Double {
        guard deltaTime > 0 else { return 0 }
        return 1 - exp(-min(deltaTime, 0.25) / timeConstant)
    }

    private func smooth(_ current: Double, _ target: Double, attack: Double, release: Double) -> Double {
        current + (target - current) * (target > current ? attack : release)
    }
}

private struct AmbienceLayerMix {
    var city = 1.0
    var coast = 0.0
    var desert = 0.0
    var tunnel = 0.0

    mutating func advance(target environment: AudioEnvironment, deltaTime: TimeInterval) {
        let amount = smoothingFactor(deltaTime: deltaTime, timeConstant: 0.45)
        city = smooth(city, environment == .city ? 1 : 0, amount: amount)
        coast = smooth(coast, environment == .coast ? 1 : 0, amount: amount)
        desert = smooth(desert, environment == .desert ? 1 : 0, amount: amount)
        tunnel = smooth(tunnel, environment == .tunnel ? 1 : 0, amount: amount)
    }

    func level(for environment: AudioEnvironment) -> Double {
        switch environment {
        case .city: city
        case .coast: coast
        case .desert: desert
        case .tunnel: tunnel
        }
    }

    private func smoothingFactor(deltaTime: TimeInterval, timeConstant: TimeInterval) -> Double {
        guard deltaTime > 0 else { return 0 }
        return 1 - exp(-min(deltaTime, 0.25) / timeConstant)
    }

    private func smooth(_ current: Double, _ target: Double, amount: Double) -> Double {
        current + (target - current) * amount
    }
}

private enum ProceduralAudio {
    enum NoiseColor {
        case bright
        case dark
    }

    enum EngineLayer {
        case fundamental
        case harmonics
        case boostWhine
    }

    enum MusicStem: CaseIterable {
        case bass
        case arpeggio
        case pad
        case drums
        case countdownPulse
    }

    enum Cue: CaseIterable, Hashable {
        case confirm
        case pass
        case nearMiss
        case combo
        case checkpoint
        case boost
        case crashLight
        case crashMedium
        case crashHeavy
        case finish
        case failure

        static func crashCue(for severity: Double) -> Cue {
            switch severity.clamped(to: 0...1) {
            case ..<0.34: .crashLight
            case ..<0.67: .crashMedium
            default: .crashHeavy
            }
        }
    }

    static func engine(format: AVAudioFormat, layer: EngineLayer) -> AVAudioPCMBuffer {
        makeBuffer(format: format, duration: 1) { time in
            switch layer {
            case .fundamental:
                let phase = time * 55 * 2 * .pi
                return tanh(
                    sin(phase) * 0.52
                        + sin(phase * 2) * 0.22
                        + sin(phase * 3) * 0.1
                ) * 0.42
            case .harmonics:
                let phase = time * 91 * 2 * .pi
                let pulse = sin(time * 8 * 2 * .pi) * 0.04
                return tanh(
                    sin(phase) * 0.34
                        + sin(phase * 1.49) * 0.22
                        + sin(phase * 2.01) * 0.14
                        + pulse
                ) * 0.34
            case .boostWhine:
                let sweep = 360 + sin(time * 0.5 * 2 * .pi) * 42
                let shimmer = sin(time * 1_420 * 2 * .pi) * 0.08
                return tanh(
                    sin(time * sweep * 2 * .pi) * 0.24
                        + sin(time * sweep * 4 * .pi) * 0.1
                        + shimmer
                ) * 0.26
            }
        }
    }

    static func musicStem(_ stem: MusicStem, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let bpm = 108.0
        let beat = 60 / bpm
        let duration = beat * 16
        let roots = [55.0, 55.0, 65.41, 73.42, 49.0, 49.0, 65.41, 73.42]
        return makeBuffer(format: format, duration: duration) { time in
            let step = Int(time / (beat * 2)) % roots.count
            let root = roots[step]
            switch stem {
            case .bass:
                let gate = gate(time: time, interval: beat / 2, decay: 7)
                return tanh(
                    (sin(time * root * 2 * .pi)
                        + 0.38 * sin(time * root * 4 * .pi)
                        + 0.12 * sin(time * root * 6 * .pi)) * gate
                ) * 0.38
            case .arpeggio:
                let ratios = [2.0, 3.0, 4.0, 6.0, 4.0, 3.0, 2.0, 1.5]
                let ratio = ratios[Int(time / (beat / 2)) % ratios.count]
                let envelope = gate(time: time, interval: beat / 2, decay: 5.5)
                let frequency = root * ratio
                return (sin(time * frequency * 2 * .pi)
                    + 0.18 * sin(time * frequency * 4 * .pi)) * envelope * 0.2
            case .pad:
                let chord = [1.0, 1.5, 2.0, 2.5]
                let swell = 0.62 + 0.38 * sin(time * (1 / (beat * 8)) * 2 * .pi)
                let pad = chord.enumerated().reduce(0.0) { partial, item in
                    partial + sin(time * root * item.element * 2 * .pi + Double(item.offset) * 0.7) * 0.08
                }
                return tanh(pad * swell) * 0.9
            case .drums:
                return drumSample(time: time, beat: beat)
            case .countdownPulse:
                let pulse = gate(time: time, interval: beat, decay: 9)
                return sin(time * 880 * 2 * .pi) * pulse * 0.22
            }
        }
    }

    static func noise(format: AVAudioFormat, color: NoiseColor) -> AVAudioPCMBuffer {
        var seed: UInt64 = color == .bright ? 0xA11CE : 0xBADC0DE
        var previous = 0.0
        return makeBuffer(format: format, duration: 2) { _ in
            let white = randomSample(seed: &seed)
            switch color {
            case .bright:
                return white * 0.22
            case .dark:
                previous = previous * 0.94 + white * 0.06
                return previous * 0.3
            }
        }
    }

    static func ambience(format: AVAudioFormat, environment: AudioEnvironment) -> AVAudioPCMBuffer {
        var seed = ambienceSeed(for: environment) ^ 0xCAFE_BABE
        var low = 0.0
        var shimmer = 0.0
        return makeBuffer(format: format, duration: 4) { time in
            let white = randomSample(seed: &seed)
            low = low * 0.985 + white * 0.015
            shimmer = shimmer * 0.74 + white * 0.26
            switch environment {
            case .city:
                let hum = sin(time * 62 * 2 * .pi) * 0.08 + sin(time * 123 * 2 * .pi) * 0.035
                return low * 0.24 + hum
            case .coast:
                let wave = sin(time * 0.21 * 2 * .pi) * 0.08
                return low * 0.34 + shimmer * 0.035 + wave
            case .desert:
                let wind = shimmer * (0.08 + 0.05 * sin(time * 0.13 * 2 * .pi))
                return low * 0.18 + wind
            case .tunnel:
                let resonance = sin(time * 92 * 2 * .pi) * 0.07 + sin(time * 184 * 2 * .pi) * 0.035
                return low * 0.42 + resonance
            }
        }
    }

    static func cue(_ cue: Cue, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let specification: (duration: Double, start: Double, end: Double, noise: Double)
        switch cue {
        case .confirm: specification = (0.12, 520, 780, 0)
        case .pass: specification = (0.14, 720, 980, 0.02)
        case .nearMiss: specification = (0.18, 900, 1_500, 0.04)
        case .combo: specification = (0.24, 660, 1_100, 0)
        case .checkpoint: specification = (0.38, 440, 880, 0)
        case .boost: specification = (0.32, 180, 720, 0.12)
        case .crashLight: specification = (0.34, 120, 65, 0.22)
        case .crashMedium: specification = (0.42, 100, 45, 0.34)
        case .crashHeavy: specification = (0.52, 82, 38, 0.46)
        case .finish: specification = (0.7, 440, 1_320, 0)
        case .failure: specification = (0.65, 330, 110, 0.04)
        }

        var seed: UInt64 = 0x51F
        return makeBuffer(format: format, duration: specification.duration) { time in
            let progress = time / specification.duration
            let frequency = specification.start
                + (specification.end - specification.start) * progress
            let envelope = sin(.pi * min(progress / 0.08, 1))
                * pow(max(0, 1 - progress), 1.8)
            let random = randomSample(seed: &seed)
            return (sin(time * frequency * 2 * .pi) * 0.55
                + random * specification.noise) * envelope
        }
    }

    private static func drumSample(time: TimeInterval, beat: TimeInterval) -> Double {
        let position = time.truncatingRemainder(dividingBy: beat * 4)
        let kickPhase = position.truncatingRemainder(dividingBy: beat * 2)
        let kick = kickPhase < 0.18
            ? sin(time * (54 + 80 * exp(-kickPhase * 24)) * 2 * .pi) * exp(-kickPhase * 18) * 0.9
            : 0
        let snareOffset = abs(position - beat * 2)
        let snare = snareOffset < 0.16 ? pseudoNoise(time: time, frequency: 7_900) * exp(-snareOffset * 18) * 0.28 : 0
        let hatPhase = position.truncatingRemainder(dividingBy: beat / 2)
        let hat = pseudoNoise(time: time, frequency: 12_400) * exp(-hatPhase * 40) * 0.12
        return tanh(kick + snare + hat) * 0.32
    }

    private static func gate(time: TimeInterval, interval: TimeInterval, decay: Double) -> Double {
        let phase = time.truncatingRemainder(dividingBy: interval) / interval
        return exp(-phase * decay)
    }

    private static func pseudoNoise(time: TimeInterval, frequency: Double) -> Double {
        let value = sin(time * frequency * 12.9898) * 43_758.5453
        return (value - floor(value)) * 2 - 1
    }

    private static func randomSample(seed: inout UInt64) -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        return Double(Int64(bitPattern: seed)) / Double(Int64.max)
    }

    private static func ambienceSeed(for environment: AudioEnvironment) -> UInt64 {
        switch environment {
        case .city: 0xC17A
        case .coast: 0xC0A57
        case .desert: 0xDE5E27
        case .tunnel: 0x7A44E1
        }
    }

    private static func makeBuffer(
        format: AVAudioFormat,
        duration: TimeInterval,
        sample: (TimeInterval) -> Double
    ) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channels = buffer.floatChannelData else { return buffer }

        for frame in 0..<Int(frameCount) {
            let value = Float(sample(Double(frame) / format.sampleRate).clamped(to: -1...1))
            for channel in 0..<Int(format.channelCount) {
                channels[channel][frame] = value
            }
        }
        return buffer
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
