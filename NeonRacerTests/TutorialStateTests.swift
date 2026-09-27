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
}

