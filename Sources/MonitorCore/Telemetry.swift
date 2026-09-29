import Foundation

public enum ReadingStatus: String, Codable, Sendable { case ok, warmingUp, unavailable, error }

public struct MetricReading: Codable, Equatable, Sendable {
    public var status: ReadingStatus
    public var value: Double?
    public var reason: String?
    public init(status: ReadingStatus, value: Double?, reason: String?) {
        self.status = status; self.value = value; self.reason = reason
    }
}

public struct CPUTicks: Codable, Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var nice: UInt64
    public var idle: UInt64
    public init(user: UInt64, system: UInt64, nice: UInt64, idle: UInt64) {
        self.user = user; self.system = system; self.nice = nice; self.idle = idle
    }
}

public enum CounterMath {
    public static func delta(previous: UInt64, current: UInt64, allow32BitWrap: Bool = false) -> UInt64? {
        if current >= previous { return current - previous }
        let modulus: UInt64 = 1 << 32
        guard allow32BitWrap, previous < modulus, previous >= 3 * modulus / 4, current <= modulus / 4 else { return nil }
        return modulus - previous + current
    }
}

public enum TelemetryMath {
    public static func cpuPercent(previous: [CPUTicks]?, current: [CPUTicks]) -> MetricReading {
        guard let previous, previous.count == current.count, !current.isEmpty else {
            return MetricReading(status: .warmingUp, value: nil, reason: "Waiting for a comparable CPU snapshot")
        }
        var busy = 0.0
        var total = 0.0
        for (a, b) in zip(previous, current) {
            guard let user = CounterMath.delta(previous: a.user, current: b.user, allow32BitWrap: true),
                  let system = CounterMath.delta(previous: a.system, current: b.system, allow32BitWrap: true),
                  let nice = CounterMath.delta(previous: a.nice, current: b.nice, allow32BitWrap: true),
                  let idle = CounterMath.delta(previous: a.idle, current: b.idle, allow32BitWrap: true) else {
                return MetricReading(status: .unavailable, value: nil, reason: "CPU counter reset or unexplained decrease")
            }
            let coreBusy = Double(user) + Double(system) + Double(nice)
            busy += coreBusy
            total += coreBusy + Double(idle)
        }
        guard total > 0 else { return MetricReading(status: .unavailable, value: nil, reason: "CPU total ticks did not advance") }
        return MetricReading(status: .ok, value: 100 * busy / total, reason: nil)
    }
    public static func occupiedRAM(capacity: UInt64, freePages: UInt64, pageSize: UInt64) -> MetricReading {
        let (free, overflow) = freePages.multipliedReportingOverflow(by: pageSize)
        guard capacity > 0, pageSize > 0, !overflow, free <= capacity else {
            return MetricReading(status: .unavailable, value: nil, reason: "Invalid capacity, free pages or page size")
        }
        return MetricReading(status: .ok, value: Double(capacity - free), reason: nil)
    }
    public static func byteRate(previous: UInt64?, current: UInt64, elapsed: Double) -> MetricReading {
        guard let previous else { return MetricReading(status: .warmingUp, value: nil, reason: "Waiting for interface baseline") }
        guard elapsed.isFinite, elapsed > 0, let delta = CounterMath.delta(previous: previous, current: current) else {
            return MetricReading(status: .unavailable, value: nil, reason: "Invalid elapsed time or interface counter reset")
        }
        return MetricReading(status: .ok, value: Double(delta) / elapsed, reason: nil)
    }
}

public struct SessionTimeline: Sendable {
    public let start: Double
    public let duration: Double
    public init(start: Double, duration: Double) { self.start = start; self.duration = max(0, duration) }
    public func expired(at time: Double) -> Bool { time - start >= duration }
    public func remaining(at time: Double) -> Double { max(0, duration - max(0, time - start)) }
}

public struct ContinuitySummary: Codable, Sendable {
    public var expectedSlots: Int = 0
    public var distinctAttemptedSlots: Int = 0
    public var coveragePercent: Double = 0
    public var maxGapSeconds: Double = 0
    public var p95GapSeconds: Double = 0
    public init(elapsedTimes: [Double], recordingDuration: Double) {
        let duration = recordingDuration.isFinite ? max(0, recordingDuration) : 0
        expectedSlots = Int(ceil(duration))
        let times = elapsedTimes.filter { $0.isFinite && $0 >= 0 && $0 < duration }.sorted()
        distinctAttemptedSlots = Set(times.map { Int(floor($0)) }).count
        coveragePercent = expectedSlots > 0 ? 100 * Double(distinctAttemptedSlots) / Double(expectedSlots) : 0
        var gaps: [Double] = []
        var previous = 0.0
        for time in times { if time > previous { gaps.append(time - previous) }; previous = time }
        if duration > previous { gaps.append(duration - previous) }
        let sorted = gaps.sorted()
        maxGapSeconds = sorted.last ?? 0
        p95GapSeconds = sorted.isEmpty ? 0 : sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
    }
}

public final class CallbackGate {
    private var generation: UInt64 = 0
    public init() {}
    public func cancel() { generation &+= 1 }
    public func run(stages: [() -> Void]) {
        generation &+= 1
        let token = generation
        for stage in stages {
            guard token == generation else { return }
            stage()
        }
    }
}
