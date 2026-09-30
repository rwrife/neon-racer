import SceneKit
import SpriteKit
import SwiftUI
import os

struct RaceView: View {
    let inputMethod: DrivingInputMethod
    let selectedVehicleID: String
    let routeID: String
    let selectedPaletteID: String
    let audioService: AudioService
    @ObservedObject var gameplaySettings: GameplaySettingsStore
    let restartRace: () -> Void
    let exitRace: () -> Void
    let completed: (RaceResult) -> RaceResultsSummary

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject private var accessibility: AccessibilitySettingsStore
    private let routeName: String
    private let raceDuration: TimeInterval
    private let runRecoveryStore = RunRecoveryStore()
    // StateObject's autoclosure runs once per view identity; State(initialValue:) would rebuild
    // the whole SceneKit scene every time the parent re-renders.
    @StateObject private var sceneHolder: RaceSceneHolder
    private var scene: RaceScene3D { sceneHolder.scene }
    @StateObject private var inputService: InputService
    @State private var lifecycle = RunInterruptionCoordinator()
    @State private var hapticsService = HapticsService()
    @State private var feedbackError: String?
    @State private var hudSnapshot = RaceHUDSnapshot.initial
    @State private var hudFeedback: RaceHUDFeedback?
    @State private var hudFeedbackID = 0
    @State private var hudFeedbackTask: Task<Void, Never>?
    @State private var lastRecoveryPersistTime: TimeInterval = -.infinity
    @State private var confirmation: Confirmation?
    @State private var endingResult: RaceResult?
    @State private var endingSummary: RaceResultsSummary?
    @FocusState private var focusedPauseAction: PauseAction?

    private enum Confirmation: String, Identifiable {
        case restart, title
        var id: String { rawValue }
    }

    private enum PauseAction: Hashable {
        case resume, restart, title
    }
#if DEBUG
    @State private var showsVehicleArtPreview = false
#endif

    init(
        inputMethod: DrivingInputMethod,
        selectedVehicleID: String,
        configuration: RaceConfiguration,
        routeID: String,
        garagePalette: GaragePaletteDefinition,
        audioService: AudioService,
        gameplaySettings: GameplaySettingsStore,
        restartRace: @escaping () -> Void,
        exitRace: @escaping () -> Void,
        completed: @escaping (RaceResult) -> RaceResultsSummary
    ) {
        self.inputMethod = inputMethod
        self.selectedVehicleID = selectedVehicleID
        self.routeID = routeID
        self.selectedPaletteID = garagePalette.id
        self.audioService = audioService
        self.gameplaySettings = gameplaySettings
        self.restartRace = restartRace
        self.exitRace = exitRace
        self.completed = completed
        let routeName = ProgressionCatalog.routes.first { $0.id == routeID }?.displayName
            ?? ProgressionCatalog.routes[0].displayName
        self.routeName = routeName
        self.raceDuration = configuration.raceDuration
        _sceneHolder = StateObject(
            wrappedValue: RaceSceneHolder(
                scene: RaceScene3D(
                    renderQualityPreference: gameplaySettings.settings.renderQualityPreference,
                    configuration: configuration,
                    routeGraph: ProgressionCatalog.routeGraph(
                        id: routeID,
                        configuration: configuration
                    ),
                    routeName: routeName,
                    garagePalette: garagePalette
                )
            )
        )
        _inputService = StateObject(
            wrappedValue: InputService(initialInputMethod: inputMethod)
        )
    }

#if DEBUG
    private static let debugHidesHUD = ProcessInfo.processInfo.arguments.contains("UITestHideHUD")
    private static let debugStartsRace = ProcessInfo.processInfo.arguments.contains("UITestStartRace")
#else
    private static let debugHidesHUD = false
    private static let debugStartsRace = false
#endif

