import Combine
import GameController

@MainActor
final class InputService: NSObject, ObservableObject {
    @Published private(set) var inputMethod = DrivingInputMethod.touch
    @Published private(set) var isControllerConnected = false

    var actionHandler: (PlayerAction) -> Void = { _ in }
    var controllerDisconnectHandler: () -> Void = {}

    private var states: [DrivingInputMethod: InputState] = [
        .touch: InputState(),
        .controller: InputState(),
        .keyboard: InputState()
    ]
    private var activeController: GCController?
    private var remapping: InputRemapping
    private var isStarted = false

    init(
        initialInputMethod: DrivingInputMethod = .touch,
        remapping: InputRemapping = .standard
    ) {
        inputMethod = initialInputMethod
        self.remapping = remapping
        super.init()
    }

    var currentCommand: PlayerCommand {
        states[inputMethod, default: InputState()].command
    }

    var currentInputSource: DrivingInputMethod {
        inputMethod
    }

    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(controllerConnectedNotification(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(controllerDisconnectedNotification(_:)),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardConnectedNotification(_:)),
            name: .GCKeyboardDidConnect,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardDisconnectedNotification(_:)),
            name: .GCKeyboardDidDisconnect,
            object: nil
        )

        configureKeyboard()
        if let controller = GCController.controllers().first {
            controllerDidConnect(controller)
        } else {
            GCController.startWirelessControllerDiscovery()
        }
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        GCController.stopWirelessControllerDiscovery()
        clearHandlers(on: activeController)
        activeController = nil
        isControllerConnected = false
        states = [
            .touch: InputState(),
            .controller: InputState(),
            .keyboard: InputState()
        ]
        inputMethod = .touch
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
        isStarted = false
    }

    func resetDrivingState() {
        for method in DrivingInputMethod.allCases {
            states[method] = InputState()
        }
    }

    func updateRemapping(_ remapping: InputRemapping) {
        self.remapping = remapping
        states[.keyboard] = InputState()
    }

    func setTouchSteering(_ value: Double) {
        update(.touch) { $0.steering = value }
    }

    func setTouchAction(_ action: PlayerAction, isPressed: Bool) {
        updateDigitalAction(action, isPressed: isPressed, source: .touch)
    }

    @objc
    private func controllerConnectedNotification(_ notification: Notification) {
        guard let controller = notification.object as? GCController else {
            return
        }
        controllerDidConnect(controller)
    }

    @objc
    private func controllerDisconnectedNotification(_ notification: Notification) {
        guard let controller = notification.object as? GCController else {
            return
        }
        controllerDidDisconnect(controller)
    }

    @objc
    private func keyboardConnectedNotification(_ notification: Notification) {
        configureKeyboard(notification.object as? GCKeyboard)
    }

    @objc
    private func keyboardDisconnectedNotification(_ notification: Notification) {
        (notification.object as? GCKeyboard)?.keyboardInput?.keyChangedHandler = nil
        states[.keyboard] = InputState()
        if inputMethod == .keyboard {
            inputMethod = .touch
        }
    }

    private func controllerDidConnect(_ controller: GCController) {
        if let activeController {
            guard activeController.extendedGamepad == nil, controller.extendedGamepad != nil else {
                isControllerConnected = true
                return
            }
            clearHandlers(on: activeController)
        }
        guard activeController == nil || controller.extendedGamepad != nil else {
            isControllerConnected = true
            return
        }
        activeController = controller
        isControllerConnected = true
        installHandlers(on: controller)
        GCController.stopWirelessControllerDiscovery()
    }

    private func controllerDidDisconnect(_ controller: GCController) {
        guard controller === activeController else {
            isControllerConnected = !GCController.controllers().isEmpty
            return
        }

        clearHandlers(on: controller)
        let shouldPauseForDisconnect = inputMethod == .controller
            && states[.controller, default: InputState()].hasActiveDrivingInput
        states[.controller] = InputState()
        activeController = nil

        if let replacement = GCController.controllers().first(where: { $0 !== controller }) {
            controllerDidConnect(replacement)
        } else {
            isControllerConnected = false
            if inputMethod == .controller {
                inputMethod = .touch
            }
            if shouldPauseForDisconnect {
                actionHandler(.pause)
            }
            controllerDisconnectHandler()
            GCController.startWirelessControllerDiscovery()
        }
    }

    private func installHandlers(on controller: GCController) {
        if let gamepad = controller.extendedGamepad {
            gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, _ in
                Task { @MainActor in
                    self?.update(.controller) { $0.steering = Double(x) }
                }
            }
            gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
                Task { @MainActor in
                    self?.updateControllerDpad(x: Double(x), y: Double(y))
                }
            }
            gamepad.rightTrigger.valueChangedHandler = { [weak self] _, value, _ in
                Task { @MainActor in
                    self?.update(.controller) { $0.throttle = Double(value) }
                }
            }
            gamepad.leftTrigger.valueChangedHandler = { [weak self] _, value, _ in
                Task { @MainActor in
                    self?.update(.controller) { $0.brake = Double(value) }
                }
            }
            bind(gamepad.buttonA, to: .confirm, drivingAction: .boost)
            bind(gamepad.buttonB, to: .cancel, drivingAction: .brake)
            bind(gamepad.buttonX, to: .boost, drivingAction: .boost)
            bind(gamepad.buttonMenu, to: .pause)
        } else if let gamepad = controller.microGamepad {
            gamepad.allowsRotation = true
            gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
                Task { @MainActor in
                    self?.updateControllerDpad(x: Double(x), y: Double(y))
                }
            }
            bind(gamepad.buttonA, to: .confirm, drivingAction: .throttle)
            bind(gamepad.buttonX, to: .boost, drivingAction: .boost)
            bind(gamepad.buttonMenu, to: .pause)
        }
    }

    private func clearHandlers(on controller: GCController?) {
        controller?.extendedGamepad?.leftThumbstick.valueChangedHandler = nil
        controller?.extendedGamepad?.dpad.valueChangedHandler = nil
        controller?.extendedGamepad?.rightTrigger.valueChangedHandler = nil
        controller?.extendedGamepad?.leftTrigger.valueChangedHandler = nil
        controller?.extendedGamepad?.buttonA.pressedChangedHandler = nil
        controller?.extendedGamepad?.buttonB.pressedChangedHandler = nil
        controller?.extendedGamepad?.buttonX.pressedChangedHandler = nil
        controller?.extendedGamepad?.buttonMenu.pressedChangedHandler = nil
        controller?.microGamepad?.dpad.valueChangedHandler = nil
        controller?.microGamepad?.buttonA.pressedChangedHandler = nil
        controller?.microGamepad?.buttonX.pressedChangedHandler = nil
        controller?.microGamepad?.buttonMenu.pressedChangedHandler = nil
    }

    private func bind(
        _ button: GCControllerButtonInput?,
        to action: PlayerAction,
        drivingAction: PlayerAction? = nil
    ) {
        button?.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.inputMethod = .controller
                if let drivingAction {
                    self.updateDigitalAction(
                        drivingAction,
                        isPressed: pressed,
                        source: .controller
                    )
                }
                if pressed {
                    self.actionHandler(action)
                }
            }
        }
    }

    private func configureKeyboard(_ keyboard: GCKeyboard? = GCKeyboard.coalesced) {
        keyboard?.keyboardInput?.keyChangedHandler = {
            [weak self] _, _, keyCode, pressed in
            Task { @MainActor in
                guard let self, let key = KeyboardKey(keyCode) else {
                    return
                }
                for action in self.remapping.actions(for: key) {
                    self.updateDigitalAction(action, isPressed: pressed, source: .keyboard)
                    if pressed && action.isDiscrete {
                        self.actionHandler(action)
                    }
                }
            }
        }
    }

    private func updateDigitalAction(
        _ action: PlayerAction,
        isPressed: Bool,
        source: DrivingInputMethod
    ) {
        update(source) { state in
            switch action {
            case .steerLeft:
                state.steerLeft = isPressed
            case .steerRight:
                state.steerRight = isPressed
            case .throttle:
                state.throttle = isPressed ? 1 : 0
            case .brake:
                state.brake = isPressed ? 1 : 0
            case .boost:
                state.isBoosting = isPressed
            case .menuUp, .menuDown, .menuLeft, .menuRight, .pause, .confirm, .cancel:
                break
            }
        }
    }

    private func updateControllerDpad(x: Double, y: Double) {
        let previousX = states[.controller, default: InputState()].menuX
        let previousY = states[.controller, default: InputState()].menuY
        update(.controller) {
            $0.steering = x
            $0.menuX = x
            $0.menuY = y
        }

        if x <= -0.5, previousX > -0.5 {
            actionHandler(.menuLeft)
        } else if x >= 0.5, previousX < 0.5 {
            actionHandler(.menuRight)
        }
        if y <= -0.5, previousY > -0.5 {
            actionHandler(.menuDown)
        } else if y >= 0.5, previousY < 0.5 {
            actionHandler(.menuUp)
        }
    }

    private func update(
        _ source: DrivingInputMethod,
        _ update: (inout InputState) -> Void
    ) {
        update(&states[source, default: InputState()])
        inputMethod = source
    }
}

