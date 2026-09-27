import Foundation
import SwiftUI

struct HUDCalloutView: View {
    let content: HUDCalloutContent
    let palette: PaletteComponents
    let settings: AccessibilitySettings
    let reduceMotion: Bool

    init(
        feedback: RaceHUDFeedback,
        palette: PaletteComponents,
        settings: AccessibilitySettings,
        reduceMotion: Bool
    ) {
        self.content = HUDCalloutContent(feedback: feedback, palette: palette)
        self.palette = palette
        self.settings = settings
        self.reduceMotion = reduceMotion
    }

    init(
        warning: RaceHUDWarning,
        palette: PaletteComponents,
        settings: AccessibilitySettings,
        reduceMotion: Bool
    ) {
        self.content = HUDCalloutContent(warning: warning, palette: palette)
        self.palette = palette
        self.settings = settings
        self.reduceMotion = reduceMotion
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: content.symbol)
                .font(.system(size: 16, weight: .black))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HUDArcadeText(
                    text: content.title,
                    font: .system(size: 18, weight: .black, design: .monospaced),
                    color: content.accent,
                    glowColor: content.accent,
                    reduceGlow: settings.reduceFlashes
                )
                if let subtitle = content.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.text.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .foregroundStyle(content.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(settings.highContrast ? 0.94 : 0.56), in: Capsule())
        .overlay { Capsule().stroke(content.accent, lineWidth: settings.highContrast ? 2 : 1.2) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityValue(content.accessibilityValue)
        .accessibilityAddTraits(.isHeader)
    }
}

struct HUDCountdownOverlay: View {
    let snapshot: RaceHUDSnapshot
    let palette: PaletteComponents
    let settings: AccessibilitySettings
    let reduceMotion: Bool

    var body: some View {
        if let countdown = snapshot.countdownSeconds {
            countdownText("\(countdown)", label: "Race begins in \(countdown)")
        } else if snapshot.phase == .racing {
            EmptyView()
        }
    }

    private func countdownText(_ text: String, label: String) -> some View {
        HUDArcadeText(
            text: text,
            font: .system(size: settings.largeHUD ? 112 : 92, weight: .black, design: .monospaced).monospacedDigit(),
            color: palette.warning.color,
            glowColor: palette.secondary.color,
            alignment: .center,
            reduceGlow: settings.reduceFlashes
        )
        .padding(28)
        .background(Color.black.opacity(settings.highContrast ? 0.90 : 0.48), in: Circle())
        .overlay { Circle().stroke(palette.warning.color, lineWidth: settings.highContrast ? 4 : 2) }
        .accessibilityLabel(label)
    }
}

struct HUDCalloutContent {
    let symbol: String
    let title: String
    let subtitle: String?
    let accessibilityLabel: String
    let accessibilityValue: String
    let accent: Color

