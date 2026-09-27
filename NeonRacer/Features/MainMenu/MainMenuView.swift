import SwiftUI

struct MainMenuView: View {
    @Binding var profile: PlayerProfile
    @ObservedObject var audio: AudioService
    @ObservedObject var gameplaySettings: GameplaySettingsStore
    let startRace: () -> Void
    let saveProfile: () -> Void
    let resetProfile: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject private var accessibility: AccessibilitySettingsStore
    @State private var isShowingDrivingGuide = false
    @State private var isShowingSettings = false
    @State private var isShowingGarage = false
    @State private var isShowingCredits = false
    @State private var isShowingLegal = false
    @FocusState private var focusedButton: MenuButton?

    private enum MenuButton: Hashable {
        case start, garage, guide, settings, credits, legal
    }

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
                .focused($focusedButton, equals: .start)

                Button {
                    isShowingGarage = true
                } label: {
                    Label("GARAGE", systemImage: "car.side.fill")
                        .font(.subheadline.bold().monospaced())
                }
                .buttonStyle(.bordered)
                .tint(palette.primary.color)
                .accessibilityHint("Choose an unlocked car, palette, and route")
                .focused($focusedButton, equals: .garage)

                Button {
                    isShowingDrivingGuide = true
                } label: {
                    Label("DRIVING GUIDE", systemImage: "book.pages")
                        .font(.subheadline.bold().monospaced())
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opens controls, tutorial replay, and reset options")
                .focused($focusedButton, equals: .guide)

                Button {
                    isShowingSettings = true
                } label: {
                    Label("SETTINGS", systemImage: "gearshape")
                        .font(.subheadline.bold().monospaced())
                }
                .buttonStyle(.bordered)
                .tint(palette.primary.color)
                .accessibilityHint("Opens audio, haptics, accessibility, and reset options")
                .focused($focusedButton, equals: .settings)

                HStack {
                    Button("CREDITS") { isShowingCredits = true }
                        .focused($focusedButton, equals: .credits)
                    Button("LEGAL") { isShowingLegal = true }
                        .focused($focusedButton, equals: .legal)
                }
                .buttonStyle(.borderless)
                .font(.caption.bold().monospaced())

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
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                audio: audio,
                gameplaySettings: gameplaySettings,
                resetProfile: resetProfile
            )
        }
        .sheet(isPresented: $isShowingGarage) {
            GarageView(profile: $profile, saveProfile: saveProfile)
        }
        .sheet(isPresented: $isShowingCredits) {
            InformationView(
                title: "Credits",
                text: "Designed and built with SwiftUI and SpriteKit.\n\nCreated by the Neon Racer team."
            )
        }
        .sheet(isPresented: $isShowingLegal) {
            InformationView(
                title: "Legal",
                text: "Neon Racer is provided under the terms included with this application. No account, advertising identifier, or online service is required."
            )
        }
        .animation(
            accessibility.settings.resolvedReduceMotion(systemReduceMotion: systemReduceMotion)
                ? nil
                : .easeInOut(duration: 0.25),
            value: accessibility.settings
        )
        .onAppear { focusedButton = .start }
    }
}

struct ResultsView: View {
    let result: RaceResult
    let previousBest: Int
    let unlocks: [String]
    let retry: () -> Void
    let returnToTitle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject private var accessibility: AccessibilitySettingsStore
    @FocusState private var focusedAction: Action?

    private enum Action: Hashable { case retry, title }

    var body: some View {
        let palette = NeonPalette.colors(for: accessibility.settings)
        ZStack {
            LinearGradient(
                colors: [palette.background.color, palette.panel.color],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                Text(result.outcome == .finished ? "FINISH!" : "RUN OVER")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .foregroundStyle(result.outcome == .finished ? palette.secondary.color : palette.primary.color)
                    .accessibilityAddTraits(.isHeader)
                Text("\(result.rank.rawValue.uppercased()) RANK")
                    .font(.title2.bold().monospaced())
                Text(result.score, format: .number)
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .accessibilityLabel("Score \(result.score)")
                if result.score > previousBest {
                    Label("NEW BEST", systemImage: "sparkles")
                        .foregroundStyle(palette.secondary.color)
                        .font(.headline.bold())
                } else {
                    Text("BEST \(previousBest)")
                        .font(.headline.monospaced())
                }
                Grid(horizontalSpacing: 28, verticalSpacing: 10) {
                    resultRow("ROUTE", result.routeName)
                    resultRow(
                        "TIME",
                        String(
                            format: "%d:%02d",
                            Int(result.elapsedTime) / 60,
                            Int(result.elapsedTime) % 60
                        )
                    )
                    resultRow("DISTANCE", "\(Int(result.distance.rounded())) m")
                    resultRow("DISTANCE SCORE", "\(result.distancePoints)")
                    resultRow("SPEED SCORE", "\(result.speedPoints)")
                    resultRow("BOOST SCORE", "\(result.boostPoints)")
                    resultRow("OVERTAKE SCORE", "\(result.overtakePoints)")
                    resultRow("NEAR MISS SCORE", "\(result.nearMissPoints)")
                    resultRow("DRIFT SCORE", "\(result.driftPoints)")
                    resultRow("CHECKPOINT SCORE", "\(result.checkpointPoints)")
                    resultRow("POSITION SCORE", "\(result.positionPoints)")
                    resultRow("FINISH SCORE", "\(result.finishPoints)")
                    if result.collisionPoints != 0 {
                        resultRow("COLLISION PENALTY", "\(result.collisionPoints)")
                    }
                }
                .padding()
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
                if !unlocks.isEmpty {
                    Label("UNLOCKED: \(unlocks.joined(separator: ", "))", systemImage: "lock.open.fill")
                        .font(.headline.bold())
                        .foregroundStyle(palette.secondary.color)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 18) {
                    Button("RETRY", action: retry)
                        .buttonStyle(.borderedProminent)
                        .focused($focusedAction, equals: .retry)
                    Button("TITLE", action: returnToTitle)
                        .buttonStyle(.bordered)
                        .focused($focusedAction, equals: .title)
                }
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { focusedAction = .retry }
        .animation(
            accessibility.settings.resolvedReduceMotion(systemReduceMotion: systemReduceMotion)
                ? nil : .easeOut(duration: 0.3),
            value: result
        )
    }

    @ViewBuilder
    private func resultRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text(value).gridColumnAlignment(.trailing)
        }
        .font(.subheadline.bold().monospaced())
    }
}

private struct InformationView: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(32)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    MainMenuView(
        profile: .constant(.newPlayer),
        audio: AudioService(),
        gameplaySettings: GameplaySettingsStore(),
        startRace: {},
        saveProfile: {},
        resetProfile: {}
    )
        .environmentObject(AccessibilitySettingsStore())
}
