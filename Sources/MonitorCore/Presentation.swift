import Foundation

public enum SessionFeedbackPhase: Sendable { case preparing, ready, recording, saved, partial, saveFailed }

// Minimal scaffolds for recording-failure and missing-reading regression tests.
public struct SessionFeedback: Sendable {
    public private(set) var phase: SessionFeedbackPhase = .preparing
    public private(set) var summarySaved = true
    public private(set) var failure: String?
    public var message: String { "Recording saved" }
    public init() {}
    public mutating func ready() { phase = .ready }
    public mutating func begin() { phase = .recording }
    public mutating func recordFailure(operation: String, error: Error) {}
    public mutating func finish(completed: Bool, saveSummary: () throws -> Void) {
        try? saveSummary()
        phase = .saved
    }
}

public struct NetworkActivitySummary: Sendable {
    public let hasTraffic = false
    public let warmingUp = false
    public let missingReadings = false
    public let isMeasuredIdle = true
    public init(readings: [MetricReading]) {}
}
