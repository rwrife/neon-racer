import SwiftUI

struct RootView: View {
    private enum Destination: Equatable {
        case menu
        case race(UUID)
        case results(RaceResult, previousBest: Int, unlocks: [String])
    }

    @State private var destination = Destination.menu
    @State private var profile = PlayerProfile.newPlayer
    @State private var isProfileLoaded = false
    @State private var profileRecovery: ProfileRecovery?
    @State private var profileRecoveryError: String?
    @State private var profileSaveError: String?
    @State private var profileSaveTask: Task<Void, Never>?
    @StateObject private var audio = AudioService()
    @StateObject private var gameplaySettings = GameplaySettingsStore()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject private var accessibility: AccessibilitySettingsStore
    private let profileStore = ProfileStore()

    var body: some View {
        Group {
            if let profileRecovery {
                profileRecoveryView(profileRecovery)
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
                        tutorialProgress: profile.tutorialProgress,
                        inputMethod: profile.preferredInputMethod,
                        configuration: ProgressionCatalog.vehicle(
                            id: profile.selectedVehicleID
                        ).configuration,
                        routeID: profile.selectedRouteID,
                        garagePalette: ProgressionCatalog.palette(
                            id: profile.selectedPaletteID
                        ),
                        audioService: audio,
                        gameplaySettings: gameplaySettings,
                        updateTutorialProgress: { progress in
                            profile.tutorialProgress = progress
                            saveProfile()
                        },
                        restartRace: startRace,
                        exitRace: { returnToMenu() },
                        completed: showResults
                    )
                    .id(runID)
                case .results(let result, let previousBest, let unlocks):
                    ResultsView(
                        result: result,
                        previousBest: previousBest,
                        unlocks: unlocks,
                        retry: startRace,
                        returnToTitle: returnToMenu
                    )
                }
            } else {
                ProgressView("Loading profile")
                    .accessibilityLabel("Loading player profile")
            }
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .task {
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

    private func showResults(_ result: RaceResult) {
        print("UITEST: showResults \(result.outcome)")
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
        let resultDestination = Destination.results(
            result,
            previousBest: previousBest,
            unlocks: Array(currentUnlocks.subtracting(previousUnlocks)).sorted()
        )
        setDestination(resultDestination)
        print("UITEST: destination set to results")
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
}

#Preview {
    RootView()
        .environmentObject(AccessibilitySettingsStore())
}
