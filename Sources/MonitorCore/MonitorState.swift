import Foundation

// Compiling scaffolds for the first failing behavioral test run.
public struct MonitorPreferences: Codable, Equatable, Sendable {
    public var durationMinutes: Int
    public var locationEnabled: Bool
    public var audioEnabled: Bool

    public init(durationMinutes: Int = 15, locationEnabled: Bool = false, audioEnabled: Bool = true) {
        self.durationMinutes = durationMinutes
        self.locationEnabled = locationEnabled
        self.audioEnabled = audioEnabled
    }

    public static func load(_ data: Data?) -> MonitorPreferences { MonitorPreferences() }
}

public enum TrendMetric: Sendable { case cpu, ram }

public struct TrendPoint: Equatable, Sendable, Identifiable {
    public var id: Int
    public var elapsedSeconds: Double
    public var cpuPercent: Double?
    public var ramBytes: Double?

    public init(id: Int, elapsedSeconds: Double, cpuPercent: Double?, ramBytes: Double?) {
        self.id = id; self.elapsedSeconds = elapsedSeconds
        self.cpuPercent = cpuPercent; self.ramBytes = ramBytes
    }
}

public struct TrendHistory: Sendable {
    public private(set) var points: [TrendPoint] = []
    public let capacity: Int
    public init(capacity: Int = 120) { self.capacity = max(1, capacity) }
    public mutating func append(_ point: TrendPoint) {}
    public mutating func reset() { points = [] }
    public func segments(for metric: TrendMetric) -> [[TrendPoint]] { [] }
}
