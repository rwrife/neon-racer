#if DEBUG
import Foundation

struct DebugPerformanceSnapshot {
    let framesPerSecond: Double
    let frameTimeMilliseconds: Double
    let activeVehicles: Int
    let segmentCount: Int
    let nodeCount: Int
    let environmentDrawCount: Int
    let environmentNodeCount: Int
    let qualityTier: CosmeticQualityTier
    let activeEffects: Int
    let activePooledNodes: Int
    let pooledNodeCapacity: Int

    var overlayText: String {
        String(
            format: "FPS %.0f  %.2f ms\nvehicles %d  segments %d  nodes %d\nenv draws %d visible %d quality %@\nfx %d pool %d/%d",
            framesPerSecond,
            frameTimeMilliseconds,
            activeVehicles,
            segmentCount,
            nodeCount,
            environmentDrawCount,
            environmentNodeCount,
            qualityTier.rawValue,
            activeEffects,
            activePooledNodes,
            pooledNodeCapacity
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
        environmentDrawCount: Int,
        environmentNodeCount: Int,
        qualityTier: CosmeticQualityTier,
        activeEffects: Int,
        activePooledNodes: Int,
        pooledNodeCapacity: Int
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
            environmentDrawCount: environmentDrawCount,
            environmentNodeCount: environmentNodeCount,
            qualityTier: qualityTier,
            activeEffects: activeEffects,
            activePooledNodes: activePooledNodes,
            pooledNodeCapacity: pooledNodeCapacity
        )
    }
}
#endif
