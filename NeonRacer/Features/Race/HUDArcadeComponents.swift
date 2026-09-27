import Foundation
import SwiftUI

struct HUDArcadeText: View {
    let text: String
    var font: Font
    var color: Color
    var glowColor: Color
    var alignment: TextAlignment = .leading
    var reduceGlow = false

    var body: some View {
        ZStack(alignment: alignment == .trailing ? .trailing : .leading) {
            Text(text)
                .font(font)
                .foregroundStyle(glowColor.opacity(reduceGlow ? 0.18 : 0.45))
                .multilineTextAlignment(alignment)
                .offset(x: 1, y: 0.7)
                .accessibilityHidden(true)
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .multilineTextAlignment(alignment)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.62)
    }
}

struct HUDChamferedRectangle: Shape {
    var cut: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let c = min(cut, min(rect.width, rect.height) * 0.32)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - c * 0.45, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c * 0.45))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
            path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + c * 0.45, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c * 0.45))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
            path.closeSubpath()
        }
    }
}

struct HUDScanlineOverlay: View {
    var color: Color
    var opacity: Double

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                path.move(to: CGPoint(x: 0, y: proxy.size.height))
                path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
            }
            .stroke(color.opacity(opacity), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct HUDNeonPanel<Content: View>: View {
    let palette: PaletteComponents
    let highContrast: Bool
    var accent: Color?
    var content: Content

    init(
        palette: PaletteComponents,
        highContrast: Bool,
        accent: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.highContrast = highContrast
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        let shape = HUDChamferedRectangle(cut: 11)
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Color.black.opacity(highContrast ? 0.92 : 0.44),
                in: shape
            )
            .overlay {
                shape.stroke(accent ?? palette.primary.color.opacity(0.9), lineWidth: highContrast ? 2 : 1.1)
            }
    }
}

struct HUDSegmentedMeter: View {
    let fraction: Double
    let segments: Int
    let activeColor: Color
    let inactiveColor: Color
    var height: CGFloat = 10
    var label: String? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(inactiveColor)
                Capsule()
                    .fill(activeColor)
                    .frame(width: max(height, proxy.size.width * fraction.clamped(to: 0...1)))
                Capsule()
                    .stroke(activeColor.opacity(0.72), lineWidth: 0.8)
            }
        }
        .frame(height: height)
        .accessibilityLabel(label ?? "Meter")
        .accessibilityValue("\(Int((fraction.clamped(to: 0...1) * 100).rounded())) percent")
    }

}

struct HUDScoreStageCluster: View {
    let snapshot: RaceHUDSnapshot
    let palette: PaletteComponents
    let settings: AccessibilitySettings
    let reduceGlow: Bool
    let compact: Bool

    var body: some View {
        let shape = HUDChamferedRectangle(cut: 8)
        HStack(alignment: .firstTextBaseline, spacing: compact ? 8 : 12) {
            Text(stageText)
                .font(labelFont)
                .foregroundStyle(palette.secondary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.48)
                .layoutPriority(1)
            Rectangle()
                .fill(palette.primary.color.opacity(settings.highContrast ? 0.85 : 0.45))
                .frame(width: 1, height: 14)
            Text("SCORE")
                .font(labelFont)
                .foregroundStyle(palette.primary.color)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(2)
                .accessibilityIdentifier("SCORE")
            HUDArcadeText(
                text: snapshot.formattedScore,
                font: valueFont,
                color: palette.primary.color,
                glowColor: palette.primary.color,
                reduceGlow: reduceGlow
            )
            .fixedSize()
            .layoutPriority(2)
            .accessibilityLabel("Score \(snapshot.score)")
            if !compact, let multiplier = snapshot.comboMultiplier {
                Text(String(format: "x%.1f", multiplier))
                    .font(routeFont)
                    .foregroundStyle(palette.warning.color)
            }
        }
        .padding(.horizontal, compact ? 9 : 12)
        .padding(.vertical, compact ? 5 : 6)
        .frame(height: compact ? 30 : 34)
        .background(Color.black.opacity(settings.highContrast ? 0.92 : 0.40), in: shape)
        .overlay { shape.stroke(palette.primary.color.opacity(settings.highContrast ? 1 : 0.78), lineWidth: settings.highContrast ? 2 : 1) }
        .accessibilityElement(children: .contain)
    }

