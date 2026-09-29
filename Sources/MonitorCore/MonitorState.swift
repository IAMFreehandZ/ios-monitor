import Foundation

public struct MonitorPreferences: Codable, Equatable, Sendable {
    public static let durations = [5, 15, 30, 60]
    public var durationMinutes: Int
    public var locationEnabled: Bool
    public var audioEnabled: Bool

    public init(durationMinutes: Int = 15, locationEnabled: Bool = true, audioEnabled: Bool = false) {
        self.durationMinutes = Self.durations.contains(durationMinutes) ? durationMinutes : 15
        self.locationEnabled = locationEnabled
        self.audioEnabled = audioEnabled
    }

    public static func load(_ data: Data?) -> MonitorPreferences {
        guard let data, let saved = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return Self(durationMinutes: saved.durationMinutes, locationEnabled: saved.locationEnabled, audioEnabled: saved.audioEnabled)
    }
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

    public func value(for metric: TrendMetric) -> Double? {
        switch metric { case .cpu: return cpuPercent; case .ram: return ramBytes }
    }
}

public struct TrendHistory: Sendable {
    public private(set) var points: [TrendPoint] = []
    public let capacity: Int
    public init(capacity: Int = 120) { self.capacity = max(1, capacity) }
    public mutating func append(_ point: TrendPoint) {
        guard point.elapsedSeconds.isFinite, point.elapsedSeconds >= 0 else { return }
        if let last = points.last, point.id <= last.id || point.elapsedSeconds <= last.elapsedSeconds { return }
        var valid = point
        if let cpu = valid.cpuPercent, !cpu.isFinite || !(0...100).contains(cpu) { valid.cpuPercent = nil }
        if let ram = valid.ramBytes, !ram.isFinite || ram < 0 { valid.ramBytes = nil }
        points.append(valid)
        if points.count > capacity { points.removeFirst(points.count - capacity) }
    }
    public mutating func reset() { points = [] }
    public func segments(for metric: TrendMetric) -> [[TrendPoint]] {
        var segments: [[TrendPoint]] = []
        var current: [TrendPoint] = []
        for point in points {
            guard point.value(for: metric) != nil else {
                if !current.isEmpty { segments.append(current); current = [] }
                continue
            }
            if let last = current.last, point.elapsedSeconds - last.elapsedSeconds > 2.5 {
                segments.append(current); current = []
            }
            current.append(point)
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }
}
