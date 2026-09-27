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
    @StateObject private var inputService = InputService()
    @State private var isShowingSettings = false
    @State private var isShowingGarage = false
    @FocusState private var focusedButton: MenuButton?

    private enum MenuButton: Hashable {
        case start, garage, settings
    }

    var body: some View {
        let palette = NeonPalette.colors(for: accessibility.settings)

        ZStack {
            TitleArtBackground()

            VStack {
                Spacer(minLength: 0)

                HStack(spacing: 14) {
                    Button(action: startRace) {
                        Label("RACE", systemImage: "flag.checkered")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.secondary.color)
                    .accessibilityHint("Starts a new race")
                    .focused($focusedButton, equals: .start)

                    Button {
                        isShowingGarage = true
                    } label: {
                        Label("GARAGE", systemImage: "car.side.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(palette.primary.color)
                    .accessibilityHint("Choose an unlocked car, palette, and route")
                    .focused($focusedButton, equals: .garage)

                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("SETTINGS", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(palette.primary.color)
                    .accessibilityHint("Opens audio, haptics, accessibility, and reset options")
                    .focused($focusedButton, equals: .settings)
                }
                .font(.headline.bold().monospaced())
                .lineLimit(1)
                .controlSize(.large)
                .frame(maxWidth: 720)
                .padding(10)
                .background(.black.opacity(accessibility.settings.highContrast ? 0.9 : 0.55), in: Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                audio: audio,
                gameplaySettings: gameplaySettings,
                inputService: inputService,
                resetProfile: resetProfile
            )
        }
        .sheet(isPresented: $isShowingGarage) {
            GarageView(
                profile: $profile,
                inputService: inputService,
                saveProfile: saveProfile
            )
        }
        .animation(
            accessibility.settings.resolvedReduceMotion(systemReduceMotion: systemReduceMotion)
                ? nil
                : .easeInOut(duration: 0.25),
            value: accessibility.settings
        )
        .onAppear {
            focusedButton = .start
            configureMenuInput()
            inputService.start()
            inputService.updateRemapping(gameplaySettings.settings.inputRemapping)
        }
        .onDisappear {
            inputService.stop()
        }
        .onChange(of: gameplaySettings.settings.inputRemapping) { _, newValue in
            inputService.updateRemapping(newValue)
        }
        .onChange(of: isShowingSettings) { configureMenuInputIfNeeded() }
        .onChange(of: isShowingGarage) { configureMenuInputIfNeeded() }
    }

    private var menuFocusOrder: [MenuButton] {
        [.start, .garage, .settings]
    }

    private func configureMenuInputIfNeeded() {
        guard !hasPresentedSheet else {
            return
        }
        configureMenuInput()
    }

    private var hasPresentedSheet: Bool {
        isShowingSettings
            || isShowingGarage
    }

    private func configureMenuInput() {
        inputService.actionHandler = handleInputAction
    }

    private func handleInputAction(_ action: PlayerAction) {
        switch action {
        case .menuUp, .menuLeft:
            moveMenuFocus(-1)
        case .menuDown, .menuRight:
            moveMenuFocus(1)
        case .confirm:
            confirmFocusedButton()
        case .cancel, .pause:
            break
        default:
            break
        }
    }

    private func moveMenuFocus(_ offset: Int) {
        let current = focusedButton.flatMap(menuFocusOrder.firstIndex) ?? 0
        focusedButton = menuFocusOrder[
            (current + offset + menuFocusOrder.count) % menuFocusOrder.count
        ]
    }

    private func confirmFocusedButton() {
        switch focusedButton ?? .start {
        case .start:
            startRace()
        case .garage:
            isShowingGarage = true
        case .settings:
            isShowingSettings = true
        }
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

/// Title art scaled to fill: in landscape it spans the full device width (never letterboxed)
/// and stays vertically centered so the logo remains in view while the excess is cropped.
private struct TitleArtBackground: View {
    private static let artSize = CGSize(width: 2240, height: 1888)
    private static let verticalLift: CGFloat = 0.10

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.size
            let scale = max(
                container.width / Self.artSize.width,
                container.height / Self.artSize.height
            )
            let artHeight = Self.artSize.height * scale
            let overflow = max(0, (artHeight - container.height) / 2)
            // Lift the art so the logo and hero car both fit; never past the image edge.
            let lift = min(container.height * Self.verticalLift, overflow)

            Image("TitleScreen")
                .resizable()
                .frame(width: Self.artSize.width * scale, height: artHeight)
                .offset(y: -lift)
                .frame(width: container.width, height: container.height)
                .clipped()
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("CyberRun title art")
        .accessibilityAddTraits([.isImage, .isHeader])
    }
}
