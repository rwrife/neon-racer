import SwiftUI

struct SettingsView: View {
    @ObservedObject var audio: AudioService
    @ObservedObject var gameplaySettings: GameplaySettingsStore
    let resetProfile: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingResetConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Audio") {
                    audioSlider(
                        "Music",
                        value: Binding(
                            get: { audio.preferences.musicLevel },
                            set: audio.setMusicLevel
                        )
                    )
                    Toggle(
                        "Mute Music",
                        isOn: Binding(
                            get: { audio.preferences.isMusicMuted },
                            set: audio.setMusicMuted
                        )
                    )
                    audioSlider(
                        "Effects",
                        value: Binding(
                            get: { audio.preferences.effectsLevel },
                            set: audio.setEffectsLevel
                        )
                    )
                    Toggle(
                        "Mute Effects",
                        isOn: Binding(
                            get: { audio.preferences.areEffectsMuted },
                            set: audio.setEffectsMuted
                        )
                    )
                }

                Section("Feedback") {
                    Toggle(
                        "Haptics",
                        isOn: gameplayBinding(\.haptics.isEnabled)
                    )
                    Slider(
                        value: gameplayBinding(\.haptics.intensity),
                        in: 0...1
                    ) {
                        Text("Haptic Intensity")
                    }
                    .disabled(!gameplaySettings.settings.haptics.isEnabled)
                }

                Section {
                    NavigationLink("Accessibility") {
                        AccessibilitySettingsView(showsDoneButton: false)
                    }
                }

                Section {
                    Button("Reset Player Data", role: .destructive) {
                        isShowingResetConfirmation = true
                    }
                } footer: {
                    Text("Settings are saved immediately. Race input and haptic changes apply at the start of the next run.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset Player Data", role: .destructive) {
                        isShowingResetConfirmation = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Reset all player data?", isPresented: $isShowingResetConfirmation) {
                Button("Reset Player Data", role: .destructive) {
                    resetProfile()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the best score, tutorial progress, controls, and haptic settings. Audio and accessibility preferences are preserved.")
            }
        }
    }

    private func audioSlider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: 0...1)
                .accessibilityLabel("\(title) volume")
        }
    }

    private func gameplayBinding<Value>(
        _ keyPath: WritableKeyPath<GameplaySettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { gameplaySettings.settings[keyPath: keyPath] },
            set: { value in
                gameplaySettings.update { $0[keyPath: keyPath] = value }
            }
        )
    }
}

struct AccessibilitySettingsView: View {
    var showsDoneButton = true
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accessibility: AccessibilitySettingsStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Comfort") {
                    Toggle("Reduce Motion", isOn: binding(\.reduceMotion))
                        .accessibilityHint("Stops road movement, vehicle tilt, and pulsing effects")
                    Toggle("Reduce Flashes", isOn: binding(\.reduceFlashes))
                        .accessibilityHint("Removes rapid glow and brightness changes")
                }

                Section("Readability") {
                    Toggle("High Contrast", isOn: binding(\.highContrast))
                    Toggle("Large Race Display", isOn: binding(\.largeHUD))

                    Picker("Color Palette", selection: binding(\.palette)) {
                        ForEach(AccessibilityPalette.allCases) { palette in
                            Text(palette.displayName).tag(palette)
                        }
                    }
                }

                Section {
                    Text("Race information uses text and shapes as well as color. VoiceOver can describe the current race screen, but real-time steering is not designed for VoiceOver.")
                        .font(.footnote)
                } header: {
                    Text("Gameplay accessibility")
                }
            }
            .navigationTitle("Accessibility")
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AccessibilitySettings, Value>) -> Binding<Value> {
        Binding(
            get: { accessibility.settings[keyPath: keyPath] },
            set: { accessibility.settings[keyPath: keyPath] = $0 }
        )
    }
}

#Preview {
    AccessibilitySettingsView()
        .environmentObject(AccessibilitySettingsStore())
}
