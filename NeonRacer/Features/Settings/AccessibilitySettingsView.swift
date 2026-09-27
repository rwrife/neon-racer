import SwiftUI

struct AccessibilitySettingsView: View {
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
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
