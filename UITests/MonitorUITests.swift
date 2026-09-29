import XCTest

final class MonitorUITests: XCTestCase {
    @MainActor
    func testSessionLifecycleAndPreferencesSurviveRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        let settings = app.tabBars.buttons["Settings"]
        guard settings.waitForExistence(timeout: 8) else {
            XCTFail("The monitoring app must expose Settings navigation")
            return
        }
        settings.tap()
        let location = app.switches["location-mode"]
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        if location.value as? String == "1" { location.tap() }
        let audio = app.switches["audio-mode"]
        if audio.value as? String == "1" { audio.tap() }
        capture(app, "Settings")

        app.terminate()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertEqual(app.switches["location-mode"].value as? String, "0")
        XCTAssertEqual(app.switches["audio-mode"].value as? String, "0")
        app.tabBars.buttons["Monitor"].tap()
        let start = app.buttons["start-session"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        XCTAssertTrue(start.isEnabled)
        start.tap()
        let stop = app.buttons["stop-session"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        let count = app.staticTexts["sample-count"]
        let advancing = NSPredicate { _, _ in
            Int(count.label.replacingOccurrences(of: " samples", with: "")) ?? 0 >= 3
        }
        expectation(for: advancing, evaluatedWith: nil)
        waitForExpectations(timeout: 8)
        capture(app, "Monitor")
        stop.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: start)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)

        app.terminate()
        app.launch()

        app.tabBars.buttons["Sessions"].tap()
        let recording = app.buttons.matching(identifier: "saved-session").firstMatch
        XCTAssertTrue(recording.waitForExistence(timeout: 5))
        recording.tap()
        XCTAssertTrue(app.buttons["export-session"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["summary-sample-count"].exists)
        capture(app, "Session")

        app.tabBars.buttons["Monitor"].tap()
        start.tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        app.tabBars.buttons["Sessions"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "saved-session").count, 2)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
