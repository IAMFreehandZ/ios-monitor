import ActivityKit
import WidgetKit
import SwiftUI

@main
struct MonitorWidgetBundle: WidgetBundle {
    var body: some Widget { MonitorLiveActivity() }
}

struct MonitorLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MonitorAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("iOS Monitor", systemImage: "waveform.path.ecg").font(.headline)
                    Spacer()
                    Text(context.isStale ? "Stale" : context.state.phase).font(.caption).foregroundStyle(context.isStale ? .orange : .secondary)
                }
                HStack {
                    value("CPU", cpu(context.state.cpuPercent))
                    Spacer()
                    value("RAM estimate", ram(context.state.ramGiB))
                    Spacer()
                    value("Sample", "#\(context.state.sequence)")
                }
                HStack {
                    Text("Sample age:")
                    Text(context.state.sampledAt, style: .relative)
                    Spacer()
                    Text(context.state.thermal)
                }.font(.caption2).foregroundStyle(.secondary)
            }.padding(14)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { value("CPU", cpu(context.state.cpuPercent)) }
                DynamicIslandExpandedRegion(.trailing) { value("RAM estimate", ram(context.state.ramGiB)) }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.isStale ? "Stale · #\(context.state.sequence)" : "\(context.state.phase) · #\(context.state.sequence)")
                        Spacer()
                        Text(context.state.sampledAt, style: .relative)
                    }.font(.caption).foregroundStyle(context.isStale ? .orange : .secondary)
                }
            } compactLeading: {
                Text(context.isStale ? "Stale" : cpu(context.state.cpuPercent)).font(.caption2).monospacedDigit()
            } compactTrailing: {
                Text(context.state.ramGiB.map { String(format: "%.1fG", $0) } ?? "—").font(.caption2).monospacedDigit()
            } minimal: {
                Image(systemName: context.isStale ? "exclamationmark.circle" : "waveform.path.ecg")
            }.keylineTint(context.isStale ? .orange : .cyan)
        }
    }

    private func cpu(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
    private func ram(_ value: Double?) -> String { value.map { String(format: "%.2f GiB", $0) } ?? "Unavailable" }
    private func value(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(text).font(.headline).monospacedDigit()
        }
    }
}
