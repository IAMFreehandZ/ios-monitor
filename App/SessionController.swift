import Foundation
import UIKit
import MonitorCore

@MainActor
final class SessionController: ObservableObject {
    @Published var running = false
    @Published var ready = false
    @Published var frozen = false
    @Published var minutes = 15
    @Published var audioEnabled = true { didSet { applyModes() } }
    @Published var locationEnabled = false { didSet { applyModes() } }
    @Published var latest: DeviceSample?
    @Published var sessions: [SavedSession] = []
    @Published var message = "Preparing diagnostic services"
    @Published var audioRunning = false
    @Published var authorization = "not determined"
    @Published var recentEvents: [String] = []

    private let collector = DeviceCollector()
    private let services = BackgroundServices()
    private let publisher = LiveActivityPublisher()
    private var recorder: SessionRecorder?
    private var timeline: SessionTimeline?
    private var timer: Timer?
    private var sequence = 0
    private var lastPublishedAt = -Double.infinity
    private var stopping = false
    private var observations: [NSObjectProtocol] = []
    private let modeTransition = CallbackGate()

    init() {
        SessionRecorder.recoverInterrupted()
        sessions = SessionRecorder.saved()
        services.event = { [weak self] name, detail in self?.recordEvent(name, detail) }
        publisher.event = { [weak self] name, detail in self?.recordEvent(name, detail) }
        let center = NotificationCenter.default
        for (notification, name) in [(UIApplication.didEnterBackgroundNotification, "app_background"), (UIApplication.willEnterForegroundNotification, "app_foreground"), (UIApplication.willTerminateNotification, "app_will_terminate"), (Notification.Name.NSProcessInfoPowerStateDidChange, "power_state_changed")] {
            observations.append(center.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.recordEvent(name, "lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")
                    if name == "app_foreground", self.running { self.tick() }
                }
            })
        }
        Task {
            await publisher.cleanupOrphans()
            ready = true
            message = "Ready. Default profile: audio on, location off."
        }
    }

    func start() {
        guard ready, !running, !stopping else { return }
        recorder = nil; latest = nil; frozen = false; sequence = 0; recentEvents = []
        collector.reset()
        lastPublishedAt = -Double.infinity
        let start = DeviceClock.now
        let duration = Double(minutes * 60)
        timeline = SessionTimeline(start: start, duration: duration)
        let id = UUID()
        func info(_ name: String) -> String { Bundle.main.object(forInfoDictionaryKey: name).map { String(describing: $0) } ?? "unrecorded" }
        let metadata = SessionMetadata(id: id, startedAt: Date(), durationSeconds: duration, audioEnabled: audioEnabled, locationEnabled: locationEnabled, deviceModel: SessionRecorder.deviceModel(), operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, sourceCommit: info("MonitorSourceCommit"), appVersion: info("CFBundleShortVersionString"), buildNumber: info("CFBundleVersion"), bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown", extensionIdentifierBeforeSigning: "com.iamfreehandz.iosmonitor.diagnostics.activity", xcodeVersion: info("MonitorXcodeVersion"), sdk: info("MonitorSDK"), locationAuthorization: services.locationAuthorization, initialAudioRoute: services.audioRoute, initialLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, backgroundRefreshStatus: String(UIApplication.shared.backgroundRefreshStatus.rawValue), signingMethod: "Sideloaded; record actual signing tool/version separately")
        do { recorder = try SessionRecorder(metadata: metadata) }
        catch { message = "Recording could not start: \(error.localizedDescription)"; timeline = nil; return }
        running = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        recordEvent("session_start", "id=\(id); duration=\(duration); audio=\(audioEnabled); location=\(locationEnabled)")
        guard running else { return }
        services.configure(audio: audioEnabled, location: locationEnabled)
        guard running else { services.stop(); return }
        publisher.start(id: id, duration: duration)
        tick()
        guard running else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        message = "Recording. Switch to the app you want to monitor."
    }

    func stop(reason: String = "user_stop") {
        guard running, !stopping, let timeline else { return }
        stopping = true; running = false; ready = false; frozen = false
        modeTransition.cancel()
        timer?.invalidate(); timer = nil
        let observedElapsed = max(0, DeviceClock.now - timeline.start)
        recordEvent("session_stop", "reason=\(reason); observedElapsed=\(observedElapsed)")
        services.stop()
        audioRunning = false
        UIDevice.current.isBatteryMonitoringEnabled = false
        let duration = reason == "duration_complete" ? timeline.duration : min(observedElapsed, timeline.duration)
        do { _ = try recorder?.finish(reason: reason, duration: duration) }
        catch { message = "Stopped; summary error: \(error.localizedDescription)" }
        let state = activityState(phase: reason == "duration_complete" ? "Complete" : "Stopped")
        publisher.finish(state) { [weak self] in
            guard let self else { return }
            self.recorder = nil; self.timeline = nil
            self.sessions = SessionRecorder.saved()
            self.ready = true
        }
        sessions = SessionRecorder.saved()
        stopping = false
        message = "Session ended: \(reason). Share its recording from Saved sessions."
    }

    func toggleFreeze() {
        guard running else { return }
        frozen.toggle()
        recordEvent(frozen ? "collector_frozen" : "collector_resumed", "Diagnostic control; missing samples will remain missing")
    }

    private func applyModes() {
        guard running else { return }
        modeTransition.run(stages: [
            { self.recordEvent("background_preferences", "audio=\(self.audioEnabled); location=\(self.locationEnabled)") },
            {
                guard self.running else { return }
                self.services.configure(audio: self.audioEnabled, location: self.locationEnabled)
            }
        ])
        guard running else { services.stop(); return }
        audioRunning = services.audioRunning
        authorization = services.locationAuthorization
    }

    private func tick() {
        guard running, let timeline else { return }
        let now = DeviceClock.now
        if timeline.expired(at: now) { stop(reason: "duration_complete"); return }
        guard !frozen else { return }
        // Foreground callbacks and timer callbacks must not create burst catch-up samples.
        if let latest, now - latest.monotonicTime < 0.9 { return }
        sequence += 1
        let sample = collector.sample(sequence: sequence, startedAt: timeline.start)
        do { try recorder?.append(sample) }
        catch { message = "Recording error: \(error.localizedDescription)"; stop(reason: "recording_error"); return }
        latest = sample
        audioRunning = services.audioRunning
        authorization = services.locationAuthorization
        if sample.monotonicTime - lastPublishedAt >= 2 {
            lastPublishedAt = sample.monotonicTime
            publisher.publish(activityState(phase: "Recording"))
        }
    }

    private func activityState(phase: String) -> MonitorAttributes.ContentState {
        MonitorAttributes.ContentState(sequence: latest?.sequence ?? 0, sampledAt: latest?.timestamp ?? Date(), cpuPercent: latest?.cpu.reading.value, ramGiB: latest?.ram.reading.value.map { $0 / 1_073_741_824 }, phase: phase, thermal: latest?.thermalState ?? "unknown")
    }

    private func recordEvent(_ name: String, _ detail: String) {
        recentEvents.append("\(name): \(detail)")
        if recentEvents.count > 30 { recentEvents.removeFirst(recentEvents.count - 30) }
        audioRunning = services.audioRunning
        authorization = services.locationAuthorization
        guard let recorder, let timeline else { return }
        do { try recorder.event(name: name, detail: detail, elapsed: max(0, DeviceClock.now - timeline.start)) }
        catch {
            message = "Event recording failed: \(error.localizedDescription)"
            if running && !stopping { stop(reason: "recording_error") }
        }
    }
}
