import Foundation
import SwiftUI

struct HUDMinimapPanel: View {
    let snapshot: RaceHUDSnapshot
    let palette: PaletteComponents
    let settings: AccessibilitySettings
    let compact: Bool

    var body: some View {
        let shape = HUDChamferedRectangle(cut: 12)
        minimapCanvas
            .frame(width: compact ? 90 : 102, height: compact ? 56 : 61)
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, compact ? 5 : 6)
        .background(
            Color.black.opacity(settings.highContrast ? 0.92 : 0.38),
            in: shape
        )
        .overlay {
            shape.stroke(palette.primary.color.opacity(settings.highContrast ? 1 : 0.88), lineWidth: settings.highContrast ? 2 : 1.05)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Minimap")
        .accessibilityValue("Route progress \(Int((snapshot.minimap.progress * 100).rounded())) percent")
    }

    private var minimapCanvas: some View {
        GeometryReader { proxy in
            let points = snapshot.minimap.polyline.map { point in
                CGPoint(x: point.x * proxy.size.width, y: point.y * proxy.size.height)
            }
            ZStack {
                routePath(points: points)
                    .stroke(palette.primary.color.opacity(settings.highContrast ? 1 : 0.92), style: StrokeStyle(lineWidth: settings.highContrast ? 3.5 : 2.5, lineCap: .round, lineJoin: .round))
                routePath(points: points)
                    .stroke(Color.white.opacity(settings.highContrast ? 0.82 : 0.34), style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round))
                ForEach(snapshot.minimap.markers) { marker in
                    markerView(marker, in: proxy.size)
                }
                playerArrow(in: proxy.size)
            }
            .clipShape(HUDChamferedRectangle(cut: 8))
        }
    }

    private func routePath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func markerView(_ marker: HUDMinimapMarker, in size: CGSize) -> some View {
        let color = marker.isReached ? palette.warning.color : palette.secondary.color
        return ZStack {
            HUDChamferedRectangle(cut: 2)
                .fill(Color.black.opacity(0.78))
                .frame(width: 12, height: 10)
            Text(marker.label)
                .font(.system(size: 5, weight: .black, design: .monospaced))
                .foregroundStyle(color)
        }
        .overlay { HUDChamferedRectangle(cut: 2).stroke(color, lineWidth: 0.8) }
        .position(x: marker.point.x * size.width, y: marker.point.y * size.height)
        .accessibilityLabel(marker.label)
        .accessibilityValue(marker.isReached ? "reached" : "ahead")
    }

    private func playerArrow(in size: CGSize) -> some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: compact ? 12 : 13, weight: .black))
            .foregroundStyle(palette.text.color)
            .rotationEffect(.radians(snapshot.minimap.playerHeadingRadians))
            .position(
                x: snapshot.minimap.playerPoint.x * size.width,
                y: snapshot.minimap.playerPoint.y * size.height
            )
            .accessibilityHidden(true)
    }
}

struct HUDStandingsPanel: View {
    let standings: [HUDStandingEntry]
    let palette: PaletteComponents
    let settings: AccessibilitySettings
    let compact: Bool

    var body: some View {
        if standings.count > 1 {
            HUDNeonPanel(
                palette: palette,
                highContrast: settings.highContrast,
                accent: palette.secondary.color
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("STANDINGS")
                        .font(.system(.caption2, design: .monospaced).weight(.black))
                        .foregroundStyle(palette.secondary.color)
                    ForEach(standings.prefix(compact ? 3 : 5)) { entry in
                        HStack(spacing: 8) {
                            Text("\(entry.position)")
                                .font(.system(.caption, design: .monospaced).weight(.black))
                                .foregroundStyle(entry.isPlayer ? palette.warning.color : palette.primary.color)
                                .frame(width: 16, alignment: .trailing)
                            Text(entry.label)
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(entry.isPlayer ? palette.text.color : palette.primary.color)
                                .frame(width: compact ? 62 : 76, alignment: .leading)
                            Text(gapText(entry.gapMeters))
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .foregroundStyle(entry.isPlayer ? palette.warning.color : palette.text.color.opacity(0.9))
                                .frame(width: 54, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(width: compact ? 180 : 212)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Standings")
            .accessibilityValue(accessibilitySummary)
        }
    }

    private var accessibilitySummary: String {
        standings.prefix(5).map { entry in
            "\(entry.position), \(entry.label), \(gapText(entry.gapMeters))"
        }.joined(separator: "; ")
    }

    private func gapText(_ gap: Double) -> String {
        if abs(gap) < 1 { return "--" }
        return gap > 0 ? String(format: "+%.0fm", gap) : String(format: "%.0fm", gap)
    }
}