    init(feedback: RaceHUDFeedback, palette: PaletteComponents) {
        let hot = palette.secondary.color
        let cool = palette.primary.color
        let warn = palette.warning.color
        switch feedback {
        case .countdown(let value):
            self.init(symbol: "\(value).circle.fill", title: "\(value)", subtitle: "GET READY", accessibilityLabel: "Countdown", accessibilityValue: "Race begins in \(value)", accent: warn)
        case .go:
            self.init(symbol: "flag.fill", title: "GO!", subtitle: "FULL THROTTLE", accessibilityLabel: "Go", accessibilityValue: "Race started", accent: warn)
        case .boostEngaged:
            self.init(symbol: "bolt.fill", title: "BOOST!", subtitle: "SPEED SURGE", accessibilityLabel: "Boost", accessibilityValue: "Boost engaged", accent: warn)
        case .checkpoint(let number):
            self.init(symbol: "flag.checkered", title: "CHECKPOINT \(number)", subtitle: nil, accessibilityLabel: "Checkpoint \(number)", accessibilityValue: "Checkpoint crossed", accent: cool)
        case .checkpointBonus(let number, let seconds):
            self.init(symbol: "flag.checkered", title: "CHECKPOINT +\(seconds)s", subtitle: "GATE \(number) CLEARED", accessibilityLabel: "Checkpoint", accessibilityValue: "Checkpoint \(number), plus \(seconds) seconds", accent: cool)
        case .routeFork:
            self.init(symbol: "arrow.triangle.branch", title: "ROUTE FORK", subtitle: "CHOOSE A LANE", accessibilityLabel: "Route fork", accessibilityValue: "Choose a route", accent: hot)
        case .forkPreview(let left, let right):
            let subtitle = "← LEFT \(left ?? "ROUTE")   RIGHT \(right ?? "ROUTE") →"
            self.init(symbol: "arrow.triangle.branch", title: "FORK", subtitle: subtitle.uppercased(), accessibilityLabel: "Route fork", accessibilityValue: subtitle, accent: hot)
        case .routeChosen(let name):
            self.init(symbol: "arrow.turn.up.right", title: name.uppercased(), subtitle: "ROUTE LOCKED", accessibilityLabel: "Route selected", accessibilityValue: name, accent: hot)
        case .finalStretch:
            self.init(symbol: "road.lanes", title: "FINAL STRETCH", subtitle: "FINISH AHEAD", accessibilityLabel: "Final stretch", accessibilityValue: "Finish ahead", accent: warn)
        case .score(let source, let points):
            self.init(symbol: "plus.circle.fill", title: "+\(points) \(source.hudTitle)", subtitle: "SCORE UP", accessibilityLabel: source.hudTitle, accessibilityValue: "\(points) points", accent: cool)
        case .nearMiss(let points):
            self.init(symbol: "sparkles", title: "NEAR MISS!", subtitle: points > 0 ? "+\(points) POINTS" : "CLOSE CALL", accessibilityLabel: "Near miss", accessibilityValue: points > 0 ? "\(points) points" : "Close call", accent: warn)
        case .overtake(let points):
            self.init(symbol: "arrow.up.forward.circle.fill", title: "OVERTAKE", subtitle: points > 0 ? "+\(points) POINTS" : "POSITION GAIN", accessibilityLabel: "Overtake", accessibilityValue: points > 0 ? "\(points) points" : "Position gained", accent: cool)
        case .drift(let multiplier, let points):
            self.init(symbol: "flame.fill", title: String(format: "DRIFT x%.1f", multiplier), subtitle: "+\(points) POINTS", accessibilityLabel: "Drift", accessibilityValue: String(format: "Multiplier %.1f, %d points", multiplier, points), accent: hot)
        case .comboIncreased(let multiplier):
            self.init(symbol: "flame.fill", title: String(format: "COMBO x%.2f", multiplier), subtitle: "CHAIN CONTINUES", accessibilityLabel: "Combo increased", accessibilityValue: String(format: "Multiplier %.2f", multiplier), accent: warn)
        case .comboBroken:
            self.init(symbol: "flame.slash.fill", title: "COMBO LOST", subtitle: "BUILD IT BACK", accessibilityLabel: "Combo lost", accessibilityValue: "Combo ended", accent: hot)
        case .rankChanged(let rank):
            self.init(symbol: "trophy.fill", title: "RANK \(rank.hudTitle)", subtitle: "KEEP PUSHING", accessibilityLabel: "Rank changed", accessibilityValue: rank.hudTitle, accent: warn)
        case .crashTimePenalty(let seconds):
            self.init(symbol: "timer", title: "-\(seconds)s", subtitle: "CRASH PENALTY", accessibilityLabel: "Crash time penalty", accessibilityValue: "\(seconds) second penalty", accent: hot)
        case .collision:
            self.init(symbol: "exclamationmark.octagon.fill", title: "IMPACT", subtitle: "RECOVER!", accessibilityLabel: "Impact", accessibilityValue: "Collision penalty", accent: hot)
        case .finished:
            self.init(symbol: "trophy.fill", title: "FINISH!", subtitle: "RUN COMPLETE", accessibilityLabel: "Finish", accessibilityValue: "Race finished", accent: warn)
        case .failed:
            self.init(symbol: "clock.badge.exclamationmark", title: "TIME UP", subtitle: "RUN ENDED", accessibilityLabel: "Time up", accessibilityValue: "Race failed because time expired", accent: hot)
        }
    }

    init(warning: RaceHUDWarning, palette: PaletteComponents) {
        switch warning {
        case .timeCritical:
            self.init(symbol: "exclamationmark.triangle.fill", title: "TIME CRITICAL", subtitle: "UNDER 10 SECONDS", accessibilityLabel: "Time critical", accessibilityValue: "Ten seconds or less remain", accent: Color(red: 1, green: 0.18, blue: 0.16))
        case .roadEdge:
            self.init(symbol: "arrow.left.and.right", title: "RETURN TO ROAD", subtitle: "EDGE WARNING", accessibilityLabel: "Return to road", accessibilityValue: "Vehicle is near the road edge", accent: palette.warning.color)
        case .boostDepleted:
            self.init(symbol: "bolt.slash.fill", title: "BOOST EMPTY", subtitle: "RELEASE TO RECHARGE", accessibilityLabel: "Boost empty", accessibilityValue: "Release boost to recharge", accent: palette.secondary.color)
        }
    }

    private init(
        symbol: String,
        title: String,
        subtitle: String?,
        accessibilityLabel: String,
        accessibilityValue: String,
        accent: Color
    ) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.accent = accent
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

private extension RaceRank {
    var hudTitle: String {
        switch self {
        case .unranked: "UNRANKED"
        case .bronze: "BRONZE"
        case .silver: "SILVER"
        case .gold: "GOLD"
        }
    }
}
