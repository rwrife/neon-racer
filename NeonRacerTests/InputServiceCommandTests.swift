import Testing

#if !canImport(NeonRacerCore)
import UIKit
@testable import NeonRacer

@MainActor
struct InputServiceCommandTests {
    @Test
    func touchBoostAloneAcceleratesAndReleasesCleanly() {
        let service = InputService()
        service.setTouchSteering(-0.5)
        service.setTouchAction(.boost, isPressed: true)
        #expect(service.currentCommand.throttle == 1)
        #expect(service.currentCommand.isBoosting)
        #expect(service.currentCommand.steering == -0.5)

        service.setTouchAction(.boost, isPressed: false)
        #expect(service.currentCommand.throttle == 0)
        #expect(!service.currentCommand.isBoosting)
    }

    @Test(arguments: [PlayerAction.boost, .throttle])
    func releasingOneTouchButtonKeepsTheOtherAccelerating(released: PlayerAction) {
        let service = InputService()
        service.setTouchAction(.throttle, isPressed: true)
        service.setTouchAction(.boost, isPressed: true)
        service.setTouchAction(released, isPressed: false)
        #expect(service.currentCommand.throttle == 1)
        #expect(service.currentCommand.isBoosting == (released == .throttle))

        service.setTouchAction(.throttle, isPressed: false)
        service.setTouchAction(.boost, isPressed: false)
        #expect(service.currentCommand == .idle)
    }

    @Test
    func hardwareBoostKeepsIndependentThrottleAndResetClearsTouchBoost() {
        let service = InputService()
        service.simulateKeyboard(.space, isPressed: true)
        #expect(service.currentCommand.throttle == 0)
        service.resetDrivingState()
        service.simulateController(throttle: 0, isBoosting: true)
        #expect(service.currentCommand.throttle == 0)
        service.resetDrivingState()
        service.setTouchAction(.boost, isPressed: true)
        service.resetDrivingState()
        #expect(service.currentCommand == .idle)
    }

    @Test
    func touchKeyboardAndControllerNormalizeDigitalDrivingCommandsEquivalently() {
        let service = InputService()

        service.setTouchAction(.steerLeft, isPressed: true)
        service.setTouchAction(.throttle, isPressed: true)
        service.setTouchAction(.boost, isPressed: true)
        let touch = service.currentCommand

        service.resetDrivingState()
        service.simulateKeyboard(.a, isPressed: true)
        service.simulateKeyboard(.w, isPressed: true)
        service.simulateKeyboard(.space, isPressed: true)
        let keyboard = service.currentCommand

        service.resetDrivingState()
        service.simulateController(steering: -1, throttle: 1, isBoosting: true)
        let controller = service.currentCommand

        #expect(touch == keyboard)
        #expect(keyboard == controller)
        #expect(service.currentInputSource == .controller)
    }

    @Test
    func standardKeyboardAliasesMatchArrowKeyCommands() {
        let service = InputService()

        service.simulateKeyboard(.leftArrow, isPressed: true)
        service.simulateKeyboard(.upArrow, isPressed: true)
        let arrows = service.currentCommand

        service.resetDrivingState()
        service.simulateKeyboard(.a, isPressed: true)
        service.simulateKeyboard(.w, isPressed: true)
        let wasd = service.currentCommand

        #expect(arrows == wasd)
        #expect(arrows.steering == -1)
        #expect(arrows.throttle == 1)
    }

    @Test
    func customKeyboardRemappingProducesSameNormalizedCommand() {
        let service = InputService(
            remapping: InputRemapping(
                keyboard: [
                    .steerLeft: .s,
                    .throttle: .d,
                    .boost: .returnKey
                ]
            )
        )

        service.setTouchAction(.steerLeft, isPressed: true)
        service.setTouchAction(.throttle, isPressed: true)
        service.setTouchAction(.boost, isPressed: true)
        let touch = service.currentCommand

        service.resetDrivingState()
        service.simulateKeyboard(.s, isPressed: true)
        service.simulateKeyboard(.d, isPressed: true)
        service.simulateKeyboard(.returnKey, isPressed: true)

        #expect(service.currentCommand == touch)
    }

    @Test
    func duplicateKeyReportsAndAliasReleaseKeepDrivingState() {
        let service = InputService()

        service.handleKeyboardKey(.leftArrow, isPressed: true)
        service.handleKeyboardKey(.leftArrow, isPressed: true)
        service.handleKeyboardKey(.a, isPressed: true)
        service.handleKeyboardKey(.leftArrow, isPressed: false)
        #expect(service.currentCommand.steering == -1)

        service.handleKeyboardKey(.a, isPressed: false)
        service.handleKeyboardKey(.a, isPressed: false)
        #expect(service.currentCommand.steering == 0)
    }

    @Test
    func escapeDispatchesPauseOnceWithoutCancel() {
        let service = InputService()
        var actions: [PlayerAction] = []
        service.actionHandler = { actions.append($0) }

        service.handleKeyboardKey(.escape, isPressed: true)
        service.handleKeyboardKey(.escape, isPressed: true)
        service.handleKeyboardKey(.escape, isPressed: false)

        #expect(actions == [.pause])
    }

    @Test
    func hardwareKeyUsagesMapToDrivingKeys() {
        #expect(KeyboardKey(hidUsage: .keyboardLeftArrow) == .leftArrow)
        #expect(KeyboardKey(hidUsage: .keyboardW) == .w)
        #expect(KeyboardKey(hidUsage: .keyboardSpacebar) == .space)
        #expect(KeyboardKey(hidUsage: .keyboardEscape) == .escape)
        #expect(KeyboardKey(hidUsage: .keyboardReturnOrEnter) == .returnKey)
        #expect(KeyboardKey(hidUsage: .keyboardQ) == nil)
    }
}
#endif
