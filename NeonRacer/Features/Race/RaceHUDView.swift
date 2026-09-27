import Foundation
import SwiftUI

struct RaceHUDView: View {
    let snapshot: RaceHUDSnapshot
    let feedback: RaceHUDFeedback?
    let settings: AccessibilitySettings

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var palette: PaletteComponents {
        NeonPalette.colors(for: settings)
    }

    private var usesCompactLayout: Bool {
        dynamicTypeSize.isAccessibilitySize || settings.largeHUD
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = usesCompactLayout || proxy.size.width < 1_050
            ZStack(alignment: .top) {
                if compact {
                    compactLayout
                } else {
                    regularLayout
                }

                if let feedback {
                    feedbackBanner(feedback)
                        .padding(.top, compact ? 132 : 68)
                        .transition(feedbackTransition)
                } else if let warning = snapshot.warning {
                    warningBanner(warning)
                        .padding(.top, compact ? 132 : 68)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .safeAreaPadding(.horizontal, 12)
        .safeAreaPadding(.vertical, 8)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Race status")
    }

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            metric(title: "SPEED", value: "\(snapshot.speedMPH)", suffix: "MPH", icon: "speedometer")
            metric(title: "SCORE", value: snapshot.score.formatted(), icon: "star.fill")
            if let multiplier = snapshot.comboMultiplier {
                metric(
                    title: "COMBO",
                    value: String(format: "%.2f×", multiplier),
                    icon: "flame.fill"
                )
            }
            Spacer(minLength: 120)
            stageCard
            timerCard
            boostCard
        }
        .padding(.leading, 138)
    }

