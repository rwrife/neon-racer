import AVFoundation
import Combine
import os

@MainActor
final class AudioService: NSObject, ObservableObject {
    enum Event {
        case interruptionBegan
        case interruptionEnded
    }

    @Published private(set) var preferences: AudioPreferences

    private let engine = AVAudioEngine()
    private let musicPlayer = AVAudioPlayerNode()
    private let enginePlayer = AVAudioPlayerNode()
    private let tirePlayer = AVAudioPlayerNode()
    private let ambiencePlayer = AVAudioPlayerNode()
    private let engineRate = AVAudioUnitVarispeed()
    private let musicEQ = AVAudioUnitEQ(numberOfBands: 1)
    private var buses: [AudioBus: AVAudioMixerNode] = [:]
    private var oneShotPlayers: [AudioBus: AVAudioPlayerNode] = [:]
    private var mixState: AudioMixState
    private var isConfigured = false
    private let defaults: UserDefaults
    private let preferencesKey = "audio.preferences.v1"
    private var eventHandler: ((Event) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedPreferences = defaults.data(forKey: preferencesKey)
            .flatMap { try? JSONDecoder().decode(AudioPreferences.self, from: $0) }
            ?? .standard
        preferences = storedPreferences
        mixState = AudioMixState(preferences: storedPreferences)
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
        if !active {
            suspend()
        }
    }

