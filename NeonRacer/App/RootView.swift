import SwiftUI

struct RootView: View {
    private enum Destination: Equatable {
        case menu
        case race(UUID)
    }

    @State private var destination = Destination.menu
    @State private var profile = PlayerProfile.newPlayer
    @State private var isProfileLoaded = false
    @State private var profileRecovery: ProfileRecovery?
    @State private var runRecovery: RunRecoverySnapshot?
    @State private var profileRecoveryError: String?
    @State private var profileSaveError: String?
    @State private var profileSaveTask: Task<Void, Never>?
    @StateObject private var audio = AudioService()
    @StateObject private var gameplaySettings = GameplaySettingsStore()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject private var accessibility: AccessibilitySettingsStore
    private let profileStore = ProfileStore()
    private let runRecoveryStore = RunRecoveryStore()

    init() {
#if DEBUG
        if Self.shouldAutostartRace {
            _destination = State(initialValue: .race(UUID()))
            _profile = State(initialValue: .newPlayer)
            _isProfileLoaded = State(initialValue: true)
        }
#endif
    }

    var body: some View {
        Group {
            if let profileRecovery {
                profileRecoveryView(profileRecovery)
            } else if let runRecovery, isProfileLoaded, destination == .menu {
                runRecoveryView(runRecovery)
            } else if isProfileLoaded {
                switch destination {
                case .menu:
                    MainMenuView(
                        profile: $profile,
                        audio: audio,
                        gameplaySettings: gameplaySettings,
                        startRace: {
                            audio.handle(.uiConfirm)
                            startRace()
                        },
                        saveProfile: { _ = saveProfile() },
                        resetProfile: resetProfile
                    )
                case .race(let runID):
                    RaceView(
                        inputMethod: profile.preferredInputMethod,
                        selectedVehicleID: profile.selectedVehicleID,
                        configuration: ProgressionCatalog.vehicle(
                            id: profile.selectedVehicleID
                        ).configuration,
                        routeID: profile.selectedRouteID,
                        garagePalette: ProgressionCatalog.palette(
                            id: profile.selectedPaletteID
                        ),
                        audioService: audio,
                        gameplaySettings: gameplaySettings,
                        restartRace: startRace,
                        exitRace: { returnToMenu() },
                        completed: showResults
                    )
                    .id(runID)
                }
            } else {
                ProgressView("Loading profile")
                    .accessibilityLabel("Loading player profile")
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
#if DEBUG
            if Self.shouldAutostartRace {
                audio.handle(.showMenu)
                return
            }
#endif
            switch await profileStore.load() {
            case .newProfile(let newProfile):
                profile = newProfile
                isProfileLoaded = true
            case .loaded(let loadedProfile, _):
                profile = loadedProfile
                isProfileLoaded = true
            case .recoveryRequired(let recovery):
                profileRecovery = recovery
            }
#if DEBUG
            if !ProcessInfo.processInfo.arguments.contains("UITestDisableRunRecovery") {
                runRecovery = try? await runRecoveryStore.load()
            }
#else
            runRecovery = try? await runRecoveryStore.load()
#endif
            audio.handle(.showMenu)
        }
        .alert("Profile Not Saved", isPresented: profileSaveErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(profileSaveError ?? "")
        }
    }

    @discardableResult
    private func saveProfile() -> Task<Void, Never> {
        let profileToSave = profile
        let previousSave = profileSaveTask
        let task = Task {
            await previousSave?.value
            do {
                try await profileStore.save(profileToSave)
            } catch {
                profileSaveError = error.localizedDescription
            }
        }
        profileSaveTask = task
        return task
    }

    private func resetProfile() {
        profile = .newPlayer
        discardRecoveredRun()
        gameplaySettings.reset()
        saveProfile()
    }

    private func startRace() {
        setDestination(.race(UUID()))
    }

    private func returnToMenu() {
        audio.handle(.showMenu)
        setDestination(.menu)
    }

    @discardableResult
    private func showResults(_ result: RaceResult) -> RaceResultsSummary {
        audio.handle(.showMenu)
        let previousBest = profile.bestScore
        let previousUnlocks = profile.unlockedVehicleIDs
            .union(profile.unlockedPaletteIDs)
            .union(profile.unlockedRouteIDs)
        profile.record(result, routeID: profile.selectedRouteID)
        saveProfile()
        let currentUnlocks = profile.unlockedVehicleIDs
            .union(profile.unlockedPaletteIDs)
            .union(profile.unlockedRouteIDs)
        let newUnlocks = Array(currentUnlocks.subtracting(previousUnlocks)).sorted()
        return RaceResultsSummary(previousBest: previousBest, unlocks: newUnlocks)
    }

    private var profileSaveErrorIsPresented: Binding<Bool> {
        Binding(
            get: { profileSaveError != nil },
            set: { isPresented in
                if !isPresented {
                    profileSaveError = nil
                }
            }
        )
    }

    private func setDestination(_ newDestination: Destination) {
        if accessibility.settings.resolvedReduceMotion(systemReduceMotion: systemReduceMotion) {
            destination = newDestination
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                destination = newDestination
            }
        }
    }

