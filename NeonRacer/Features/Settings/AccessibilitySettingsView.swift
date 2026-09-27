import SwiftUI

struct SettingsView: View {
    @ObservedObject var audio: AudioService
    @ObservedObject var gameplaySettings: GameplaySettingsStore
    @ObservedObject var inputService: InputService
    let resetProfile: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingResetConfirmation = false
    @State private var isShowingAccessibility = false
    @FocusState private var focusedControl: SettingsControl?

    private enum SettingsControl: Hashable {
        case haptics
        case hapticIntensity
        case renderQuality
        case perfOverlay
        case remap(PlayerAction)
        case resetInput
        case accessibility
        case resetProfile
        case done
    }

    private static let remappableActions: [PlayerAction] = [
        .steerLeft,
        .steerRight,
        .throttle,
        .brake,
        .boost,
        .pause,
        .confirm,
        .cancel,
        .menuUp,
        .menuDown,
        .menuLeft,
        .menuRight
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MenuInputPrompt(inputMethod: inputService.currentInputSource)
                }

                Section("Audio") {
                    audioSlider(
                        "Music",
                        value: Binding(
                            get: { audio.preferences.musicLevel },
                            set: { audio.setMusicLevel($0) }
                        )
                    )
                    Toggle(
                        "Mute Music",
                        isOn: Binding(
                            get: { audio.preferences.isMusicMuted },
                            set: { audio.setMusicMuted($0) }
                        )
                    )
                    audioSlider(
                        "Effects",
                        value: Binding(
                            get: { audio.preferences.effectsLevel },
                            set: { audio.setEffectsLevel($0) }
                        )
                    )
                    Toggle(
                        "Mute Effects",
                        isOn: Binding(
                            get: { audio.preferences.areEffectsMuted },
                            set: { audio.setEffectsMuted($0) }
                        )
                    )
                }

                Section("Feedback") {
                    Toggle(
                        "Haptics",
                        isOn: gameplayBinding(\.haptics.isEnabled)
                    )
                    .focused($focusedControl, equals: .haptics)
                    Slider(
                        value: gameplayBinding(\.haptics.intensity),
                        in: 0...1
                    ) {
                        Text("Haptic Intensity")
                    }
                    .disabled(!gameplaySettings.settings.haptics.isEnabled)
                    .focused($focusedControl, equals: .hapticIntensity)
                }

                Section {
                    Picker("Render Quality", selection: gameplayBinding(\.renderQualityPreference)) {
                        ForEach(RenderQualityPreference.allCases) { preference in
                            Text(preference.displayName).tag(preference)
                        }
                    }
                    .focused($focusedControl, equals: .renderQuality)
#if DEBUG
                    Toggle(
                        "Performance Overlay",
                        isOn: gameplayBinding(\.debugPerformanceOverlayEnabled)
                    )
                    .focused($focusedControl, equals: .perfOverlay)
#endif
                } header: {
                    Text("Graphics")
                } footer: {
                    Text("Automatic quality considers device memory and thermal pressure. Changes apply at the start of the next run.")
                }

                Section("Input Remapping") {
                    ForEach(Self.remappableActions, id: \.self) { action in
                        Picker(action.settingsTitle, selection: remappingBinding(for: action)) {
                            ForEach(KeyboardKey.allCases, id: \.self) { key in
                                Text(key.settingsTitle).tag(key)
                            }
                        }
                        .focused($focusedControl, equals: .remap(action))
                    }

                    Button("Reset Input Mapping") {
                        gameplaySettings.update { $0.inputRemapping = .standard }
                        inputService.updateRemapping(.standard)
                    }
                    .focused($focusedControl, equals: .resetInput)
                }

                Section {
                    NavigationLink("Accessibility") {
                        AccessibilitySettingsView(showsDoneButton: false)
                    }
                    .focused($focusedControl, equals: .accessibility)
                }

