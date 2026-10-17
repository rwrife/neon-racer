import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct StartRoadTransitionTests {
    @Test
    func launchRoadIsThreeLanesStraightAndLevelThroughTheStartLine() {
        let layout = TrackLayout.initialContent()
        let stageID = layout.routeGraph.startStageID
        let baseElevation = layout.profile(for: stageID).elevationStart
        for distance in stride(from: 0.0, through: TrackLayout.startGridLength, by: 1) {
            let sample = layout.sample(stageID: stageID, distanceInStage: distance)
            #expect(sample.laneCount == 3)
            #expect(sample.roadHalfWidth == 6)
            #expect(sample.curvature == 0)
            #expect(sample.elevation == baseElevation)
            #expect(sample.grade == 0)
        }
    }

    @Test
    func launchBlendHasNoStepInHeightGradeOrCurvature() {
        let layout = TrackLayout.initialContent()
        let stageID = layout.routeGraph.startStageID
        let profile = layout.profile(for: stageID)
        let end = TrackLayout.startGridLength + TrackLayout.startTransitionLength
        for boundary in [TrackLayout.startLineDistance, TrackLayout.startGridLength, 80, end] {
            let before = layout.sample(stageID: stageID, distanceInStage: boundary - 0.001)
            let after = layout.sample(stageID: stageID, distanceInStage: boundary + 0.001)
            #expect(abs(after.elevation - before.elevation) < 0.001)
            #expect(abs(after.grade - before.grade) < 0.0001)
            #expect(abs(after.curvature - before.curvature) < 0.0001)
        }
        for distance in stride(from: TrackLayout.startGridLength + 1, to: end, by: 1) {
            let sample = layout.sample(stageID: stageID, distanceInStage: distance)
            let before = layout.sample(stageID: stageID, distanceInStage: distance - 0.01)
            let after = layout.sample(stageID: stageID, distanceInStage: distance + 0.01)
            #expect(abs(sample.grade - (after.elevation - before.elevation) / 0.02) < 0.00001)
        }
        let merged = layout.sample(stageID: stageID, distanceInStage: end)
        #expect(merged.elevation == profile.elevation(at: end))
        #expect(merged.curvature == profile.curvature(at: end))
        #expect(merged.grade == profile.grade(at: end))
    }
}

struct FinishSequenceTests {
    @Test
    func finishedRaceBeginsAnAutomaticCruiseAtAVisibleSpeed() {
        var cruise = FinishCruiseState()

        cruise.begin(outcome: .finished, currentSpeed: 8, routeDistance: 1_200)
        // Advance in realistic per-frame increments so the per-frame delta clamp
        // (presentation stall protection) does not absorb the whole interval.
        for _ in 0..<20 {
            cruise.advance(deltaTime: 0.1)
        }

        #expect(cruise.isActive)
        #expect(cruise.presentationDistance >= 1_270)
        #expect(cruise.presentationSpeed >= 35)
    }

    @Test
    func finishCruiseClampsExcessiveFrameDeltas() {
        var cruise = FinishCruiseState()
        cruise.begin(outcome: .finished, currentSpeed: 100, routeDistance: 500)

        cruise.advance(deltaTime: 30)

        // A 30-second stall may move the presentation car by at most one clamped frame.
        #expect(cruise.presentationDistance <= 500 + 100 * 0.1 + 0.0001)
    }

    @Test
    func failedRaceDoesNotBeginAFinishCruise() {
        var cruise = FinishCruiseState()

        cruise.begin(outcome: .failed, currentSpeed: 80, routeDistance: 900)
        cruise.advance(deltaTime: 2)

        #expect(!cruise.isActive)
        #expect(cruise.presentationDistance == 900)
        #expect(cruise.presentationSpeed == 0)
    }

    @Test
    func finishCruiseRejectsInvalidFrameDeltas() {
        var cruise = FinishCruiseState()
        cruise.begin(outcome: .finished, currentSpeed: 50, routeDistance: 500)

        cruise.advance(deltaTime: -.infinity)
        cruise.advance(deltaTime: .nan)

        #expect(cruise.presentationDistance == 500)
    }
}

#if !canImport(NeonRacerCore)
import SceneKit

@MainActor
struct FinishRoadExtensionTests {
    @Test
    func launchRoadExtendsBehindTheGridAndStaysContinuousWhenRebased() {
        let layout = TrackLayout.initialContent()
        let mapper = TrackWorldMapper3D(layout: layout)
        var state = RaceState(currentStageID: layout.routeGraph.startStageID)
        mapper.updateRoute(for: state)
        let behind = mapper.frame(atRunDistance: -48)
        let start = mapper.frame(atRunDistance: 0)
        #expect(abs(behind.position.z - start.position.z - 48) < 0.001)
        #expect(behind.roadHalfWidth == 6)
        #expect(behind.laneCount == 3)
        let before = mapper.frame(atRunDistance: 90).position + mapper.originWorldPosition
        state.distance = 90
        mapper.updateRoute(for: state)
        let after = mapper.frame(atRunDistance: 90).position + mapper.originWorldPosition
        #expect((after - before).length < 0.001)
    }

    @Test
    func finishRoadExtrapolatesBeyondTheAuthoredRoute() {
        let layout = TrackLayout(routeGraph: .linearFixture(distance: 200))
        let mapper = TrackWorldMapper3D(layout: layout)
        let state = RaceState(currentStageID: layout.routeGraph.startStageID)
        mapper.updateRoute(for: state)

        let finish = mapper.frame(atRunDistance: 200)
        let beyond = mapper.frame(atRunDistance: 1_200)

        #expect(beyond.runDistance == 1_200)
        #expect(beyond.distanceInStage == 1_200)
        #expect(beyond.position != finish.position)
        // The extension stays level so the cruise road runs flat to the horizon.
        #expect(beyond.pitch == 0)
    }

    @Test
    func presentationDistanceRebasesTheRoadPastTheFinishLine() {
        let layout = TrackLayout(routeGraph: .linearFixture(distance: 200))
        let mapper = TrackWorldMapper3D(layout: layout)
        let state = RaceState(currentStageID: layout.routeGraph.startStageID)
        mapper.updateRoute(for: state)

        mapper.updateRoute(for: state, presentationDistance: 900)

        // After rebasing around the cruise distance, the world origin sits near
        // that point, so frames far ahead remain numerically close to the camera
        // (a rebase that ignored presentationDistance would leave ~1100 here).
        let ahead = mapper.frame(atRunDistance: 1_100)
        #expect(ahead.position.length < 300)
    }
}
#endif
