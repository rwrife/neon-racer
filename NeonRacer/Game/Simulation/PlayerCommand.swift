import Foundation

struct PlayerCommand: Codable, Equatable, Sendable {
    var steering: Double
    var throttle: Double
    var brake: Double
    var isBoosting: Bool

    init(
        steering: Double,
        throttle: Double,
        brake: Double,
        isBoosting: Bool
    ) {
        self.steering = min(max(steering, -1), 1)
        self.throttle = min(max(throttle, 0), 1)
        self.brake = min(max(brake, 0), 1)
        self.isBoosting = isBoosting
    }

    static let idle = PlayerCommand(
        steering: 0,
        throttle: 0,
        brake: 0,
        isBoosting: false
    )

    private enum CodingKeys: String, CodingKey {
        case steering = "s"
        case throttle = "t"
        case brake = "b"
        case isBoosting = "x"
    }

}

enum PlayerAction: String, Codable, CaseIterable, Sendable {
    case steerLeft
    case steerRight
    case throttle
    case brake
    case boost
    case pause
    case confirm
    case cancel
    case menuUp
    case menuDown
    case menuLeft
    case menuRight
}

enum KeyboardKey: String, Codable, CaseIterable, Sendable {
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case space
    case escape
    case returnKey
    case a
    case d
    case w
    case s
    case p
}

struct InputRemapping: Codable, Equatable, Sendable {
    var keyboard: [PlayerAction: KeyboardKey]

    static let standard = InputRemapping(
        keyboard: [
            .steerLeft: .leftArrow,
            .steerRight: .rightArrow,
            .throttle: .upArrow,
            .brake: .downArrow,
            .boost: .space,
            .pause: .escape,
            .confirm: .returnKey,
            .cancel: .escape,
            .menuUp: .upArrow,
            .menuDown: .downArrow,
            .menuLeft: .leftArrow,
            .menuRight: .rightArrow
        ]
    )

    func actions(for key: KeyboardKey) -> Set<PlayerAction> {
        var actions = Set(
            keyboard.compactMap { action, mappedKey in
                mappedKey == key ? action : nil
            }
        )

        guard self == .standard else {
            return actions
        }

        switch key {
        case .a:
            actions.insert(.steerLeft)
        case .d:
            actions.insert(.steerRight)
        case .w:
            actions.insert(.throttle)
        case .s:
            actions.insert(.brake)
        case .p:
            actions.insert(.pause)
        case .leftArrow, .rightArrow, .upArrow, .downArrow, .space, .escape, .returnKey:
            break
        }

        return actions
    }
}
