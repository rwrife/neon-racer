import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

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
