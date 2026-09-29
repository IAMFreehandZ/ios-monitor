import ActivityKit
import Foundation

@MainActor
final class LiveActivityPublisher {
    var event: ((String, String) -> Void)?
    private var activity: Activity<MonitorAttributes>?
    private var pending: MonitorAttributes.ContentState?
    private var terminal: MonitorAttributes.ContentState?
    private var pumping = false
    private var completion: (() -> Void)?

    func cleanupOrphans() async {
        for old in Activity<MonitorAttributes>.activities {
            var state = old.content.state
            state.phase = "Interrupted"
            await old.end(ActivityContent(state: state, staleDate: state.sampledAt.addingTimeInterval(5)), dismissalPolicy: .default)
        }
    }

    func start(id: UUID, duration: Double) {
        guard activity == nil else { return }
        pending = nil; terminal = nil
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { event?("activity_unavailable", "Live Activities disabled in system settings"); return }
        let state = MonitorAttributes.ContentState(sequence: 0, sampledAt: Date(), cpuPercent: nil, ramGiB: nil, phase: "Starting", thermal: "unknown")
        do {
            activity = try Activity.request(attributes: MonitorAttributes(sessionID: id.uuidString, endsAt: Date().addingTimeInterval(duration)), content: ActivityContent(state: state, staleDate: state.sampledAt.addingTimeInterval(5)), pushType: nil)
            event?("activity_started", activity!.id)
        } catch { event?("activity_start_failed", error.localizedDescription) }
    }

    func publish(_ state: MonitorAttributes.ContentState) {
        guard terminal == nil, let activity else { return }
        guard activity.activityState != .dismissed, activity.activityState != .ended else {
            self.activity = nil; event?("activity_removed", "Activity was dismissed or ended by the system/user"); return
        }
        pending = state
        launchPump()
    }

    func finish(_ state: MonitorAttributes.ContentState, completion: @escaping () -> Void) {
        guard activity != nil else { completion(); return }
        self.completion = completion
        pending = nil
        terminal = state
        launchPump()
    }

    private func launchPump() {
        guard !pumping, activity != nil else { return }
        pumping = true
        Task { await pump() }
    }

    private func pump() async {
        defer { pumping = false }
        while let activity {
            if let terminal {
                await activity.end(ActivityContent(state: terminal, staleDate: terminal.sampledAt.addingTimeInterval(5)), dismissalPolicy: .default)
                event?("activity_end_completed", "sequence=\(terminal.sequence); presentation timing is controlled by iOS")
                self.activity = nil; self.terminal = nil
                let completed = self.completion; self.completion = nil; completed?()
                return
            }
            guard let state = pending else { return }
            pending = nil
            await activity.update(ActivityContent(state: state, staleDate: state.sampledAt.addingTimeInterval(5)))
            event?("activity_update_completed", "sequence=\(state.sequence); submission completion does not prove rendering")
        }
    }
}
