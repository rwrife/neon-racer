import SwiftUI

struct DebugPerformanceOverlay: View {
    let scene: RaceScene3D
    let settings: GameplaySettings

    @ViewBuilder
    var body: some View {
#if DEBUG
        if Self.isEnabled || settings.debugPerformanceOverlayEnabled {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                if let snapshot = scene.debugPerformanceSnapshot {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(format: "FPS %.0f  %.2f ms  %@", snapshot.framesPerSecond, snapshot.frameTimeMilliseconds, RenderQualityTier(cosmeticTier: snapshot.qualityTier).rawValue.uppercased()))
                        Text("vehicles \(snapshot.activeVehicles)  segments \(snapshot.segmentCount)  nodes \(snapshot.nodeCount)")
                        Text("draw-ish \(snapshot.environmentDrawCount)  env \(snapshot.environmentNodeCount)  pool \(snapshot.activePooledNodes)/\(snapshot.pooledNodeCapacity)")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.cyan.opacity(0.65), lineWidth: 1)
                    }
                    .padding(.top, 58)
                    .padding(.leading, 12)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(30_000)
                }
            }
        }
#else
        EmptyView()
#endif
    }

#if DEBUG
    private static let isEnabled = ProcessInfo.processInfo.arguments.contains("UITestPerfOverlay")
#endif
}
