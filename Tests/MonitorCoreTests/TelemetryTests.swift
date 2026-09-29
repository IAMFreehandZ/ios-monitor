import XCTest
@testable import MonitorCore

final class TelemetryTests: XCTestCase {
    func testCPUUsesBusyAndTotalTickDeltas() throws {
        let a = [CPUTicks(user: 100, system: 40, nice: 10, idle: 850)]
        let b = [CPUTicks(user: 130, system: 60, nice: 10, idle: 900)]
        XCTAssertEqual(try XCTUnwrap(TelemetryMath.cpuPercent(previous: a, current: b).value), 50, accuracy: 1e-6)
    }

    func testCPUWeightsCoresByTotalTicks() throws {
        let a = [CPUTicks(user: 0, system: 0, nice: 0, idle: 0), CPUTicks(user: 0, system: 0, nice: 0, idle: 0)]
        let b = [CPUTicks(user: 30, system: 0, nice: 0, idle: 70), CPUTicks(user: 10, system: 0, nice: 0, idle: 10)]
        XCTAssertEqual(try XCTUnwrap(TelemetryMath.cpuPercent(previous: a, current: b).value), 100 * 40.0 / 120, accuracy: 1e-6)
    }

    func testFirstSnapshotWarmsUp() {
        XCTAssertEqual(TelemetryMath.cpuPercent(previous: nil, current: [CPUTicks(user: 0, system: 0, nice: 0, idle: 1)]).status, .warmingUp)
    }

    func testNonAdvancingCPURemainsUnavailable() {
        let a = [CPUTicks(user: 0, system: 0, nice: 0, idle: 1)]
        XCTAssertNil(TelemetryMath.cpuPercent(previous: a, current: a).value)
        XCTAssertEqual(TelemetryMath.cpuPercent(previous: a, current: a).status, .unavailable)
    }

    func testZeroBusyCPUIsAValidReading() throws {
        let a = [CPUTicks(user: 0, system: 0, nice: 0, idle: 1)]
        let b = [CPUTicks(user: 0, system: 0, nice: 0, idle: 2)]
        XCTAssertEqual(try XCTUnwrap(TelemetryMath.cpuPercent(previous: a, current: b).value), 0)
    }

    func testSupportedCounterWrap() {
        XCTAssertEqual(CounterMath.delta(previous: 4_294_967_040, current: 256, allow32BitWrap: true), 512)
    }

    func testUnexplainedDecreaseIsNotAWrap() {
        XCTAssertNil(CounterMath.delta(previous: 1000, current: 2, allow32BitWrap: true))
        XCTAssertNil(CounterMath.delta(previous: 4_294_967_040, current: 256, allow32BitWrap: false))
    }

    func testPageSizesAndRAMCapacity() throws {
        XCTAssertEqual(try XCTUnwrap(TelemetryMath.occupiedRAM(capacity: 1_073_741_824, freePages: 1024, pageSize: 16_384).value), 1_056_964_608)
        XCTAssertEqual(try XCTUnwrap(TelemetryMath.occupiedRAM(capacity: 1_073_741_824, freePages: 1024, pageSize: 4096).value), 1_069_547_520)
    }

    func testInvalidRAMAndOverflowStayUnavailable() {
        XCTAssertNil(TelemetryMath.occupiedRAM(capacity: 100, freePages: 1024, pageSize: 4096).value)
        XCTAssertNil(TelemetryMath.occupiedRAM(capacity: 100, freePages: UInt64.max, pageSize: 4096).value)
        XCTAssertNil(TelemetryMath.occupiedRAM(capacity: 100, freePages: 0, pageSize: 0).value)
    }

    func testNetworkUsesActualElapsedTime() throws {
        XCTAssertEqual(try XCTUnwrap(TelemetryMath.byteRate(previous: 1_000_000, current: 1_500_000, elapsed: 2).value), 250_000)
        XCTAssertEqual(try XCTUnwrap(TelemetryMath.byteRate(previous: 1_000_000, current: 1_500_000, elapsed: 4).value), 125_000)
    }

    func testNetworkRejectsNonpositiveAndNonfiniteIntervals() {
        for elapsed in [0.0, -1, .nan, .infinity] {
            XCTAssertNil(TelemetryMath.byteRate(previous: 1, current: 2, elapsed: elapsed).value)
        }
    }

    func testNetworkResetAndZeroAreDistinct() throws {
        XCTAssertEqual(try XCTUnwrap(TelemetryMath.byteRate(previous: 10, current: 10, elapsed: 1).value), 0)
        XCTAssertNil(TelemetryMath.byteRate(previous: 10, current: 1, elapsed: 1).value)
    }

    func testDeadlineUsesMonotonicClock() {
        let timeline = SessionTimeline(start: 100, duration: 300)
        XCTAssertFalse(timeline.expired(at: 399.9))
        XCTAssertTrue(timeline.expired(at: 400))
        XCTAssertTrue(timeline.expired(at: 900))
        XCTAssertEqual(timeline.remaining(at: 401), 0)
    }

    func testContinuityDoesNotCountDuplicateOrCatchupSlots() {
        let result = ContinuitySummary(elapsedTimes: [0, 1, 1.1, 4, 4.01], recordingDuration: 5)
        XCTAssertEqual(result.expectedSlots, 5)
        XCTAssertEqual(result.distinctAttemptedSlots, 3)
        XCTAssertEqual(result.coveragePercent, 60, accuracy: 1e-6)
        XCTAssertEqual(result.maxGapSeconds, 2.9, accuracy: 1e-6)
    }

    func testSummaryIncludesSuspendedTail() {
        let result = ContinuitySummary(elapsedTimes: [0, 1, 2], recordingDuration: 20)
        XCTAssertEqual(result.maxGapSeconds, 18, accuracy: 1e-6)
        XCTAssertEqual(result.coveragePercent, 15, accuracy: 1e-6)
    }

    func testCodablePreservesUnavailableReasonAndValidZero() throws {
        let readings = [MetricReading(status: .ok, value: 0, reason: nil), MetricReading(status: .unavailable, value: nil, reason: "host_processor_info: 5")]
        XCTAssertEqual(try JSONDecoder().decode([MetricReading].self, from: JSONEncoder().encode(readings)), readings)
    }

    func testRecordingFailureBlocksLaterServiceActivation() {
        let gate = CallbackGate()
        var activations = 0
        gate.run(stages: [
            { gate.cancel() }, // Recording sink failure calls Stop synchronously.
            { activations += 1 }
        ])
        XCTAssertEqual(activations, 0)
    }

    func testStopDuringAudioCallbackBlocksLocationPermissionRequest() {
        let gate = CallbackGate()
        var startedAudio = false
        var locationRequests = 0
        gate.run(stages: [
            { startedAudio = true; gate.cancel() },
            { locationRequests += 1 }
        ])
        XCTAssertTrue(startedAudio)
        XCTAssertEqual(locationRequests, 0)
    }
}
