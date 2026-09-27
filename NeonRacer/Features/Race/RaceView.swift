import SpriteKit
import SwiftUI
import os

struct RaceView: View {
    let inputMethod: DrivingInputMethod
    let audioService: AudioService
    let updateTutorialProgress: (TutorialProgress) -> Void
    let exitRace: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject private var accessibility: AccessibilitySettingsStore
    @State private var scene = RaceScene()
    @StateObject private var inputService: InputService
    @State private var tutorialSession: TutorialSession
    @State private var lifecycle = RunInterruptionCoordinator()
    @State private var hapticsService = HapticsService()
    @State private var feedbackError: String?

    init(
        tutorialProgress: TutorialProgress,
        inputMethod: DrivingInputMethod,
        audioService: AudioService,
        updateTutorialProgress: @escaping (TutorialProgress) -> Void,
        exitRace: @escaping () -> Void
    ) {
        self.inputMethod = inputMethod
        self.audioService = audioService
        self.updateTutorialProgress = updateTutorialProgress
        self.exitRace = exitRace
        _tutorialSession = State(initialValue: TutorialSession(progress: tutorialProgress))
        _inputService = StateObject(
            wrappedValue: InputService(initialInputMethod: inputMethod)
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Race in progress")
                .accessibilityValue("Use the labeled steering, brake, boost, and go controls.")
                .accessibilityHint("Use Exit race to return to the main menu")

            Button {
                audioService.handle(.raceExited)
                exitRace()
            } label: {
                Label("Exit race", systemImage: "xmark")
                    .font(.headline.bold())
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(accessibility.settings.highContrast ? 0.95 : 0.65))
            .padding()
            .accessibilityHint("Returns to the main menu")

            inputSourcePrompt

#if targetEnvironment(simulator)
            simulatorKeyboardLegend
#endif

            if lifecycle.state == .running {
                touchControls
            }

            if lifecycle.state == .pausedForRecovery {
                recoveryOverlay
            }

            if let step = tutorialSession.currentStep,
               lifecycle.state != .pausedForRecovery {
                TutorialPromptView(
                    step: step,
                    inputMethod: inputService.inputMethod,
                    advance: advanceTutorial,
                    skip: skipTutorial
                )
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .onAppear {
            scene.scaleMode = .aspectFill
            scene.audioFrameHandler = { input, deltaTime in
                audioService.updateEngine(input, deltaTime: deltaTime)
            }
            scene.audioEventHandler = audioService.handle
            let input = inputService
            let haptics = hapticsService
            scene.commandProvider = { [weak input] in
                input?.currentCommand ?? .idle
            }
            scene.engineIntensityDidChange = { [weak haptics] intensity in
                haptics?.updateEngine(intensity: intensity)
            }
            scene.feedbackDidOccur = { [weak haptics] event in
                haptics?.play(event)
            }
            inputService.actionHandler = handleInputAction
            inputService.start()
            let gameplaySettings = GameplaySettingsStore().settings
            inputService.updateRemapping(gameplaySettings.inputRemapping)
            hapticsService.configure(gameplaySettings.haptics)
            configureSceneAccessibility()
            tutorialSession.startIfNeeded()
            updateTutorialProgress(tutorialSession.progress)
            audioService.beginObserving(handleAudioEvent)
            audioService.setApplicationActive(scenePhase == .active)
            audioService.handle(.raceStarted)
            if scenePhase == .active, lifecycle.state == .running {
                startFeedback()
            }
        }
        .onDisappear {
            inputService.stop()
            scene.tearDown()
            scene.audioFrameHandler = nil
            scene.audioEventHandler = nil
            audioService.endObserving()
            audioService.stop()
            audioService.handle(.showMenu)
            hapticsService.stop()
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            handleScenePhase(newPhase)
        }
        .alert("Feedback unavailable", isPresented: feedbackErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(feedbackError ?? "")
        }
        .onChange(of: accessibility.settings) {
            configureSceneAccessibility()
        }
        .onChange(of: systemReduceMotion) {
            configureSceneAccessibility()
        }
    }

    private var recoveryOverlay: some View {
        VStack(spacing: 18) {
            Text("RACE PAUSED")
                .font(.largeTitle.bold())
            Text(feedbackError ?? "Gameplay was paused while the race was interrupted.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("RESUME") {
                apply(lifecycle.handle(.resumeRequested))
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Resumes the paused race")
        }
        .padding(32)
        .frame(maxWidth: 420)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inputSourcePrompt: some View {
        Label(
            inputService.inputMethod.displayName.uppercased(),
            systemImage: inputService.inputMethod.promptSystemImage
        )
        .font(.caption.bold().monospaced())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.65), in: Capsule())
        .padding(.top, 78)
        .padding(.leading)
        .accessibilityLabel("Current input: \(inputService.inputMethod.displayName)")
    }

#if targetEnvironment(simulator)
    private var simulatorKeyboardLegend: some View {
        Text("A/D or \u{2190}/\u{2192} STEER   W or \u{2191} GO   S or \u{2193} BRAKE   SPACE BOOST   ESC PAUSE")
            .font(.caption2.bold().monospaced())
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.72), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 18)
            .allowsHitTesting(false)
            .accessibilityLabel(
                "Keyboard controls: A and D or left and right arrows steer. "
                    + "W or up arrow accelerates. S or down arrow brakes. "
                    + "Space boosts. Escape pauses."
            )
    }
#endif