#if DEBUG
extension InputService {
    func simulateKeyboard(_ key: KeyboardKey, isPressed: Bool) {
        for action in remapping.actions(for: key) {
            updateDigitalAction(action, isPressed: isPressed, source: .keyboard)
            if isPressed && action.isDiscrete {
                actionHandler(action)
            }
        }
    }

    func simulateController(
        steering: Double? = nil,
        throttle: Double? = nil,
        brake: Double? = nil,
        isBoosting: Bool? = nil
    ) {
        update(.controller) { state in
            if let steering {
                state.steering = steering
                state.menuX = steering
            }
            if let throttle {
                state.throttle = throttle
            }
            if let brake {
                state.brake = brake
            }
            if let isBoosting {
                state.isBoosting = isBoosting
            }
        }
    }

    func simulateControllerDpad(x: Double, y: Double) {
        updateControllerDpad(x: x, y: y)
    }
}
#endif

struct InputPromptGlyphs: Equatable, Sendable {
    let sourceSystemImage: String
    let navigate: String
    let confirm: String
    let cancel: String
    let pause: String
}

extension DrivingInputMethod {
    var menuPromptGlyphs: InputPromptGlyphs {
        switch self {
        case .touch:
            InputPromptGlyphs(
                sourceSystemImage: "hand.tap",
                navigate: "Tap",
                confirm: "Tap",
                cancel: "Back",
                pause: "Pause"
            )
        case .controller:
            InputPromptGlyphs(
                sourceSystemImage: "gamecontroller",
                navigate: "D-Pad/Stick",
                confirm: "A",
                cancel: "B",
                pause: "Menu"
            )
        case .keyboard:
            InputPromptGlyphs(
                sourceSystemImage: "keyboard",
                navigate: "Arrows/WASD",
                confirm: "Return",
                cancel: "Esc",
                pause: "Esc"
            )
        }
    }
}

