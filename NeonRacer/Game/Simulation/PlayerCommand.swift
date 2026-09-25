import Foundation

struct PlayerCommand: Equatable, Sendable {
    var steering: Double
    var throttle: Double
    var brake: Double
    var isBoosting: Bool

    static let idle = PlayerCommand(
        steering: 0,
        throttle: 0,
        brake: 0,
        isBoosting: false
    )
}

