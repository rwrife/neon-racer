import Foundation

enum DrivingInputMethod: String, Codable, CaseIterable, Equatable, Sendable {
    case touch
    case controller
    case keyboard

    var displayName: String {
        switch self {
        case .touch: "Touch"
        case .controller: "Controller"
        case .keyboard: "Keyboard"
        }
    }
}

struct TutorialGlyph: Equatable, Sendable {
    let symbolName: String
    let accessibilityLabel: String
}

struct TutorialPromptContent: Equatable, Sendable {
    let title: String
    let instruction: String
    let glyph: TutorialGlyph
}

enum TutorialPromptLibrary {
    static func content(
        for step: TutorialStep,
        inputMethod: DrivingInputMethod
    ) -> TutorialPromptContent {
        switch step {
        case .steering:
            TutorialPromptContent(
                title: "Find your line",
                instruction: steeringInstruction(for: inputMethod),
                glyph: steeringGlyph(for: inputMethod)
            )
        case .brakingAndRecovery:
            TutorialPromptContent(
                title: "Recover cleanly",
                instruction: brakingInstruction(for: inputMethod),
                glyph: brakingGlyph(for: inputMethod)
            )
        case .boost:
            TutorialPromptContent(
                title: "Burn boost",
                instruction: boostInstruction(for: inputMethod),
                glyph: boostGlyph(for: inputMethod)
            )
        case .trafficRisk:
            TutorialPromptContent(
                title: "Read the traffic",
                instruction: "Lift early and pass through open space. A clean line is faster than a collision.",
                glyph: TutorialGlyph(symbolName: "car.2.fill", accessibilityLabel: "Traffic")
            )
        case .checkpointTimer:
            TutorialPromptContent(
                title: "Beat the clock",
                instruction: "Reach each checkpoint before the timer expires. Checkpoints add time to the run.",
                glyph: TutorialGlyph(symbolName: "timer", accessibilityLabel: "Checkpoint timer")
            )
        case .routeFork:
            TutorialPromptContent(
                title: "Choose your route",
                instruction: steeringInstruction(for: inputMethod) + " Commit to a side before the fork.",
                glyph: TutorialGlyph(symbolName: "arrow.triangle.branch", accessibilityLabel: "Route fork")
            )
        }
    }

    private static func steeringInstruction(for inputMethod: DrivingInputMethod) -> String {
        switch inputMethod {
        case .touch: "Drag left or right to steer."
        case .controller: "Use the left stick to steer."
        case .keyboard: "Use A and D or the arrow keys to steer."
        }
    }

    private static func brakingInstruction(for inputMethod: DrivingInputMethod) -> String {
        switch inputMethod {
        case .touch: "Hold the brake control, then steer back toward the road."
        case .controller: "Hold the left trigger, then steer back toward the road."
        case .keyboard: "Hold S or the down arrow, then steer back toward the road."
        }
    }

    private static func boostInstruction(for inputMethod: DrivingInputMethod) -> String {
        switch inputMethod {
        case .touch: "Press and hold the boost control on a clear straight."
        case .controller: "Hold the south face button on a clear straight."
        case .keyboard: "Hold Space on a clear straight."
        }
    }

    private static func steeringGlyph(for inputMethod: DrivingInputMethod) -> TutorialGlyph {
        switch inputMethod {
        case .touch:
            TutorialGlyph(symbolName: "hand.draw.fill", accessibilityLabel: "Drag gesture")
        case .controller:
            TutorialGlyph(symbolName: "l.joystick.fill", accessibilityLabel: "Left stick")
        case .keyboard:
            TutorialGlyph(symbolName: "arrow.left.arrow.right", accessibilityLabel: "Left and right keys")
        }
    }

    private static func brakingGlyph(for inputMethod: DrivingInputMethod) -> TutorialGlyph {
        switch inputMethod {
        case .touch:
            TutorialGlyph(symbolName: "hand.tap.fill", accessibilityLabel: "Brake control")
        case .controller:
            TutorialGlyph(symbolName: "l.rectangle.roundedbottom.fill", accessibilityLabel: "Left trigger")
        case .keyboard:
            TutorialGlyph(symbolName: "arrow.down.square.fill", accessibilityLabel: "Down key")
        }
    }

    private static func boostGlyph(for inputMethod: DrivingInputMethod) -> TutorialGlyph {
        switch inputMethod {
        case .touch:
            TutorialGlyph(symbolName: "bolt.circle.fill", accessibilityLabel: "Boost control")
        case .controller:
            TutorialGlyph(symbolName: "a.circle.fill", accessibilityLabel: "South face button")
        case .keyboard:
            TutorialGlyph(symbolName: "space", accessibilityLabel: "Space bar")
        }
    }
}