    var body: some View {
        ZStack(alignment: .topLeading) {
            RaceScene3DView(scene: scene) { key, isPressed in
                inputService.handleKeyboardKey(key, isPressed: isPressed)
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Race in progress")
                .accessibilityValue("Use the labeled steering, brake, boost, and go controls.")
                .accessibilityHint("Use Pause race for resume, restart, and title controls")

            RaceHUDView(
                snapshot: hudSnapshot,
                feedback: hudFeedback,
                settings: accessibility.settings
            )
            .opacity(Self.debugHidesHUD ? 0 : 1)
            .zIndex(10)

            DebugPerformanceOverlay(scene: scene, settings: gameplaySettings.settings)

            Button {
                apply(lifecycle.handle(.pauseRequested))
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(accessibility.settings.highContrast ? 0.92 : 0.42), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.cyan.opacity(accessibility.settings.highContrast ? 1 : 0.78), lineWidth: accessibility.settings.highContrast ? 2 : 1.1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause race")
            .accessibilityHint("Opens pause controls")
            .padding(.top, 12)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .opacity(Self.debugHidesHUD ? 0 : 1)
            .zIndex(20_001)

#if DEBUG
            if !ProcessInfo.processInfo.arguments.contains("UITestAppStoreScreenshots") {
                HStack {
                    if ProcessInfo.processInfo.arguments.contains("UITestFinishRace") {
                        Button("COMPLETE TEST RACE") {
                            handleRaceCompleted(scene.completeForUITesting(succeeded: true))
                        }
                    }
                    if !Self.debugStartsRace {
                        Button("VEHICLE SHEET") {
                            showsVehicleArtPreview = true
                        }
                    }
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .padding()
                .padding(.top, 52)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .zIndex(20_000)
            }
#endif

            if lifecycle.state == .running
                && !Self.debugStartsRace {
                touchControls
            }

            if lifecycle.state == .pausedForRecovery {
                recoveryOverlay
            }

            if let endingResult {
                ResultsView(
                    result: endingResult,
                    previousBest: endingSummary?.previousBest ?? 0,
                    unlocks: endingSummary?.unlocks ?? [],
                    retry: restartRace,
                    returnToTitle: exitRace,
                    overlaysRaceScene: true
                )
                .background(.black.opacity(0.58))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Race results")
                .zIndex(30_000)
            }
        }
        .onAppear {
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
            scene.hudDidUpdate = handleHUDUpdate
            scene.raceDidEnd = handleRaceCompleted
            inputService.actionHandler = handleInputAction
            inputService.controllerDisconnectHandler = handleControllerDisconnected
            inputService.start()
            inputService.updateRemapping(gameplaySettings.settings.inputRemapping)
            hapticsService.configure(gameplaySettings.settings.haptics)
            configureSceneAccessibility()
            saveRunRecoverySnapshot(force: true)
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
            scene.hudDidUpdate = { _ in }
            inputService.actionHandler = { _ in }
            inputService.controllerDisconnectHandler = {}
            hudFeedbackTask?.cancel()
            audioService.endObserving()
            hapticsService.stop()
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            handleScenePhase(newPhase)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            handleMemoryWarning()
        }
        .alert("Feedback unavailable", isPresented: feedbackErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(feedbackError ?? "")
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationIsPresented,
            titleVisibility: .visible
        ) {
            if confirmation == .restart {
                Button("Restart Race", role: .destructive) {
                    audioService.handle(.raceExited)
                    restartRace()
                }
            } else {
                Button("Return to Title", role: .destructive) {
                    audioService.handle(.raceExited)
                    clearRunRecoverySnapshot()
                    exitRace()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Current run progress will be lost.")
        }
        .onChange(of: accessibility.settings) {
            configureSceneAccessibility()
        }
        .onChange(of: systemReduceMotion) {
            configureSceneAccessibility()
        }
#if DEBUG
        .sheet(isPresented: $showsVehicleArtPreview) {
            VehicleArtPreviewView()
        }
#endif
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
            .focused($focusedPauseAction, equals: .resume)
            Button("RESTART") {
                confirmation = .restart
            }
            .buttonStyle(.bordered)
            .focused($focusedPauseAction, equals: .restart)
            Button("RETURN TO TITLE") {
                confirmation = .title
            }
            .buttonStyle(.bordered)
            .focused($focusedPauseAction, equals: .title)
        }
        .padding(32)
        .frame(maxWidth: 420)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focusedPauseAction = .resume }
    }

    private var touchControls: some View {
        TouchDrivingControls(
            inputMethod: inputService.inputMethod,
            setSteering: inputService.setTouchSteering,
            setAction: inputService.setTouchAction
        )
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
#if DEBUG
        // simctl/XCUITest launches can report a spurious .inactive phase at startup.
        if Self.debugStartsRace, phase == .inactive {
            return
        }
#endif
        if phase != .active {
            saveRunRecoverySnapshot(force: true)
        }
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
        case .routeChanged:
            apply(lifecycle.handle(.audioRouteChanged))
        }
    }

    private func handleControllerDisconnected() {
        apply(lifecycle.handle(.controllerDisconnected))
    }

    private func handleMemoryWarning() {
#if DEBUG
        Logger.lifecycle.debug("Run lifecycle memory warning received")
#endif
        saveRunRecoverySnapshot(force: true)
        apply(lifecycle.handle(.memoryWarningReceived))
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
            switch focusedPauseAction ?? .resume {
            case .resume:
                apply(lifecycle.handle(.resumeRequested))
            case .restart:
                confirmation = .restart
            case .title:
                confirmation = .title
            }
        case .cancel:
            if lifecycle.state == .pausedForRecovery {
                confirmation = .title
            } else {
                apply(lifecycle.handle(.pauseRequested))
            }
        case .menuUp where lifecycle.state == .pausedForRecovery:
            movePauseFocus(-1)
        case .menuDown where lifecycle.state == .pausedForRecovery:
            movePauseFocus(1)
        default:
            break
        }
    }

    private func handleRaceCompleted(_ result: RaceResult) {
        inputService.resetDrivingState()
        audioService.stop()
        hapticsService.stop()
        clearRunRecoverySnapshot()
        endingSummary = completed(result)
        endingResult = result
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
            case .releaseRecreatableResources:
                scene.releaseRecreatableResourcesForMemoryPressure()
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

    private func configureSceneAccessibility() {
        scene.apply(
            settings: accessibility.settings,
            systemReduceMotion: systemReduceMotion
        )
    }

    private func saveRunRecoverySnapshot(force: Bool = false) {
        guard hudSnapshot.phase != .finished, hudSnapshot.phase != .failed else {
            return
        }
        let now = Date().timeIntervalSinceReferenceDate
        guard force || now - lastRecoveryPersistTime >= 5 else {
            return
        }
        lastRecoveryPersistTime = now
        let snapshot = RunRecoverySnapshot(
            routeID: routeID,
            routeName: hudSnapshot.routeName ?? routeName,
            selectedVehicleID: selectedVehicleID,
            selectedPaletteID: selectedPaletteID,
            preferredInputMethod: inputService.currentInputSource,
            elapsedTime: max(0, raceDuration - Double(hudSnapshot.timerSeconds)),
            routeProgress: hudSnapshot.routeProgressFraction,
            score: hudSnapshot.score,
            stageNumber: hudSnapshot.stageNumber
        )
        Task {
            try? await runRecoveryStore.save(snapshot)
        }
    }

    private func clearRunRecoverySnapshot() {
        Task {
            try? await runRecoveryStore.clear()
        }
    }

    private func handleHUDUpdate(_ update: RaceHUDUpdate) {
        hudSnapshot = update.snapshot
        saveRunRecoverySnapshot()
        guard let feedback = update.feedback else {
            return
        }

        hudFeedbackID += 1
        let feedbackID = hudFeedbackID
        let reduceMotion = accessibility.settings.resolvedReduceMotion(
            systemReduceMotion: systemReduceMotion
        )
        hudFeedbackTask?.cancel()
        if reduceMotion {
            hudFeedback = feedback
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                hudFeedback = feedback
            }
        }
        hudFeedbackTask = Task { @MainActor in
            let duration = feedback == .finished || feedback == .failed ? 3.0 : 1.5
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, feedbackID == hudFeedbackID else {
                return
            }
            if reduceMotion {
                hudFeedback = nil
            } else {
                withAnimation(.easeIn(duration: 0.18)) {
                    hudFeedback = nil
                }
            }
        }
    }

    private func movePauseFocus(_ offset: Int) {
        let actions: [PauseAction] = [.resume, .restart, .title]
        let current = focusedPauseAction.flatMap(actions.firstIndex) ?? 0
        focusedPauseAction = actions[(current + offset + actions.count) % actions.count]
    }

    private var confirmationTitle: String {
        confirmation == .restart ? "Restart this race?" : "Return to the title?"
    }

    private var confirmationIsPresented: Binding<Bool> {
        Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        )
    }
}

