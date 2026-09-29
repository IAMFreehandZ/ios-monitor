# Diagnostic IPA Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task. The user has requested the built IPA in this turn; continue through the GitHub build and artifact delivery.

**Goal:** Deliver a sideloadable, native diagnostic IPA for testing device counters, background audio/location, and Live Activity sampling.

**Architecture:** A small Foundation package owns counter arithmetic, session timing, continuity summaries, and serializable evidence. A SwiftUI app supplies the iOS collectors and background services, records sessions in Documents, and publishes a shared ActivityKit content model to a WidgetKit extension. GitHub Actions tests the package, generates the Xcode project, builds an unsigned arm64 app and extension, and uploads the IPA.

**Tech Stack:** Swift 5, SwiftUI, ActivityKit, WidgetKit, AVFoundation, CoreLocation, Darwin/Mach, XcodeGen 2.46.0, GitHub macOS 15 with Xcode 26.3.

**Spec:** [Test specification](../../testing/TEST_SPEC.md), initial feasibility gate.

## Global Constraints

- Native executable; no JIT requirement.
- Phone target: iPhone 17 Pro Max, iOS 27; deployment minimum iOS 17.
- CPU/RAM capability access is a physical device finding. Unsupported GPU/NPU/disk throughput remains unavailable.
- Sampling every 1 second using monotonic time; ordinary ActivityKit submissions at most once every 2 seconds; stale date 5 seconds after the actual sample.
- Presets 5/15/30/60 minutes, default 15. Audio enabled by default, location independently disabled by default.
- JSONL records and JSON summaries with sequence, actual time, raw counters, lifecycle events, and build provenance; sharing through Files and the share sheet.
- Use `tests/test-spec` for the necessary CI commits. Deliver the successful IPA artifact; physical device tests remain unrun until the user reports results.

## Review Focus

- Counter denial on a stock device must preserve API error evidence and other readings.
- Stop during audio interruption must cancel recovery and prevent services restarting.
- Force quit must leave a recoverable incomplete recording and no fabricated samples.
- Sideload signing must preserve the embedded Live Activity extension.
- Actor reentrancy must not publish an old Live Activity update after terminal state.

### Task 1: Tested telemetry core and CI red run

**Files:** `Package.swift`, `Sources/MonitorCore/Telemetry.swift`, `Tests/MonitorCoreTests/TelemetryTests.swift`, `.github/workflows/diagnostic.yml`.

**Interfaces:** `CounterMath.delta`, `TelemetryMath.cpuPercent`, `TelemetryMath.occupiedRAM`, `TelemetryMath.byteRate`, `SessionTimeline`, `ContinuitySummary`, and Codable `MetricReading`.

- [ ] Write fixtures for CPU 50%, aggregate 33.333333%, 32-bit wrap 512, invalid decreases, RAM 0.984375 GiB, actual-interval rates, valid zero, clock expiry, duplicate attempts, and Codable evidence.
- [ ] Publish a minimal interface scaffold and run `swift test` on GitHub. Verify assertion failures demonstrate missing arithmetic rather than compiler failures.
- [ ] Implement the calculations and session/continuity logic. Run the same suite green in Actions.

### Task 2: Device diagnostic app and extension

**Files:** `project.yml`, `App/MonitorApp.swift`, `App/SessionController.swift`, `App/DeviceCollector.swift`, `App/BackgroundServices.swift`, `App/SessionRecorder.swift`, `Shared/MonitorAttributes.swift`, `Widget/MonitorWidget.swift`, `App/Info.plist`, `Widget/Info.plist`.

**Interfaces:** `DeviceCollector.sample(at:) -> DeviceSample`; main-actor session controller exposes settings, Start/Stop, latest readings, saved sessions and export; background services expose explicit Start/Stop/configure and event callbacks; recorder accepts Codable events and samples and writes final summaries.

- [ ] Add failing timeline/summary tests for interrupted sessions, missed slots, raw export round-trip and boundary expiration before implementing their core behavior.
- [ ] Implement one session and one sampler, real Mach counters, per-interface network rates, battery/thermal/storage, silent looping audio with mixing, and independent coarse location.
- [ ] Record API failures, route and lifecycle events; end on monotonic deadline; recover interrupted recordings on relaunch. Stop services on recording failure.
- [ ] Implement Live Activity request/update/end with strictly ordered updates, 5-second stale dates and sequence numbers; include Freeze Collector as a diagnostic control.
- [ ] Implement compact SwiftUI controls, readings, summary and session sharing. Keep session history on disk and in-memory history bounded.

### Task 3: Compile, inspect, review, and deliver IPA

**Files:** `.github/workflows/diagnostic.yml`, `scripts/validate_ipa.py`, `README.md`, local continuation checkpoint.

- [ ] Pin the runner/Xcode and XcodeGen; record SDK, source SHA and build number in the app and artifact.
- [ ] Run all Swift package tests, generate the Xcode project, and compile the physical device app and embedded extension with signing disabled.
- [ ] Package `Payload/MonitorDiagnostics.app` as `iOS-Monitor-Diagnostics.ipa`; inspect identifiers, arm64 executables, background declarations and extension inclusion.
- [ ] Obtain one independent final code review; fix material findings and rerun required checks.
- [ ] Upload the successful artifact, retrieve a usable download reference and deliver it to the user. Label its required sideload signing and preserve the extension. No phone result is assumed.
