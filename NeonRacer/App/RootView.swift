import SwiftUI

struct RootView: View {
    private enum Destination {
        case menu
        case race
    }

    @State private var destination = Destination.menu
    @State private var profile = PlayerProfile.newPlayer
    @State private var isProfileLoaded = false
    @StateObject private var audio = AudioService()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject private var accessibility: AccessibilitySettingsStore
    private let profileStore = ProfileStore()

    var body: some View {
        Group {
            if isProfileLoaded {
                switch destination {
                case .menu:
                    MainMenuView(
                        profile: $profile,
                        audio: audio,
                        startRace: {
                            audio.handle(.uiConfirm)
                            setDestination(.race)
                        },
                        saveProfile: saveProfile
                    )
                case .race:
                    RaceView(
                        tutorialProgress: profile.tutorialProgress,
                        inputMethod: profile.preferredInputMethod,
                        audioService: audio,
                        updateTutorialProgress: { progress in
                            profile.tutorialProgress = progress
                            saveProfile()
                        },
                        exitRace: { setDestination(.menu) }
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
            if let loadedProfile = try? await profileStore.load() {
                profile = loadedProfile
            }
            audio.handle(.showMenu)
            isProfileLoaded = true
        }
    }

    private func saveProfile() {
        let profileToSave = profile
        Task {
            try? await profileStore.save(profileToSave)
        }
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
}

#Preview {
    RootView()
        .environmentObject(AccessibilitySettingsStore())
}