@MainActor
private final class RaceSceneHolder: ObservableObject {
    let scene: RaceScene3D
    init(scene: RaceScene3D) { self.scene = scene }
}

private struct RaceScene3DView: UIViewRepresentable {
    let scene: RaceScene3D
    let keyHandler: (KeyboardKey, Bool) -> Void

    func makeUIView(context: Context) -> KeyboardCaptureSCNView {
        let view = KeyboardCaptureSCNView(frame: .zero, options: nil)
        view.isJitteringEnabled = true
        view.keyHandler = keyHandler
        scene.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: KeyboardCaptureSCNView, context: Context) {
        uiView.keyHandler = keyHandler
        if uiView.scene !== scene.scene {
            scene.attach(to: uiView)
        }
        uiView.claimKeyboardFocusIfNeeded()
    }
}

/// Receives hardware keyboard presses through the UIKit responder chain, which works for the
/// Mac keyboard in the iOS Simulator even when GameController's GCKeyboard never connects.
final class KeyboardCaptureSCNView: SCNView {
    var keyHandler: (KeyboardKey, Bool) -> Void = { _, _ in }

    override var canBecomeFirstResponder: Bool { true }

    // UIKit consumes Escape as a system key command before `pressesBegan`, so claim it explicitly.
    private lazy var escapeCommand: UIKeyCommand = {
        let command = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapePressed))
        command.wantsPriorityOverSystemBehavior = true
        return command
    }()

    override var keyCommands: [UIKeyCommand]? { [escapeCommand] }

    @objc private func escapePressed() {
        keyHandler(.escape, true)
        keyHandler(.escape, false)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        claimKeyboardFocusIfNeeded()
    }

    func claimKeyboardFocusIfNeeded() {
        guard window != nil, !isFirstResponder else { return }
        becomeFirstResponder()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !forward(presses, isPressed: true) {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !forward(presses, isPressed: false) {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !forward(presses, isPressed: false) {
            super.pressesCancelled(presses, with: event)
        }
    }

    private func forward(_ presses: Set<UIPress>, isPressed: Bool) -> Bool {
        var handled = false
        for press in presses {
            guard let usage = press.key?.keyCode,
                  let key = KeyboardKey(hidUsage: usage),
                  key != .escape else { continue }
            keyHandler(key, isPressed)
            handled = true
        }
        return handled
    }
}

extension KeyboardKey {
    init?(hidUsage: UIKeyboardHIDUsage) {
        switch hidUsage {
        case .keyboardLeftArrow: self = .leftArrow
        case .keyboardRightArrow: self = .rightArrow
        case .keyboardUpArrow: self = .upArrow
        case .keyboardDownArrow: self = .downArrow
        case .keyboardSpacebar: self = .space
        case .keyboardEscape: self = .escape
        case .keyboardReturnOrEnter, .keypadEnter: self = .returnKey
        case .keyboardA: self = .a
        case .keyboardD: self = .d
        case .keyboardW: self = .w
        case .keyboardS: self = .s
        case .keyboardP: self = .p
        default: return nil
        }
    }
}

#if DEBUG
private struct VehicleArtPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scene = VehicleArtPreviewScene(size: CGSize(width: 1920, height: 1080))

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SpriteView(scene: scene)
                .ignoresSafeArea()
            Button("DONE") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .onAppear {
            scene.scaleMode = .aspectFit
        }
    }
}
#endif

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

private extension Logger {
    static let lifecycle = Logger(subsystem: "com.neonracer.app", category: "Lifecycle")
}

#Preview {
    RaceView(
        inputMethod: .touch,
        selectedVehicleID: "prototype-zero",
        configuration: .standard,
        routeID: "neon-loop",
        garagePalette: ProgressionCatalog.palettes[0],
        audioService: AudioService(),
        gameplaySettings: GameplaySettingsStore(),
        restartRace: {},
        exitRace: {},
        completed: { _ in RaceResultsSummary(previousBest: 0, unlocks: []) }
    )
    .environmentObject(AccessibilitySettingsStore())
}