    private var stageText: String {
        "S\(snapshot.stageIndexInRun) · \((snapshot.routeName ?? "STAGE").uppercased())"
    }

    private var labelFont: Font { .system(size: compact ? 12 : 15, weight: .heavy, design: .monospaced) }
    private var valueFont: Font { .system(size: compact ? 13 : 17, weight: .black, design: .monospaced).monospacedDigit() }
    private var routeFont: Font { .system(compact ? .caption2 : .caption, design: .monospaced).weight(.bold) }
}

struct HUDTimeCluster: View {
    let snapshot: RaceHUDSnapshot
    let feedback: RaceHUDFeedback?
    let palette: PaletteComponents
    let settings: AccessibilitySettings
    let compact: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            readout
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("TIME")
                .accessibilityLabel("Time remaining")
                .accessibilityValue("\(snapshot.timerSeconds) seconds")
#if DEBUG
            HUDUITestIdentifierText("TIME")
#endif
        }
    }

    private var readout: some View {
        let shape = HUDChamferedRectangle(cut: 8)
        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("TIME")
                        .font(.system(.caption2, design: .monospaced).weight(.black))
                        .foregroundStyle(timeAccent)
                    Rectangle()
                        .fill(timeAccent.opacity(settings.highContrast ? 0.85 : 0.45))
                        .frame(width: compact ? 36 : 48, height: 1)
                }
                HUDArcadeText(
                    text: snapshot.timerDigitalText,
                    font: .system(size: compact ? 32 : 39, weight: .black, design: .monospaced).monospacedDigit(),
                    color: timeAccent,
                    glowColor: timeAccent,
                    alignment: .leading,
                    reduceGlow: settings.reduceFlashes || isCrashPenalty
                )
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 6 : 7)
            .background(Color.black.opacity(settings.highContrast ? 0.92 : 0.42), in: shape)
            .overlay {
                shape.stroke(timeAccent, lineWidth: settings.highContrast ? 2 : 1.1)
            }
            .frame(width: compact ? 156 : 182, alignment: .leading)

            if let seconds = crashPenaltySeconds {
                Text("−\(seconds)s")
                    .font(.system(compact ? .caption : .callout, design: .monospaced).weight(.black))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(crashAccent, in: Capsule())
                    .overlay { Capsule().stroke(Color.white, lineWidth: settings.highContrast ? 2 : 1) }
                    .offset(x: compact ? 8 : 10, y: compact ? -8 : -10)
                    .accessibilityLabel("Time penalty")
                    .accessibilityValue("minus \(seconds) seconds")
            }
        }
    }

    private var timeAccent: Color {
        isCrashPenalty || snapshot.warning == .timeCritical ? crashAccent : palette.primary.color
    }

    private var crashAccent: Color {
        Color(red: 1, green: 0.12, blue: 0.10)
    }

    private var crashPenaltySeconds: Int? {
        if case .crashTimePenalty(let seconds) = feedback {
            return seconds
        }
        return nil
    }

    private var isCrashPenalty: Bool {
        crashPenaltySeconds != nil
    }

}

