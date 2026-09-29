import XCTest
@testable import MonitorCore

final class MonitorStateTests: XCTestCase {
    // Regression: returning to audio-only on a fresh install loses the mode
    // that kept the Live Activity updating in the user's device comparison.
    func testNewInstallUsesLocationWithoutActivatingAudio() {
        let preferences = MonitorPreferences.load(nil)
        XCTAssertTrue(preferences.locationEnabled)
        XCTAssertFalse(preferences.audioEnabled)
        XCTAssertEqual(preferences.durationMinutes, 15)
    }

    // Regression: controller relaunch must honor explicit foreground-only choices.
    func testPreferencesRoundTripPreservesExplicitChoices() throws {
        let preferences = MonitorPreferences(durationMinutes: 30, locationEnabled: false, audioEnabled: false)
        let data = try JSONEncoder().encode(preferences)
        XCTAssertEqual(MonitorPreferences.load(data), preferences)
    }

    func testInvalidDurationFallsBackWithoutChangingBackgroundChoices() {
        let data = Data(#"{"durationMinutes":-20,"locationEnabled":false,"audioEnabled":true}"#.utf8)
        let preferences = MonitorPreferences.load(data)
        XCTAssertEqual(preferences.durationMinutes, 15)
        XCTAssertFalse(preferences.locationEnabled)
        XCTAssertTrue(preferences.audioEnabled)
    }

    func testCorruptPreferencesRecoverToUsableDefaults() {
        let preferences = MonitorPreferences.load(Data("not json".utf8))
        XCTAssertEqual(preferences.durationMinutes, 15)
        XCTAssertTrue(preferences.locationEnabled)
        XCTAssertFalse(preferences.audioEnabled)
    }

    // Regression: an hour-long session must not retain an hour of chart objects.
    func testHistoryRetainsOnlyNewestRealSamples() {
        var history = TrendHistory(capacity: 3)
        for id in 1...5 { history.append(point(id, Double(id))) }
        XCTAssertEqual(history.points.map(\.id), [3, 4, 5])
        XCTAssertEqual(history.points.map(\.elapsedSeconds), [3, 4, 5])
    }

    func testZeroIsPlottedButMissingCPUAndGapsBreakTheLine() {
        var history = TrendHistory()
        history.append(point(1, 0, cpu: 0))
        history.append(point(2, 1, cpu: 20))
        history.append(point(3, 2, cpu: nil))
        history.append(point(4, 3, cpu: 30))
        history.append(point(5, 10, cpu: 40))
        XCTAssertEqual(history.segments(for: .cpu).map { $0.map(\.id) }, [[1, 2], [4], [5]])
        XCTAssertEqual(history.segments(for: .ram).map { $0.map(\.id) }, [[1, 2, 3, 4], [5]])
        XCTAssertEqual(history.points.first?.cpuPercent, 0)
    }

    func testInvalidValuesAndDuplicateSamplesCannotInventChartData() {
        var history = TrendHistory()
        history.append(point(1, 0, cpu: .nan, ram: -.infinity))
        history.append(point(1, 0, cpu: 30))
        history.append(point(2, -1, cpu: 30))
        history.append(point(3, .nan, cpu: 30))
        history.append(point(4, 1, cpu: 200, ram: -1))
        XCTAssertEqual(history.points.map(\.id), [1, 4])
        XCTAssertTrue(history.segments(for: .cpu).isEmpty)
        XCTAssertTrue(history.segments(for: .ram).isEmpty)
    }

    func testNewSessionClearsPreviousTrends() {
        var history = TrendHistory()
        history.append(point(1, 0))
        history.reset()
        XCTAssertTrue(history.points.isEmpty)
        history.append(point(1, 0, cpu: 5))
        XCTAssertEqual(history.points.map(\.cpuPercent), [5])
    }

    private func point(_ id: Int, _ elapsed: Double, cpu: Double? = 10, ram: Double? = 1_073_741_824) -> TrendPoint {
        TrendPoint(id: id, elapsedSeconds: elapsed, cpuPercent: cpu, ramBytes: ram)
    }
}