                Section {
                    Button("Reset Player Data", role: .destructive) {
                        isShowingResetConfirmation = true
                    }
                    .focused($focusedControl, equals: .resetProfile)
                } footer: {
                    Text("Settings are saved immediately. Race input, haptic, and graphics changes apply at the start of the next run.")
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
                        .focused($focusedControl, equals: .done)
                }
            }
            .navigationDestination(isPresented: $isShowingAccessibility) {
                AccessibilitySettingsView(showsDoneButton: false)
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
        .onAppear {
            focusedControl = .haptics
            inputService.actionHandler = handleInputAction
        }
        .onChange(of: gameplaySettings.settings.inputRemapping) { _, newValue in
            inputService.updateRemapping(newValue)
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

    private func remappingBinding(for action: PlayerAction) -> Binding<KeyboardKey> {
        Binding(
            get: {
                gameplaySettings.settings.inputRemapping.keyboard[action]
                    ?? InputRemapping.standard.keyboard[action]
                    ?? .returnKey
            },
            set: { key in
                gameplaySettings.update { $0.inputRemapping.keyboard[action] = key }
            }
        )
    }

    private var focusOrder: [SettingsControl] {
        [.haptics, .hapticIntensity, .renderQuality, .perfOverlay]
            + Self.remappableActions.map(SettingsControl.remap)
            + [.resetInput, .accessibility, .resetProfile, .done]
    }

    private func handleInputAction(_ action: PlayerAction) {
        switch action {
        case .menuUp:
            moveFocus(-1)
        case .menuDown:
            moveFocus(1)
        case .menuLeft:
            adjustFocusedControl(-1)
        case .menuRight:
            adjustFocusedControl(1)
        case .confirm:
            confirmFocusedControl()
        case .cancel, .pause:
            dismiss()
        default:
            break
        }
    }

    private func moveFocus(_ offset: Int) {
        let order = focusOrder
        let current = focusedControl.flatMap(order.firstIndex) ?? 0
        focusedControl = order[(current + offset + order.count) % order.count]
    }

    private func adjustFocusedControl(_ offset: Int) {
        switch focusedControl {
        case .hapticIntensity:
            gameplaySettings.update {
                $0.haptics.intensity = min(max($0.haptics.intensity + Double(offset) * 0.05, 0), 1)
            }
        case .remap(let action):
            let keys = KeyboardKey.allCases
            let current = remappingBinding(for: action).wrappedValue
            let index = keys.firstIndex(of: current) ?? 0
            remappingBinding(for: action).wrappedValue = keys[(index + offset + keys.count) % keys.count]
        case .renderQuality:
            let preferences = RenderQualityPreference.allCases
            let current = gameplaySettings.settings.renderQualityPreference
            let index = preferences.firstIndex(of: current) ?? 0
            gameplaySettings.update {
                $0.renderQualityPreference = preferences[(index + offset + preferences.count) % preferences.count]
            }
        default:
            break
        }
    }

    private func confirmFocusedControl() {
        switch focusedControl {
        case .haptics:
            gameplaySettings.update { $0.haptics.isEnabled.toggle() }
        case .perfOverlay:
            gameplaySettings.update { $0.debugPerformanceOverlayEnabled.toggle() }
        case .resetInput:
            gameplaySettings.update { $0.inputRemapping = .standard }
            inputService.updateRemapping(.standard)
        case .accessibility:
            isShowingAccessibility = true
        case .resetProfile:
            isShowingResetConfirmation = true
        case .done:
            dismiss()
        default:
            break
        }
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

struct MenuInputPrompt: View {
    let inputMethod: DrivingInputMethod

    var body: some View {
        let glyphs = inputMethod.menuPromptGlyphs
        HStack(spacing: 12) {
            Label(inputMethod.displayName, systemImage: glyphs.sourceSystemImage)
            Divider()
                .frame(height: 16)
            Text("\(glyphs.navigate) Navigate")
            Text("\(glyphs.confirm) Confirm")
            Text("\(glyphs.cancel) Back")
        }
        .font(.caption.bold().monospaced())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.06), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(inputMethod.displayName) controls. "
                + "\(glyphs.navigate) to navigate. "
                + "\(glyphs.confirm) to confirm. "
                + "\(glyphs.cancel) to go back."
        )
    }
}

private extension PlayerAction {
    var settingsTitle: String {
        switch self {
        case .steerLeft: "Steer Left"
        case .steerRight: "Steer Right"
        case .throttle: "Throttle"
        case .brake: "Brake"
        case .boost: "Boost"
        case .pause: "Pause"
        case .confirm: "Confirm"
        case .cancel: "Cancel"
        case .menuUp: "Menu Up"
        case .menuDown: "Menu Down"
        case .menuLeft: "Menu Left"
        case .menuRight: "Menu Right"
        }
    }
}

private extension KeyboardKey {
    var settingsTitle: String {
        switch self {
        case .leftArrow: "Left Arrow"
        case .rightArrow: "Right Arrow"
        case .upArrow: "Up Arrow"
        case .downArrow: "Down Arrow"
        case .space: "Space"
        case .escape: "Escape"
        case .returnKey: "Return"
        case .a: "A"
        case .d: "D"
        case .w: "W"
        case .s: "S"
        }
    }
}
