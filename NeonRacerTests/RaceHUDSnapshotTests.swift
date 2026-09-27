import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct RaceHUDSnapshotTests {
    @Test
    func snapshotFormatsSimulationValuesAndPrioritizesUrgentWarnings() {
        var state = RaceState(
            timerRemaining: 9.2,
            boostCharge: 0,
            stageProgress: 0.5,
            phase: .racing
        )
        state.speed = 10
        state.scoreInputs.distancePoints = 123.9
        state.lateralPosition = 0.95

        let snapshot = RaceHUDSnapshot(state: state, configuration: .standard)

        #expect(snapshot.speedMPH == 22)
        #expect(snapshot.score == 123)
        #expect(snapshot.timerSeconds == 10)
        #expect(snapshot.stageProgress == 0.5)
        #expect(snapshot.boostFraction == 0)
        #expect(snapshot.warning == .timeCritical)
        #expect(snapshot.routeName == nil)
        #expect(snapshot.comboMultiplier == nil)
    }

    @Test
    func trackerEmitsOneShotEventsAndProgressCheckpoints() {
        var tracker = RaceHUDTracker()
        let state = RaceState(stageProgress: 0.26, phase: .racing)
        let events: [RaceEvent] = [.started(time: 0)]
        let checkpoint = RunEvent.checkpointCrossed(
            time: 2,
            completedStageID: "entry",
            nextStageID: "fork",
            timeAward: 10
        )

        let first = tracker.update(
            state: state,
            events: events,
            runEvents: [checkpoint],
            configuration: .standard
        )
        let repeated = tracker.update(
            state: state,
            events: events,
            runEvents: [checkpoint],
            configuration: .standard
        )

        #expect(first.feedback == .checkpoint(number: 1))
        #expect(repeated.feedback == nil)
    }

    @Test
    func terminalEventsBecomeReadableFeedback() {
        var tracker = RaceHUDTracker()
        var state = RaceState(phase: .finished)

        let finish = tracker.update(
            state: state,
            events: [.finished(time: 42)],
            configuration: .standard
        )
        state.phase = .failed
        let failure = tracker.update(
            state: state,
            events: [.finished(time: 42), .failed(time: 43)],
            configuration: .standard
        )

        #expect(finish.feedback == .finished)
        #expect(failure.feedback == .failed)
    }
}