private struct InputState {
    var steering = 0.0
    var throttle = 0.0
    var brake = 0.0
    var isBoosting = false
    var steerLeft = false
    var steerRight = false
    var menuX = 0.0
    var menuY = 0.0

    var command: PlayerCommand {
        let digitalSteering = (steerLeft ? -1.0 : 0) + (steerRight ? 1.0 : 0)
        return PlayerCommand(
            steering: digitalSteering == 0 ? steering : digitalSteering,
            throttle: throttle,
            brake: brake,
            isBoosting: isBoosting
        )
    }

    var hasActiveDrivingInput: Bool {
        command != .idle
    }
}

private extension PlayerAction {
    var isDiscrete: Bool {
        switch self {
        case .pause, .confirm, .cancel, .menuUp, .menuDown, .menuLeft, .menuRight:
            true
        case .steerLeft, .steerRight, .throttle, .brake, .boost:
            false
        }
    }
}

private extension KeyboardKey {
    init?(_ keyCode: GCKeyCode) {
        switch keyCode {
        case .leftArrow: self = .leftArrow
        case .rightArrow: self = .rightArrow
        case .upArrow: self = .upArrow
        case .downArrow: self = .downArrow
        case .spacebar: self = .space
        case .escape: self = .escape
        case .returnOrEnter: self = .returnKey
        case .keyA: self = .a
        case .keyD: self = .d
        case .keyW: self = .w
        case .keyS: self = .s
        default: return nil
        }
    }
}
