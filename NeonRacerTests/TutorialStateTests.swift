import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct TutorialStateTests {
    @Test
    func firstRunStartsAtSteeringAndCompletesInOrder() {
        var session = TutorialSession()

        session.startIfNeeded()
        #expect(session.currentStep == .steering)

        for expectedStep in TutorialStep.allCases {
            #expect(session.currentStep == expectedStep)
            session.advance()
        }

        #expect(session.progress == .completed)
        #expect(session.isPresenting == false)
    }

    @Test
    func completedTutorialDoesNotRestartUnlessReplayed() {
        var session = TutorialSession(progress: .completed)

        session.startIfNeeded()
        #expect(session.progress == .completed)

        session.replay()
        #expect(session.progress.status == .inProgress)
        #expect(session.currentStep == .steering)
    }

    @Test
    func skipAndResetHaveDistinctPersistentStates() {
        var session = TutorialSession()
        session.startIfNeeded()
        session.skip()

        #expect(session.progress.status == .skipped)
        #expect(session.currentStep == nil)

        session.reset()
        #expect(session.progress == .notStarted)
    }

    @Test
    func promptCopyAndGlyphFollowInputMethod() {
        let touch = TutorialPromptLibrary.content(for: .boost, inputMethod: .touch)
        let controller = TutorialPromptLibrary.content(for: .boost, inputMethod: .controller)
        let keyboard = TutorialPromptLibrary.content(for: .boost, inputMethod: .keyboard)

        #expect(touch.instruction.contains("boost control"))
        #expect(controller.instruction.contains("face button"))
        #expect(keyboard.instruction.contains("Space"))
        #expect(Set([touch.glyph.symbolName, controller.glyph.symbolName, keyboard.glyph.symbolName]).count == 3)
    }

    @Test
    func stepsAdvanceOnlyWhenMatchingDrivingActionIsObserved() {
        var session = TutorialSession()
        session.startIfNeeded()

        let idleDidAdvance = session.observe(.init(command: .idle, phase: .racing))
        #expect(idleDidAdvance == false)
        #expect(session.currentStep == .steering)

        let steeringDidAdvance = session.observe(.init(
            command: PlayerCommand(steering: 0.6, throttle: 1, brake: 0, isBoosting: false),
            phase: .racing,
            speedKPH: 36
        ))
        #expect(steeringDidAdvance)
        #expect(session.currentStep == .brakingAndRecovery)

        let brakeDidAdvance = session.observe(.init(
            command: PlayerCommand(steering: 0, throttle: 0, brake: 1, isBoosting: false),
            phase: .racing,
            speedKPH: 64
        ))
        #expect(brakeDidAdvance)
        #expect(session.currentStep == .boost)

        let boostDidAdvance = session.observe(.init(
            command: PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: true),
            phase: .racing,
            speedKPH: 110,
            isBoostActive: true
        ))
        #expect(boostDidAdvance)
        #expect(session.currentStep == .trafficRisk)

        let nearMissDidAdvance = session.observe(.init(
            phase: .racing,
            feedback: .nearMiss(points: 120)
        ))
        #expect(nearMissDidAdvance)
        #expect(session.currentStep == .checkpointTimer)

        let checkpointDidAdvance = session.observe(.init(
            phase: .checkpoint,
            feedback: .checkpointBonus(number: 1, seconds: 12)
        ))
        #expect(checkpointDidAdvance)
        #expect(session.currentStep == .routeFork)

        let forkDidAdvance = session.observe(.init(
            phase: .racing,
            feedback: .routeChosen("SKYWAY")
        ))
        #expect(forkDidAdvance)
        #expect(session.progress == .completed)
    }

    @Test
    func checkpointCanAdvanceFromReachedRouteMarker() {
        var session = TutorialSession(progress: .init(status: .inProgress, currentStep: .checkpointTimer))
        let marker = HUDRouteProgressMarker(
            id: "checkpoint-1",
            kind: .checkpoint,
            position: 0.36,
            label: "CP1",
            isReached: true
        )

        let markerDidAdvance = session.observe(.init(
            phase: .racing,
            routeProgressMarkers: [marker]
        ))
        #expect(markerDidAdvance)
        #expect(session.currentStep == .routeFork)
    }

    @Test
    func speedControlStepAcceptsThrottleOrBrake() {
        var throttleSession = TutorialSession(
            progress: .init(status: .inProgress, currentStep: .brakingAndRecovery)
        )
        let throttleDidAdvance = throttleSession.observe(.init(
            command: PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: false),
            phase: .racing
        ))
        #expect(throttleDidAdvance)

        var brakeSession = TutorialSession(
            progress: .init(status: .inProgress, currentStep: .brakingAndRecovery)
        )
        let brakeDidAdvance = brakeSession.observe(.init(
            command: PlayerCommand(steering: 0, throttle: 0, brake: 1, isBoosting: false),
            phase: .racing,
            warning: .roadEdge
        ))
        #expect(brakeDidAdvance)
    }
}