    private func resumeRecoveredRun(_ snapshot: RunRecoverySnapshot) {
        if ProgressionCatalog.vehicles.contains(where: { $0.id == snapshot.selectedVehicleID }) {
            profile.unlockedVehicleIDs.insert(snapshot.selectedVehicleID)
            profile.selectedVehicleID = snapshot.selectedVehicleID
        }
        if ProgressionCatalog.palettes.contains(where: { $0.id == snapshot.selectedPaletteID }) {
            profile.unlockedPaletteIDs.insert(snapshot.selectedPaletteID)
            profile.selectedPaletteID = snapshot.selectedPaletteID
        }
        if ProgressionCatalog.routes.contains(where: { $0.id == snapshot.routeID }) {
            profile.unlockedRouteIDs.insert(snapshot.routeID)
            profile.selectedRouteID = snapshot.routeID
        }
        profile.preferredInputMethod = snapshot.preferredInputMethod
        saveProfile()
        runRecovery = nil
        audio.handle(.uiConfirm)
        startRace()
    }

    private func discardRecoveredRun() {
        clearRecoveredRunState()
        audio.handle(.uiConfirm)
    }

    private func clearRecoveredRunState() {
        runRecovery = nil
        Task {
            try? await runRecoveryStore.clear()
        }
    }

#if DEBUG
    private static var shouldAutostartRace: Bool {
        ProcessInfo.processInfo.arguments.contains("UITestStartRace")
            || ProcessInfo.processInfo.environment["NEON_RACER_AUTOSTART_RACE"] == "1"
    }
#endif

    private func profileRecoveryView(_ recovery: ProfileRecovery) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("PROFILE RECOVERY")
                .font(.title.bold().monospaced())
            Text(recovery.message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let profileRecoveryError {
                Text(profileRecoveryError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("RESET LOCAL PROFILE", role: .destructive) {
                Task {
                    do {
                        profile = try await profileStore.resetPreservingCorruptSave()
                        profileRecovery = nil
                        profileRecoveryError = nil
                        isProfileLoaded = true
                    } catch {
                        profileRecoveryError = error.localizedDescription
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Preserves the damaged file and creates a new profile")
        }
        .padding(36)
        .frame(maxWidth: 520)
    }

    private func runRecoveryView(_ snapshot: RunRecoverySnapshot) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "flag.checkered.2.crossed")
                .font(.system(size: 48))
                .foregroundStyle(.cyan)
            Text("RUN RECOVERY")
                .font(.title.bold().monospaced())
            Text("A race was interrupted before it could finish. Resume the route from a safe checkpoint or discard the interrupted run.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text(recoverySummary(snapshot))
                .font(.caption.bold().monospaced())
                .foregroundStyle(.secondary)
            Button("RESUME ROUTE") {
                resumeRecoveredRun(snapshot)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Restarts the interrupted route with the recovered race setup")
            Button("DISCARD RUN", role: .destructive) {
                discardRecoveredRun()
            }
            .buttonStyle(.bordered)
        }
        .padding(36)
        .frame(maxWidth: 560)
    }

    private func recoverySummary(_ snapshot: RunRecoverySnapshot) -> String {
        let route = snapshot.routeName ?? snapshot.routeID
        let progress = Int((snapshot.routeProgress * 100).rounded())
        return "\(route.uppercased()) · STAGE \(snapshot.stageNumber) · \(progress)% · SCORE \(snapshot.score)"
    }
}

#Preview {
    RootView()
        .environmentObject(AccessibilitySettingsStore())
}
