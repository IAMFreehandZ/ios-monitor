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

// Minimal public interfaces for the initial RED test run.
public enum CounterMath {
    public static func delta(previous: UInt64, current: UInt64, allow32BitWrap: Bool = false) -> UInt64? { nil }
}

public enum TelemetryMath {
    public static func cpuPercent(previous: [CPUTicks]?, current: [CPUTicks]) -> MetricReading {
        MetricReading(status: .unavailable, value: nil, reason: "Not implemented")
    }
    public static func occupiedRAM(capacity: UInt64, freePages: UInt64, pageSize: UInt64) -> MetricReading {
        MetricReading(status: .unavailable, value: nil, reason: "Not implemented")
    }
    public static func byteRate(previous: UInt64?, current: UInt64, elapsed: Double) -> MetricReading {
        MetricReading(status: .unavailable, value: nil, reason: "Not implemented")
    }
}

public struct SessionTimeline: Sendable {
    public init(start: Double, duration: Double) {}
    public func expired(at: Double) -> Bool { false }
    public func remaining(at: Double) -> Double { 0 }
}

public struct ContinuitySummary: Codable, Sendable {
    public var expectedSlots: Int = 0
    public var distinctAttemptedSlots: Int = 0
    public var coveragePercent: Double = 0
    public var maxGapSeconds: Double = 0
    public var p95GapSeconds: Double = 0
    public init(elapsedTimes: [Double], recordingDuration: Double) {}
}