    private func updatePreferences(_ update: (inout AudioPreferences) -> Void) {
        var next = preferences
        update(&next)
        preferences = AudioPreferences(
            musicLevel: next.musicLevel,
            effectsLevel: next.effectsLevel,
            isMusicMuted: next.isMusicMuted,
            areEffectsMuted: next.areEffectsMuted
        )
        mixState.setPreferences(preferences)
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: preferencesKey)
        }
        applyMix()
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        for bus in AudioBus.allCases {
            let mixer = AVAudioMixerNode()
            buses[bus] = mixer
            engine.attach(mixer)
            engine.connect(mixer, to: engine.mainMixerNode, format: format)
        }

        engine.attach(musicPlayer)
        engine.attach(musicEQ)
        engine.connect(musicPlayer, to: musicEQ, format: format)
        engine.connect(musicEQ, to: buses[.music]!, format: format)

        engine.attach(enginePlayer)
        engine.attach(engineRate)
        engine.connect(enginePlayer, to: engineRate, format: format)
        engine.connect(engineRate, to: buses[.engine]!, format: format)

        connect(tirePlayer, to: .tires, format: format)
        connect(ambiencePlayer, to: .ambience, format: format)

        for bus in [AudioBus.impacts, .ui, .voice] {
            let player = AVAudioPlayerNode()
            oneShotPlayers[bus] = player
            connect(player, to: bus, format: format)
        }

        musicEQ.bands[0].filterType = .lowPass
        musicEQ.bands[0].frequency = 12_000
        musicEQ.bands[0].bypass = false
        engine.mainMixerNode.outputVolume = 0.82

        musicPlayer.scheduleBuffer(
            ProceduralAudio.music(format: format),
            at: nil,
            options: .loops
        )
        enginePlayer.scheduleBuffer(
            ProceduralAudio.engine(format: format),
            at: nil,
            options: .loops
        )
        tirePlayer.scheduleBuffer(
            ProceduralAudio.noise(format: format, color: .bright),
            at: nil,
            options: .loops
        )
        ambiencePlayer.scheduleBuffer(
            ProceduralAudio.noise(format: format, color: .dark),
            at: nil,
            options: .loops
        )

        isConfigured = true
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
        [musicPlayer, enginePlayer, tirePlayer, ambiencePlayer].forEach {
            if !$0.isPlaying {
                $0.play()
            }
        }
    }

    private func applyMix() {
        guard isConfigured else { return }
        let rendering = mixState.shouldRender
        let vehicle = mixState.shouldPlayVehicleAudio

        buses[.music]?.outputVolume = Float(
            rendering && mixState.shouldPlayMusic
                ? preferences.gain(for: .music) * mixState.musicSectionGain()
                : 0
        )
        buses[.engine]?.outputVolume = Float(
            vehicle ? preferences.gain(for: .engine) * mixState.engine.engineGain : 0
        )
        buses[.tires]?.outputVolume = Float(
            vehicle ? preferences.gain(for: .tires) * mixState.engine.tireGain : 0
        )
        buses[.ambience]?.outputVolume = Float(
            vehicle ? preferences.gain(for: .ambience) * mixState.engine.ambienceGain : 0
        )
        for bus in [AudioBus.impacts, .ui, .voice] {
            buses[bus]?.outputVolume = Float(
                rendering ? preferences.gain(for: bus) * busHeadroom(bus) : 0
            )
        }

        engineRate.rate = Float(mixState.engine.pitchRate)
        musicEQ.bands[0].frequency = musicCutoff(for: mixState.musicSection)
    }

    private func busHeadroom(_ bus: AudioBus) -> Double {
        switch bus {
        case .impacts: 0.9
        case .voice: 0.88
        case .ui: 0.7
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

    private func playOneShot(for event: AudioEvent) {
        let cue: (AudioBus, ProceduralAudio.Cue)?
        switch event {
        case .checkpoint: cue = (.voice, .checkpoint)
        case .pass: cue = (.ui, .pass)
        case .nearMiss: cue = (.ui, .nearMiss)
        case .combo: cue = (.ui, .combo)
        case .boost: cue = (.impacts, .boost)
        case let .crash(severity): cue = (.impacts, .crash(severity: severity))
        case .finish: cue = (.voice, .finish)
        case .failure: cue = (.voice, .failure)
        case .uiConfirm, .raceStarted, .raceRetried: cue = (.ui, .confirm)
        case .showMenu, .racePaused, .raceResumed, .raceExited, .environmentChanged:
            cue = nil
        }
        guard let (bus, sound) = cue,
              let player = oneShotPlayers[bus],
              let format = player.outputFormat(forBus: 0).standardized else {
            return
        }
        player.stop()
        player.scheduleBuffer(ProceduralAudio.cue(sound, format: format))
        player.play()
    }

    private func suspend() {
        applySilentMix()
        engine.pause()
        deactivateSession()
    }

    private func applySilentMix() {
        buses.values.forEach { $0.outputVolume = 0 }
    }

    private func resumeAfterSuspension() {
        guard !mixState.isInterrupted else { return }
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
            eventHandler?(.interruptionEnded)
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
        if reason == .oldDeviceUnavailable || reason == .newDeviceAvailable {
            resumeAfterSuspension()
        }
    }

    @objc private func handleEngineConfigurationChange() {
        resumeAfterSuspension()
    }
}

private extension Logger {
    static let audio = Logger(subsystem: "com.neonracer.app", category: "Audio")
}

private extension AVAudioFormat {
    var standardized: AVAudioFormat? {
        AVAudioFormat(
            standardFormatWithSampleRate: sampleRate > 0 ? sampleRate : 44_100,
            channels: channelCount > 0 ? channelCount : 2
        )
    }
}

private enum ProceduralAudio {
    enum NoiseColor {
        case bright
        case dark
    }

    enum Cue {
        case confirm
        case pass
        case nearMiss
        case combo
        case checkpoint
        case boost
        case crash(severity: Double)
        case finish
        case failure
    }

    static func engine(format: AVAudioFormat) -> AVAudioPCMBuffer {
        makeBuffer(format: format, duration: 1) { time in
            let phase = time * 55 * 2 * .pi
            return tanh(
                sin(phase) * 0.52
                    + sin(phase * 2) * 0.22
                    + sin(phase * 3) * 0.1
            ) * 0.45
        }
    }

    static func music(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let bpm = 108.0
        let beat = 60 / bpm
        let duration = beat * 16
        let notes = [55.0, 55.0, 65.41, 73.42, 49.0, 49.0, 65.41, 73.42]
        return makeBuffer(format: format, duration: duration) { time in
            let step = Int(time / (beat * 2)) % notes.count
            let bassFrequency = notes[step]
            let bass = sin(time * bassFrequency * 2 * .pi)
                + 0.35 * sin(time * bassFrequency * 4 * .pi)
            let pulsePhase = (time.truncatingRemainder(dividingBy: beat)) / beat
            let pulse = exp(-pulsePhase * 13) * sin(time * 110 * 2 * .pi)
            let eighth = (time.truncatingRemainder(dividingBy: beat / 2)) / (beat / 2)
            let arpeggioFrequency = bassFrequency * [2, 3, 4, 6][Int(time / (beat / 2)) % 4]
            let arpeggio = sin(time * arpeggioFrequency * 2 * .pi) * exp(-eighth * 5)
            return tanh(bass * 0.18 + pulse * 0.2 + arpeggio * 0.08)
        }
    }

    static func noise(format: AVAudioFormat, color: NoiseColor) -> AVAudioPCMBuffer {
        var seed: UInt64 = color == .bright ? 0xA11CE : 0xBADC0DE
        var previous = 0.0
        return makeBuffer(format: format, duration: 2) { _ in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let white = Double(Int64(bitPattern: seed)) / Double(Int64.max)
            switch color {
            case .bright:
                return white * 0.22
            case .dark:
                previous = previous * 0.94 + white * 0.06
                return previous * 0.3
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
        case let .crash(severity):
            specification = (0.42, 100, 45, 0.25 + min(max(severity, 0), 1) * 0.2)
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
            seed = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
            let random = Double(Int64(bitPattern: seed)) / Double(Int64.max)
            return (sin(time * frequency * 2 * .pi) * 0.55
                + random * specification.noise) * envelope
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
            let value = Float(sample(Double(frame) / format.sampleRate))
            for channel in 0..<Int(format.channelCount) {
                channels[channel][frame] = value
            }
        }
        return buffer
    }
}
