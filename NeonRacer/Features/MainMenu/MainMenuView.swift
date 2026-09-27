import SwiftUI

struct MainMenuView: View {
    @Binding var profile: PlayerProfile
    @ObservedObject var audio: AudioService
    let startRace: () -> Void
    let saveProfile: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject private var accessibility: AccessibilitySettingsStore
    @State private var isShowingDrivingGuide = false
    @State private var isShowingAccessibility = false

    var body: some View {
        let palette = NeonPalette.colors(for: accessibility.settings)

        ZStack {
            LinearGradient(
                colors: [
                    palette.background.color,
                    palette.panel.color,
                    palette.background.color
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 24)

                Text("NEON RACER")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .foregroundStyle(palette.primary.color)
                    .shadow(
                        color: palette.primary.color.opacity(accessibility.settings.reduceFlashes ? 0.25 : 0.8),
                        radius: accessibility.settings.reduceFlashes ? 4 : 18
                    )
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("CHASE THE HORIZON")
                    .font(.headline.monospaced())
                    .foregroundStyle(palette.secondary.color)
                    .multilineTextAlignment(.center)

                Button(action: startRace) {
                    Label("START ENGINE", systemImage: "flag.checkered")
                        .font(.title3.bold().monospaced())
                        .padding(.horizontal, 36)
                        .padding(.vertical, 16)
                        .frame(minWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.secondary.color)
                .accessibilityHint("Starts a new race")

                Button {
                    isShowingDrivingGuide = true
                } label: {
                    Label("DRIVING GUIDE", systemImage: "book.pages")
                        .font(.subheadline.bold().monospaced())
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opens controls, tutorial replay, and reset options")

                Button {
                    isShowingAccessibility = true
                } label: {
                    Label("ACCESSIBILITY", systemImage: "accessibility")
                        .font(.subheadline.bold().monospaced())
                }
                .buttonStyle(.bordered)
                .tint(palette.primary.color)
                .accessibilityHint("Opens readability, color, motion, and flash options")

                VStack(spacing: 10) {
                    audioControl(
                        title: "MUSIC",
                        level: Binding(
                            get: { audio.preferences.musicLevel },
                            set: audio.setMusicLevel
                        ),
                        muted: audio.preferences.isMusicMuted,
                        toggleMute: {
                            audio.setMusicMuted(!audio.preferences.isMusicMuted)
                        }
                    )
                    audioControl(
                        title: "EFFECTS",
                        level: Binding(
                            get: { audio.preferences.effectsLevel },
                            set: audio.setEffectsLevel
                        ),
                        muted: audio.preferences.areEffectsMuted,
                        toggleMute: {
                            audio.setEffectsMuted(!audio.preferences.areEffectsMuted)
                        }
                    )
                }
                .frame(maxWidth: 420)

                    Spacer(minLength: 24)

                    Text("Native Swift • iOS 26+")
                        .font(.caption.monospaced())
                        .foregroundStyle(palette.text.color.opacity(accessibility.settings.highContrast ? 1 : 0.7))
                }
                .padding(40)
                .frame(maxWidth: .infinity, minHeight: 700)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .sheet(isPresented: $isShowingDrivingGuide) {
            TutorialReferenceView(
                inputMethod: Binding(
                    get: { profile.preferredInputMethod },
                    set: {
                        profile.preferredInputMethod = $0
                        saveProfile()
                    }
                ),
                replay: {
                    var session = TutorialSession(progress: profile.tutorialProgress)
                    session.replay()
                    profile.tutorialProgress = session.progress
                    saveProfile()
                    isShowingDrivingGuide = false
                },
                reset: {
                    profile.tutorialProgress = .notStarted
                    saveProfile()
                }
            )
        }
        .sheet(isPresented: $isShowingAccessibility) {
            AccessibilitySettingsView()
        }
        .animation(
            accessibility.settings.resolvedReduceMotion(systemReduceMotion: systemReduceMotion)
                ? nil
                : .easeInOut(duration: 0.25),
            value: accessibility.settings
        )
    }

    private func audioControl(
        title: String,
        level: Binding<Double>,
        muted: Bool,
        toggleMute: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.caption.bold().monospaced())
                .frame(width: 72, alignment: .leading)
            Slider(value: level, in: 0...1)
                .accessibilityLabel("\(title) volume")
            Button(action: toggleMute) {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(muted ? "Unmute \(title)" : "Mute \(title)")
        }
        .foregroundStyle(.white.opacity(0.9))
    }
}

#Preview {
    MainMenuView(
        profile: .constant(.newPlayer),
        audio: AudioService(),
        startRace: {},
        saveProfile: {}
    )
        .environmentObject(AccessibilitySettingsStore())
}
