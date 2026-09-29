import Foundation

public enum SessionFeedbackPhase: Sendable { case preparing, ready, recording, saved, partial, saveFailed }

public struct SessionFeedback: Sendable {
    public private(set) var phase: SessionFeedbackPhase = .preparing
    public private(set) var summarySaved = false
    public private(set) var failure: String?
    private var errors: [String] = []
    private var completed = false
    public var message: String {
        switch phase {
        case .preparing: return "Preparing monitor"
        case .ready: return "Ready to monitor"
        case .recording: return "Recording. Switch to the app you want to monitor."
        case .saved: return completed ? "Session complete. Recording saved in Sessions." : "Session stopped. Recording saved in Sessions."
        case .partial: return summarySaved ? "Session stopped after a recording error. Partial recording saved." : "Recording failed. Check Diagnostics for details."
        case .saveFailed: return "Session stopped. Summary could not be saved. Export the available files from Sessions."
        }
    }
    public init() {}
    public mutating func ready() { phase = .ready }
    public mutating func begin() {
        phase = .recording; summarySaved = false; failure = nil; errors = []; completed = false
    }
    public mutating func recordFailure(operation: String, error: Error) {
        let detail = "\(operation): \(error.localizedDescription)"
        if !errors.contains(detail), errors.count < 5 { errors.append(detail) }
        failure = errors.joined(separator: "\n")
        phase = .partial
    }
    public mutating func finish(completed: Bool, saveSummary: () throws -> Void) {
        self.completed = completed
        do {
            try saveSummary()
            summarySaved = true
            phase = failure == nil ? .saved : .partial
        } catch {
            summarySaved = false
            recordFailure(operation: "Save summary", error: error)
            phase = .saveFailed
        }
    }
}

public struct NetworkActivitySummary: Sendable {
    public let hasTraffic: Bool
    public let warmingUp: Bool
    public let missingReadings: Bool
    public let isMeasuredIdle: Bool
    public init(readings: [MetricReading]) {
        let values = readings.compactMap { reading -> Double? in
            guard reading.status == .ok, let value = reading.value, value.isFinite, value >= 0 else { return nil }
            return value
        }
        hasTraffic = values.contains { $0 > 0 }
        warmingUp = readings.contains { $0.status == .warmingUp }
        missingReadings = readings.contains { reading in
            if reading.status == .warmingUp { return false }
            guard reading.status == .ok, let value = reading.value, value.isFinite, value >= 0 else { return true }
            return false
        }
        isMeasuredIdle = !readings.isEmpty && values.count == readings.count && values.allSatisfy { $0 == 0 }
    }
}
