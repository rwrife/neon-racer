#if DEBUG
import Foundation

struct DebugPerformanceSnapshot {
    let framesPerSecond: Double
    let frameTimeMilliseconds: Double
    let activeVehicles: Int
    let segmentCount: Int
    let nodeCount: Int
    let qualityTier: CosmeticQualityTier

    var overlayText: String {
        String(
            format: "FPS %.0f  %.2f ms\nvehicles %d  segments %d  nodes %d\nquality %@",
            framesPerSecond,
            frameTimeMilliseconds,
            activeVehicles,
            segmentCount,
            nodeCount,
            qualityTier.rawValue
        )
    }
}

final class DebugPerformanceMetrics {
    private var smoothedFrameTime: TimeInterval = 1.0 / 60.0

    func record(
        frameDelta: TimeInterval,
        activeVehicles: Int,
        segmentCount: Int,
        nodeCount: Int,
        qualityTier: CosmeticQualityTier
    ) -> DebugPerformanceSnapshot {
        if frameDelta > 0 {
            smoothedFrameTime += (frameDelta - smoothedFrameTime) * 0.1
        }

        return DebugPerformanceSnapshot(
            framesPerSecond: 1 / smoothedFrameTime,
            frameTimeMilliseconds: smoothedFrameTime * 1_000,
            activeVehicles: activeVehicles,
            segmentCount: segmentCount,
            nodeCount: nodeCount,
            qualityTier: qualityTier
        )
    }
}
#endif
