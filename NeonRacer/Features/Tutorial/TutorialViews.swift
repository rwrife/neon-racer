import SwiftUI

struct TutorialPromptView: View {
    let step: TutorialStep
    let inputMethod: DrivingInputMethod
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

            HStack(spacing: 12) {
                Label("Do the move to continue", systemImage: "checkmark.circle")
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(.white.opacity(0.82))
                    .accessibilityLabel("Complete the driving action to continue")

                Spacer(minLength: 8)

                Button("SKIP", action: skip)
                    .buttonStyle(.bordered)
                    .accessibilityHint("Skips the tutorial and saves that choice")
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
        .accessibilityLabel("Tutorial. \(content.title). \(content.instruction)")
        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
    }
}

struct TutorialReferenceView: View {
    @Binding var inputMethod: DrivingInputMethod
    let progress: TutorialProgress
    let replay: () -> Void
    let complete: () -> Void
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
                    LabeledContent("Status", value: tutorialStatusText)
                    Button("Replay on next race", action: replay)
                    Button("Mark tutorial completed", action: complete)
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

    private var tutorialStatusText: String {
        switch progress.status {
        case .notStarted:
            "Not started"
        case .inProgress:
            if let currentStep = progress.currentStep {
                "In progress: \(TutorialPromptLibrary.content(for: currentStep, inputMethod: inputMethod).title)"
            } else {
                "In progress"
            }
        case .completed:
            "Completed"
        case .skipped:
            "Skipped"
        }
    }
}