struct HUDSpeedCluster: View {
    let snapshot: RaceHUDSnapshot
    let palette: PaletteComponents
    let settings: AccessibilitySettings
    let reduceGlow: Bool
    let compact: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            panel
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("SPEED")
                .accessibilityLabel("Speed")
                .accessibilityValue(
                    "\(snapshot.speedKPH) kilometers per hour, boost \(boostPercent) percent"
                )
#if DEBUG
            HUDUITestIdentifierText("SPEED")
            HUDUITestIdentifierText("BOOST")
#endif
        }
    }

    private var panel: some View {
        HUDNeonPanel(palette: palette, highContrast: settings.highContrast) {
            VStack(alignment: .trailing, spacing: compact ? 4 : 5) {
                speedRow
                boostRow
            }
        }
        .frame(width: compact ? 172 : 202)
    }

    private var speedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("SPEED")
                .font(.system(.caption2, design: .monospaced).weight(.heavy))
                .foregroundStyle(palette.primary.color)
            Spacer(minLength: 4)
            HUDArcadeText(
                text: "\(snapshot.speedKPH)",
                font: .system(size: compact ? 28 : 32, weight: .black, design: .monospaced).monospacedDigit(),
                color: palette.primary.color,
                glowColor: palette.primary.color,
                alignment: .trailing,
                reduceGlow: reduceGlow
            )
            Text("km/h")
                .font(.system(.caption2, design: .monospaced).weight(.heavy))
                .foregroundStyle(palette.text.color)
        }
    }

    private var boostRow: some View {
        HStack(spacing: 6) {
            Text(snapshot.isBoostActive ? "BOOST ACTIVE" : "BOOST")
                .font(.system(.caption2, design: .monospaced).weight(.black))
                .foregroundStyle(snapshot.isBoostActive ? palette.warning.color : palette.secondary.color)
            HUDSegmentedMeter(
                fraction: snapshot.boostFraction,
                segments: 8,
                activeColor: snapshot.isBoostActive ? palette.warning.color : palette.secondary.color,
                inactiveColor: Color.white.opacity(0.12),
                height: 7,
                label: "Boost meter"
            )
            .frame(width: compact ? 92 : 118)
        }
    }

    private var boostPercent: Int {
        Int((snapshot.boostFraction * 100).rounded())
    }
}

struct HUDBoostThumbGauge: View {
    let snapshot: RaceHUDSnapshot
    let palette: PaletteComponents
    let settings: AccessibilitySettings

    var body: some View {
        ZStack(alignment: .topLeading) {
            panel
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("BOOST_THUMB")
                .accessibilityLabel("Boost")
                .accessibilityValue("\(boostPercent) percent")
#if DEBUG
            HUDUITestIdentifierText("BOOST_THUMB")
#endif
        }
    }

    private var panel: some View {
        HUDNeonPanel(
            palette: palette,
            highContrast: settings.highContrast,
            accent: snapshot.isBoostActive ? palette.warning.color : palette.secondary.color
        ) {
            VStack(alignment: .leading, spacing: 5) {
                header
                HUDSegmentedMeter(
                    fraction: snapshot.boostFraction,
                    segments: 10,
                    activeColor: snapshot.isBoostActive ? palette.warning.color : palette.secondary.color,
                    inactiveColor: Color.white.opacity(settings.highContrast ? 0.18 : 0.10),
                    height: 12,
                    label: "Thumb boost gauge"
                )
                Text("\(boostPercent)% CHARGE")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(palette.text.color)
            }
        }
        .frame(width: 190)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: snapshot.isBoostActive ? "bolt.fill" : "bolt")
                .accessibilityHidden(true)
            Text(snapshot.isBoostActive ? "BOOST FIRE" : "BOOST")
                .font(.system(.caption, design: .monospaced).weight(.black))
        }
        .foregroundStyle(snapshot.isBoostActive ? palette.warning.color : palette.secondary.color)
    }

    private var boostPercent: Int {
        Int((snapshot.boostFraction * 100).rounded())
    }
}

#if DEBUG
private struct HUDUITestIdentifierText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 1, weight: .regular, design: .monospaced))
            .foregroundStyle(.white.opacity(0.01))
            .frame(width: 1, height: 1)
            .accessibilityIdentifier(text)
    }
}
#endif

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
