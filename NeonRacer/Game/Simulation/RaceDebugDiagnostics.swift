#if DEBUG
import Foundation

struct RaceReplayDiagnosticSnapshot: Equatable, Sendable {
    let seed: UInt64
    let frameCount: Int
    let commandRunCount: Int
    let finalState: RaceState
    let events: [RaceEvent]
}

protocol RaceReplayDiagnosticSink: Sendable {
    func receive(_ snapshot: RaceReplayDiagnosticSnapshot)
}

struct DisabledRaceReplayDiagnosticSink: RaceReplayDiagnosticSink {
    func receive(_ snapshot: RaceReplayDiagnosticSnapshot) {}
}

extension RaceReplayResult {
    func diagnosticSnapshot(for replay: RaceReplay) -> RaceReplayDiagnosticSnapshot {
        RaceReplayDiagnosticSnapshot(
            seed: replay.seed,
            frameCount: frameCount,
            commandRunCount: replay.commandRuns.count,
            finalState: finalState,
            events: events
        )
    }
}
#endif
