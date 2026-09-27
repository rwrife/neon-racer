import Testing

#if !canImport(NeonRacerCore)
@testable import NeonRacer

@MainActor
struct InputServiceCommandTests {
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
}
#endif
