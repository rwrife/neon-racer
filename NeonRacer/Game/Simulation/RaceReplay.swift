import Foundation

enum RaceReplayError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case invalidFrameDelta
    case invalidRepeatCount
    case invalidCommand
    case invalidGameplayEventFrame(Int)
    case eventMismatch(expected: [RaceEvent], actual: [RaceEvent])
}

struct RecordedGameplayScoreEvent: Codable, Equatable, Sendable {
    let frameIndex: Int
    let event: GameplayScoreEvent

    init(frameIndex: Int, event: GameplayScoreEvent) throws {
        guard frameIndex >= 0 else {
            throw RaceReplayError.invalidGameplayEventFrame(frameIndex)
        }
        self.frameIndex = frameIndex
        self.event = event
    }
}

struct RaceCommandRun: Codable, Equatable, Sendable {
    let frameDelta: TimeInterval
    let repeatCount: Int
    let command: PlayerCommand

    init(frameDelta: TimeInterval, repeatCount: Int, command: PlayerCommand) throws {
        guard frameDelta.isFinite, frameDelta >= 0 else {
            throw RaceReplayError.invalidFrameDelta
        }
        guard repeatCount > 0 else {
            throw RaceReplayError.invalidRepeatCount
        }
        guard command.steering.isFinite,
              command.throttle.isFinite,
              command.brake.isFinite else {
            throw RaceReplayError.invalidCommand
        }
        self.frameDelta = frameDelta
        self.repeatCount = repeatCount
        self.command = command
    }

    private enum CodingKeys: String, CodingKey {
        case frameDelta = "d"
        case repeatCount = "n"
        case command = "c"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            frameDelta: container.decode(TimeInterval.self, forKey: .frameDelta),
            repeatCount: container.decode(Int.self, forKey: .repeatCount),
            command: container.decode(PlayerCommand.self, forKey: .command)
        )
    }
}

struct RaceReplay: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let seed: UInt64
    let commandRuns: [RaceCommandRun]
    let events: [RaceEvent]
    let gameplayEvents: [RecordedGameplayScoreEvent]

    init(
        seed: UInt64,
        commandRuns: [RaceCommandRun],
        events: [RaceEvent] = [],
        gameplayEvents: [RecordedGameplayScoreEvent] = []
    ) {
        self.seed = seed
        self.commandRuns = commandRuns
        self.events = events
        self.gameplayEvents = gameplayEvents
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case seed = "s"
        case commandRuns = "r"
        case events = "e"
        case gameplayEvents = "g"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw RaceReplayError.unsupportedVersion(version)
        }
        seed = try container.decode(UInt64.self, forKey: .seed)
        commandRuns = try container.decode([RaceCommandRun].self, forKey: .commandRuns)
        events = try container.decodeIfPresent([RaceEvent].self, forKey: .events) ?? []
        gameplayEvents =
            try container.decodeIfPresent([RecordedGameplayScoreEvent].self, forKey: .gameplayEvents)
            ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(seed, forKey: .seed)
        try container.encode(commandRuns, forKey: .commandRuns)
        if !events.isEmpty {
            try container.encode(events, forKey: .events)
        }
        if !gameplayEvents.isEmpty {
            try container.encode(gameplayEvents, forKey: .gameplayEvents)
        }
    }
}

struct RaceReplayRecorder: Sendable {
    let seed: UInt64
    private(set) var commandRuns: [RaceCommandRun] = []

    init(seed: UInt64) {
        self.seed = seed
    }

    mutating func record(frameDelta: TimeInterval, command: PlayerCommand) throws {
        let run = try RaceCommandRun(
            frameDelta: frameDelta,
            repeatCount: 1,
            command: command
        )

        if let previous = commandRuns.last,
           previous.frameDelta == frameDelta,
           previous.command == command {
            commandRuns[commandRuns.count - 1] = try RaceCommandRun(
                frameDelta: frameDelta,
                repeatCount: previous.repeatCount + 1,
                command: command
            )
        } else {
            commandRuns.append(run)
        }
    }

    func finish(
        events: [RaceEvent] = [],
        gameplayEvents: [RecordedGameplayScoreEvent] = []
    ) -> RaceReplay {
        RaceReplay(
            seed: seed,
            commandRuns: commandRuns,
            events: events,
            gameplayEvents: gameplayEvents
        )
    }
}

struct RaceReplayResult: Equatable, Sendable {
    let finalState: RaceState
    let events: [RaceEvent]
    let scoreEvents: [ScoreEvent]
    let frameCount: Int
}

enum RaceReplayExecutor {
    static func run(
        _ replay: RaceReplay,
        configuration: RaceConfiguration = .standard,
        verifyEvents: Bool = true
    ) throws -> RaceReplayResult {
        var simulation = RaceSimulation(configuration: configuration, seed: replay.seed)
        var frameCount = 0
        var gameplayEventIndex = 0

        for run in replay.commandRuns {
            for _ in 0..<run.repeatCount {
                simulation.advance(frameDelta: run.frameDelta, command: run.command)
                while gameplayEventIndex < replay.gameplayEvents.count,
                      replay.gameplayEvents[gameplayEventIndex].frameIndex == frameCount {
                    simulation.ingest(replay.gameplayEvents[gameplayEventIndex].event)
                    gameplayEventIndex += 1
                }
                frameCount += 1
            }
        }
        if gameplayEventIndex != replay.gameplayEvents.count {
            throw RaceReplayError.invalidGameplayEventFrame(
                replay.gameplayEvents[gameplayEventIndex].frameIndex
            )
        }

        if verifyEvents, !replay.events.isEmpty, replay.events != simulation.events {
            throw RaceReplayError.eventMismatch(
                expected: replay.events,
                actual: simulation.events
            )
        }

        return RaceReplayResult(
            finalState: simulation.state,
            events: simulation.events,
            scoreEvents: simulation.scoreEvents,
            frameCount: frameCount
        )
    }
}
