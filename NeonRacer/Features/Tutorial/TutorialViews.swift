import SwiftUI

struct TutorialPromptView: View {
    let step: TutorialStep
    let inputMethod: DrivingInputMethod
    let advance: () -> Void
    let skip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var content: TutorialPromptContent {
        TutorialPromptLibrary.content(for: step, inputMethod: inputMethod)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: content.glyph.symbolName)
                    .font(.title2.bold())
                    .foregroundStyle(NeonPalette.cyan)
                    .accessibilityLabel(content.glyph.accessibilityLabel)

                VStack(alignment: .leading, spacing: 3) {
                    Text(content.title.uppercased())
                        .font(.headline.monospaced().bold())
                    Text("DRIVING TIP")
                        .font(.caption2.monospaced())
                        .foregroundStyle(NeonPalette.magenta)
                }
            }

            Text(content.instruction)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("SKIP", action: skip)
                    .buttonStyle(.bordered)

                Spacer()

                Button(step.next == nil ? "FINISH" : "GOT IT", action: advance)
                    .buttonStyle(.borderedProminent)
                    .tint(NeonPalette.magenta)
            }
            .font(.caption.bold().monospaced())
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: 390, alignment: .leading)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(NeonPalette.cyan.opacity(0.7), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
    }
}

struct TutorialReferenceView: View {
    @Binding var inputMethod: DrivingInputMethod
    let replay: () -> Void
    let reset: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Control hints") {
                    Picker("Input method", selection: $inputMethod) {
                        ForEach(DrivingInputMethod.allCases, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                }

                Section("Driving reference") {
                    ForEach(TutorialStep.allCases, id: \.self) { step in
                        let content = TutorialPromptLibrary.content(for: step, inputMethod: inputMethod)
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(content.title)
                                    .font(.headline)
                                Text(content.instruction)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: content.glyph.symbolName)
                                .accessibilityLabel(content.glyph.accessibilityLabel)
                        }
                    }
                }

                Section("Tutorial") {
                    Button("Replay on next race", action: replay)
                    Button("Reset first-run state", role: .destructive, action: reset)
                }
            }
            .navigationTitle("Driving Guide")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

