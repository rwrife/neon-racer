#if canImport(OSLog)
import OSLog
#endif

enum PerformanceInterval {
    case frame
    case simulation
    case roadProjection
    case effects

    fileprivate var name: StaticString {
        switch self {
        case .frame: "Frame"
        case .simulation: "Simulation"
        case .roadProjection: "Road Projection"
        case .effects: "Effects"
        }
    }
}

enum PerformanceInstrumentation {
#if DEBUG && os(iOS) && canImport(OSLog)
    typealias IntervalID = OSSignpostID
    private static let log = OSLog(subsystem: "com.infinityball.neonracer", category: .pointsOfInterest)

    static func begin(_ interval: PerformanceInterval) -> IntervalID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: interval.name, signpostID: id)
        return id
    }

    static func end(_ interval: PerformanceInterval, _ id: IntervalID) {
        os_signpost(.end, log: log, name: interval.name, signpostID: id)
    }
#else
    struct IntervalID {}

    static func begin(_ interval: PerformanceInterval) -> IntervalID {
        IntervalID()
    }

    static func end(_ interval: PerformanceInterval, _ id: IntervalID) {}
#endif
}
