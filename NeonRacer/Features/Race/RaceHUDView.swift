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

    private var reduceMotion: Bool {
        settings.resolvedReduceMotion(systemReduceMotion: systemReduceMotion)
    }

    private var reduceGlow: Bool {
        settings.reduceFlashes || reduceMotion
    }

    private var usesCompactLayout: Bool {
        dynamicTypeSize.isAccessibilitySize || settings.largeHUD
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = usesCompactLayout || proxy.size.width < 1_080
            ZStack(alignment: .top) {
                topHUD(compact: compact)
                    .padding(.horizontal, compact ? 10 : 16)
                    .padding(.top, compact ? 8 : 10)

                centerLayer(compact: compact, height: proxy.size.height)

                bottomLayer(width: proxy.size.width, compact: compact)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaPadding(.horizontal, 12)
        .safeAreaPadding(.vertical, 8)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Race status")
    }

    private func topHUD(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: compact ? 12 : 18) {
            VStack(alignment: .leading, spacing: compact ? 7 : 9) {
                HUDTimeCluster(
                    snapshot: snapshot,
                    feedback: feedback,
                    palette: palette,
                    settings: settings,
                    compact: compact
                )
                HUDMinimapPanel(
                    snapshot: snapshot,
                    palette: palette,
                    settings: settings,
                    compact: compact
                )
            }
            .frame(width: compact ? 156 : 182, alignment: .leading)

            Spacer(minLength: compact ? 20 : 44)

            HUDScoreStageCluster(
                snapshot: snapshot,
                palette: palette,
                settings: settings,
                reduceGlow: reduceGlow,
                compact: compact
            )
            .frame(maxWidth: compact ? 500 : 640, alignment: .center)

            Spacer(minLength: compact ? 20 : 44)

            HUDSpeedCluster(
                snapshot: snapshot,
                palette: palette,
                settings: settings,
                reduceGlow: reduceGlow,
                compact: compact
            )
            .padding(.trailing, compact ? 52 : 58)
        }
    }

    @ViewBuilder
    private func centerLayer(compact: Bool, height: CGFloat) -> some View {
        if snapshot.countdownSeconds != nil {
            HUDCountdownOverlay(
                snapshot: snapshot,
                palette: palette,
                settings: settings,
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .transition(centerTransition)
        } else if let feedback {
            HUDCalloutView(
                feedback: feedback,
                palette: palette,
                settings: settings,
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, max(compact ? 74 : 82, height * 0.17))
            .transition(centerTransition)
        } else if let warning = snapshot.warning {
            HUDCalloutView(
                warning: warning,
                palette: palette,
                settings: settings,
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, max(compact ? 74 : 82, height * 0.17))
        }
    }

    private func bottomLayer(width: CGFloat, compact: Bool) -> some View {
        HUDRouteProgressView(
            progress: snapshot.routeProgressFraction,
            markers: snapshot.routeProgressMarkers,
            palette: palette,
            settings: settings
        )
        .padding(.horizontal, horizontalRoutePadding(width: width, compact: compact))
        .padding(.bottom, compact ? 8 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func horizontalRoutePadding(width: CGFloat, compact: Bool) -> CGFloat {
        let minimumControlClearance: CGFloat = compact ? 210 : 250
        let proportional = width * (compact ? 0.21 : 0.23)
        return max(minimumControlClearance, proportional)
    }

    private var centerTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .scale(scale: 0.9).combined(with: .opacity)
    }
}