    private var touchControls: some View {
        HStack(alignment: .bottom) {
            steeringPad
            Spacer()
            HStack(alignment: .bottom, spacing: 14) {
                HoldButton(title: "BRAKE", systemImage: "stop.fill") { pressed in
                    inputService.setTouchAction(.brake, isPressed: pressed)
                }
                HoldButton(title: "BOOST", systemImage: "bolt.fill") { pressed in
                    inputService.setTouchAction(.boost, isPressed: pressed)
                }
                HoldButton(title: "GO", systemImage: "arrow.up") { pressed in
                    inputService.setTouchAction(.throttle, isPressed: pressed)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(inputService.inputMethod == .controller ? 0.35 : 1)
    }

    private var steeringPad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(.black.opacity(0.55))
            Image(systemName: "arrow.left.and.right")
                .font(.largeTitle.bold())
        }
        .frame(width: 190, height: 92)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    inputService.setTouchSteering((value.location.x / 95) - 1)
                }
                .onEnded { _ in inputService.setTouchSteering(0) }
        )
        .accessibilityLabel("Steering")
        .accessibilityHint("Drag left or right to steer")
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        audioService.setApplicationActive(phase == .active)
        switch phase {
        case .active:
            apply(lifecycle.handle(.sceneBecameActive))
        case .inactive:
            apply(lifecycle.handle(.sceneBecameInactive))
        case .background:
            apply(lifecycle.handle(.sceneEnteredBackground))
        @unknown default:
            apply(lifecycle.handle(.sceneBecameInactive))
        }
    }

    private func handleAudioEvent(_ event: AudioService.Event) {
        switch event {
        case .interruptionBegan:
            apply(lifecycle.handle(.audioInterruptionBegan))
        case .interruptionEnded:
            apply(lifecycle.handle(.audioInterruptionEnded))
        }
    }

    private func handleInputAction(_ action: PlayerAction) {
        switch action {
        case .pause:
            if lifecycle.state == .running {
                apply(lifecycle.handle(.pauseRequested))
            } else if lifecycle.state == .pausedForRecovery {
                apply(lifecycle.handle(.resumeRequested))
            }
        case .confirm where lifecycle.state == .pausedForRecovery:
            apply(lifecycle.handle(.resumeRequested))
        case .cancel:
            if lifecycle.state == .pausedForRecovery {
                audioService.handle(.raceExited)
                exitRace()
            } else {
                apply(lifecycle.handle(.pauseRequested))
            }
        default:
            break
        }
    }

    private func apply(_ actions: [RunLifecycleAction]) {
#if DEBUG
        if !actions.isEmpty {
            Logger.lifecycle.debug(
                "Run lifecycle state: \(String(describing: lifecycle.state), privacy: .public); actions: \(String(describing: actions), privacy: .public)"
            )
        }
#endif
        for action in actions {
            switch action {
            case .pauseGameplay:
                inputService.resetDrivingState()
                scene.pauseForInterruption()
                audioService.handle(.racePaused)
            case .stopFeedback:
                audioService.stop()
                hapticsService.suspend()
            case .startFeedback:
                startFeedback()
            case .resumeGameplay:
                scene.resumeAfterInterruption()
                audioService.handle(.raceResumed)
            }
        }
    }

    private func startFeedback() {
        do {
            try audioService.start()
            try hapticsService.prepare()
            feedbackError = nil
        } catch {
            feedbackError = "Feedback could not be restored: \(error.localizedDescription)"
        }
    }

    private var feedbackErrorIsPresented: Binding<Bool> {
        Binding(
            get: { feedbackError != nil && lifecycle.state == .running },
            set: { isPresented in
                if !isPresented {
                    feedbackError = nil
                }
            }
        )
    }

    private func advanceTutorial() {
        withAnimation {
            tutorialSession.advance()
        }
        updateTutorialProgress(tutorialSession.progress)
    }

    private func skipTutorial() {
        withAnimation {
            tutorialSession.skip()
        }
        updateTutorialProgress(tutorialSession.progress)
    }

    private func configureSceneAccessibility() {
        scene.apply(
            settings: accessibility.settings,
            systemReduceMotion: systemReduceMotion
        )
    }
}

private struct HoldButton: View {
    let title: String
    let systemImage: String
    let changed: (Bool) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2.bold())
            Text(title)
                .font(.caption2.bold().monospaced())
        }
        .frame(width: 82, height: 82)
        .background(.black.opacity(0.55), in: Circle())
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in changed(true) }
                .onEnded { _ in changed(false) }
        )
        .accessibilityLabel(title)
    }
}

private extension DrivingInputMethod {
    var promptSystemImage: String {
        switch self {
        case .touch: "hand.tap"
        case .controller: "gamecontroller"
        case .keyboard: "keyboard"
        }
    }
}

private extension Logger {
    static let lifecycle = Logger(subsystem: "com.neonracer.app", category: "Lifecycle")
}

#Preview {
    RaceView(
        tutorialProgress: .notStarted,
        inputMethod: .touch,
        audioService: AudioService(),
        updateTutorialProgress: { _ in },
        exitRace: {}
    )
    .environmentObject(AccessibilitySettingsStore())
}
