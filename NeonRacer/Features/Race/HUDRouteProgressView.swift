import SwiftUI

struct HUDRouteProgressView: View {
    let progress: Double
    let markers: [HUDRouteProgressMarker]
    let palette: PaletteComponents
    let settings: AccessibilitySettings

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(settings.highContrast ? 0.86 : 0.42))
                    .overlay {
                        Capsule()
                            .stroke(palette.primary.color.opacity(settings.highContrast ? 1 : 0.65), lineWidth: settings.highContrast ? 1.5 : 1)
                    }
                    .frame(height: settings.highContrast ? 9 : 7)
                Capsule()
                    .fill(palette.warning.color.opacity(settings.highContrast ? 1 : 0.88))
                    .frame(width: max(7, width * progress.clamped(to: 0...1)), height: settings.highContrast ? 7 : 5)
                ForEach(markers) { marker in
                    markerView(marker)
                        .position(x: marker.position.clamped(to: 0...1) * width, y: 4)
                }
                Circle()
                    .fill(palette.text.color)
                    .frame(width: 9, height: 9)
                    .overlay { Circle().stroke(palette.warning.color, lineWidth: 1) }
                    .position(x: progress.clamped(to: 0...1) * width, y: 4)
                    .accessibilityHidden(true)
            }
            .frame(height: 14)
        }
        .frame(maxWidth: 520, maxHeight: 14)
        .accessibilityLabel("Route progress")
        .accessibilityValue("\(Int((progress.clamped(to: 0...1) * 100).rounded())) percent to finish")
    }

    private func markerView(_ marker: HUDRouteProgressMarker) -> some View {
        ZStack {
            Circle()
                .fill(marker.isReached ? palette.warning.color : Color.black.opacity(0.72))
                .frame(width: marker.kind == .finish ? 12 : 10, height: marker.kind == .finish ? 12 : 10)
            if marker.kind == .fork {
                Rectangle()
                    .fill(palette.secondary.color)
                    .frame(width: 2, height: 12)
            } else if marker.kind == .finish {
                Rectangle()
                    .fill(palette.text.color)
                    .frame(width: 7, height: 2)
            }
        }
        .overlay { Circle().stroke(marker.isReached ? palette.warning.color : palette.primary.color, lineWidth: 1) }
        .accessibilityLabel(marker.label)
        .accessibilityValue(marker.isReached ? "reached" : "ahead")
    }

}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