    private var compactLayout: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                metric(title: "SPEED", value: "\(snapshot.speedMPH)", suffix: "MPH", icon: "speedometer")
                metric(title: "SCORE", value: snapshot.score.formatted(), icon: "star.fill")
                timerCard
            }
            HStack(spacing: 8) {
                stageCard
                boostCard
                if let multiplier = snapshot.comboMultiplier {
                    metric(
                        title: "COMBO",
                        value: String(format: "%.2f×", multiplier),
                        icon: "flame.fill"
                    )
                }
            }
        }
        .padding(.leading, 138)
    }

    private func metric(
        title: String,
        value: String,
        suffix: String? = nil,
        icon: String
    ) -> some View {
        HUDPanel(palette: palette, highContrast: settings.highContrast) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption2.bold().monospaced())
                        .foregroundStyle(palette.primary.color)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value)
                            .font(.title3.bold().monospacedDigit())
                        if let suffix {
                            Text(suffix)
                                .font(.caption2.bold().monospaced())
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.capitalized)
        .accessibilityValue(suffix.map { "\(value) \($0)" } ?? value)
    }

    private var timerCard: some View {
        let minutes = snapshot.timerSeconds / 60
        let seconds = snapshot.timerSeconds % 60
        let value = String(format: "%01d:%02d", minutes, seconds)

        return HUDPanel(
            palette: palette,
            highContrast: settings.highContrast,
            emphasized: snapshot.warning == .timeCritical
        ) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("TIME")
                        .font(.caption2.bold().monospaced())
                        .foregroundStyle(palette.primary.color)
                    Text(value)
                        .font(.title3.bold().monospacedDigit())
                }
            } icon: {
                Image(systemName: "timer")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue("\(minutes) minutes, \(seconds) seconds")
    }

    private var stageCard: some View {
        HUDPanel(palette: palette, highContrast: settings.highContrast) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "flag.checkered")
                        .accessibilityHidden(true)
                    Text("STAGE \(snapshot.stageNumber)")
                        .font(.caption.bold().monospaced())
                    if let routeName = snapshot.routeName {
                        Text("• \(routeName)")
                            .font(.caption2.bold().monospaced())
                    }
                }
                ProgressView(value: snapshot.stageProgress)
                    .tint(palette.primary.color)
                    .frame(minWidth: 86)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stage \(snapshot.stageNumber) progress")
        .accessibilityValue("\(Int(snapshot.stageProgress * 100)) percent")
    }

    private var boostCard: some View {
        HUDPanel(
            palette: palette,
            highContrast: settings.highContrast,
            emphasized: snapshot.isBoostActive
        ) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: snapshot.isBoostActive ? "bolt.fill" : "bolt")
                        .accessibilityHidden(true)
                    Text(snapshot.isBoostActive ? "BOOST ACTIVE" : "BOOST")
                        .font(.caption.bold().monospaced())
                }
                HStack(spacing: 6) {
                    ProgressView(value: snapshot.boostFraction)
                        .tint(palette.secondary.color)
                        .frame(minWidth: 72)
                    Text("\(Int((snapshot.boostFraction * 100).rounded()))%")
                        .font(.caption2.bold().monospacedDigit())
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.isBoostActive ? "Boost active" : "Boost charge")
        .accessibilityValue("\(Int((snapshot.boostFraction * 100).rounded())) percent")
    }

    private func warningBanner(_ warning: RaceHUDWarning) -> some View {
        let content: (String, String, String) = switch warning {
        case .timeCritical: ("exclamationmark.triangle.fill", "TIME CRITICAL", "Ten seconds or less remain")
        case .roadEdge: ("arrow.left.and.right", "RETURN TO ROAD", "Vehicle is near the road edge")
        case .boostDepleted: ("bolt.slash.fill", "BOOST EMPTY", "Release boost to recharge")
        }

        return banner(icon: content.0, title: content.1, accessibilityValue: content.2, warning: true)
    }

    private func feedbackBanner(_ feedback: RaceHUDFeedback) -> some View {
        let content: (String, String, String) = switch feedback {
        case .countdown(let value): ("\(value).circle.fill", "\(value)", "Race begins in \(value)")
        case .go: ("flag.fill", "GO!", "Race started")
        case .boostEngaged: ("bolt.fill", "BOOST!", "Boost engaged")
        case .checkpoint(let number):
            ("flag.checkered", "CHECKPOINT \(number)", "Checkpoint \(number) crossed")
        case .routeFork:
            ("arrow.triangle.branch", "ROUTE FORK", "Choose a route")
        case .routeChosen(let name):
            ("arrow.turn.up.right", name.uppercased(), "Route selected: \(name)")
        case .score(let source, let points):
            ("plus.circle.fill", "+\(points) \(source.hudTitle)", "\(points) points for \(source.hudTitle)")
        case .comboIncreased(let multiplier):
            ("flame.fill", String(format: "%.2f× COMBO", multiplier), "Combo multiplier \(multiplier)")
        case .comboBroken: ("flame.slash.fill", "COMBO LOST", "Combo ended")
        case .collision: ("exclamationmark.octagon.fill", "IMPACT", "Collision penalty")
        case .finished: ("trophy.fill", "FINISH!", "Race finished")
        case .failed: ("clock.badge.exclamationmark", "TIME EXPIRED", "Race failed because time expired")
        }

        return banner(icon: content.0, title: content.1, accessibilityValue: content.2, warning: false)
            .accessibilityAddTraits(.isHeader)
    }

    private func banner(
        icon: String,
        title: String,
        accessibilityValue: String,
        warning: Bool
    ) -> some View {
        Label(title, systemImage: icon)
            .font(.headline.bold().monospaced())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                warning ? palette.warning.color.opacity(0.96) : palette.panel.color.opacity(0.96),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(warning ? Color.white : palette.primary.color, lineWidth: 2)
            }
            .shadow(color: .black, radius: 3, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValue)
    }

    private var feedbackTransition: AnyTransition {
        if settings.resolvedReduceMotion(systemReduceMotion: systemReduceMotion) {
            return .opacity
        }
        return .scale(scale: 0.92).combined(with: .opacity)
    }

    private struct HUDPanel<Content: View>: View {
        let palette: PaletteComponents
        let highContrast: Bool
        let emphasized: Bool
        let content: Content

        init(
            palette: PaletteComponents,
            highContrast: Bool,
            emphasized: Bool = false,
            @ViewBuilder content: () -> Content
        ) {
            self.palette = palette
            self.highContrast = highContrast
            self.emphasized = emphasized
            self.content = content()
        }

        var body: some View {
            content
                .foregroundStyle(palette.text.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Color.black.opacity(highContrast ? 0.96 : 0.78),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            emphasized ? palette.warning.color : palette.primary.color.opacity(0.75),
                            lineWidth: emphasized ? 3 : 1
                        )
                }
                .shadow(color: .black.opacity(0.8), radius: 3, y: 2)
        }
    }
}

private extension ScoreSource {
    var hudTitle: String {
        switch self {
        case .distance: "DISTANCE"
        case .speed: "SPEED"
        case .boost: "BOOST"
        case .overtake: "OVERTAKE"
        case .nearMiss: "NEAR MISS"
        case .drift: "DRIFT"
        case .checkpoint: "CHECKPOINT"
        case .position: "POSITION"
        case .finish: "FINISH"
        case .collision: "COLLISION"
        }
    }
}
