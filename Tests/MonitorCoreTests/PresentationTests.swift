import Foundation
import XCTest
@testable import MonitorCore

final class PresentationTests: XCTestCase {
    // Regression: Stop must preserve the actual write failure even if a summary
    // can subsequently be saved. The dashboard consumes this model's message.
    func testSampleFailureRemainsVisibleAfterSuccessfulSummary() {
        var feedback = SessionFeedback()
        feedback.begin()
        feedback.recordFailure(operation: "Sample", error: diskError("Sample disk full"))
        feedback.finish(completed: false, saveSummary: {})
        XCTAssertTrue(feedback.failure?.contains("Sample disk full") == true)
        XCTAssertTrue(feedback.summarySaved)
        XCTAssertEqual(feedback.phase, .partial)
    }

    // Regression: a failed summary write must never produce a saved outcome.
    func testSummaryWriteFailureDoesNotReportSaved() {
        var feedback = SessionFeedback()
        feedback.begin()
        feedback.finish(completed: true) { throw diskError("Summary disk full") }
        XCTAssertFalse(feedback.summarySaved)
        XCTAssertEqual(feedback.phase, .saveFailed)
        XCTAssertTrue(feedback.failure?.contains("Summary disk full") == true)
    }

    func testEventAndSummaryFailuresBothRemainInspectable() {
        var feedback = SessionFeedback()
        feedback.begin()
        feedback.recordFailure(operation: "Event", error: diskError("Event write failed"))
        feedback.finish(completed: false) { throw diskError("Summary write failed") }
        XCTAssertTrue(feedback.failure?.contains("Event write failed") == true)
        XCTAssertTrue(feedback.failure?.contains("Summary write failed") == true)
        XCTAssertEqual(feedback.phase, .saveFailed)
    }

    func testNewSessionClearsThePreviousFailure() {
        var feedback = SessionFeedback()
        feedback.begin()
        feedback.recordFailure(operation: "Sample", error: diskError("Old failure"))
        feedback.finish(completed: false, saveSummary: {})
        feedback.begin()
        XCTAssertNil(feedback.failure)
        XCTAssertFalse(feedback.summarySaved)
        XCTAssertEqual(feedback.phase, .recording)
    }

    // Regression: nil rates are not measured zeros in the collapsed card.
    func testWarmingNetworkReadingsDoNotDescribeMeasuredInactivity() {
        let summary = NetworkActivitySummary(readings: [MetricReading(status: .warmingUp, value: nil, reason: "Baseline")])
        XCTAssertFalse(summary.isMeasuredIdle)
        XCTAssertTrue(summary.warmingUp)
        XCTAssertFalse(summary.hasTraffic)
    }

    func testOnlyValidZeroRatesDescribeMeasuredInactivity() {
        let zero = MetricReading(status: .ok, value: 0, reason: nil)
        XCTAssertTrue(NetworkActivitySummary(readings: [zero, zero]).isMeasuredIdle)
        let reset = MetricReading(status: .unavailable, value: nil, reason: "Counter reset")
        let summary = NetworkActivitySummary(readings: [zero, reset])
        XCTAssertFalse(summary.isMeasuredIdle)
        XCTAssertTrue(summary.missingReadings)
        XCTAssertFalse(NetworkActivitySummary(readings: []).isMeasuredIdle)
    }

    func testTrafficDoesNotConcealOtherMissingReadings() {
        let traffic = MetricReading(status: .ok, value: 2000, reason: nil)
        let failed = MetricReading(status: .error, value: nil, reason: "No counter")
        let summary = NetworkActivitySummary(readings: [traffic, failed])
        XCTAssertTrue(summary.hasTraffic)
        XCTAssertTrue(summary.missingReadings)
        XCTAssertFalse(summary.isMeasuredIdle)
    }

    private func diskError(_ description: String) -> NSError {
        NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError, userInfo: [NSLocalizedDescriptionKey: description])
    }
}
