import SwiftUI
import UIKit
import MonitorCore

struct SettingsView: View {
    @ObservedObject var session: SessionController

    var body: some View {
        Form {
            Section("Session length") {
                Picker("Minutes", selection: $session.minutes) {
                    ForEach(MonitorPreferences.durations, id: \.self) { minutes in Text("\(minutes) min").tag(minutes) }
                }.pickerStyle(.segmented).disabled(session.running)
            }
            Section {
                Toggle("Coarse location", isOn: $session.locationEnabled).accessibilityIdentifier("location-mode")
                Toggle("Silent audio backup", isOn: $session.audioEnabled).accessibilityIdentifier("audio-mode")
                LabeledContent("Location access", value: session.authorization.capitalized)
                if session.authorization == "denied" || session.authorization == "restricted" {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } header: { Text("Monitoring in other apps") } footer: {
                Text("Coarse location is the default background mode. Access is requested when you start a session; coordinates are never saved. Silent audio mixes with other apps and is an optional backup. Both services stop at the end of a session. With both off, use the monitor in the foreground.")
            }
            Section {
                NavigationLink { DiagnosticsView(session: session) } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                }.accessibilityIdentifier("diagnostics")
            }
            Section("About") {
                LabeledContent("iOS Monitor", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Local")
                Text("Device CPU and occupied RAM estimate, interface traffic, battery, thermal state and storage. Designed for short monitoring sessions on your own iPhone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Settings")
    }
}

struct DiagnosticsView: View {
    @ObservedObject var session: SessionController

    var body: some View {
        Form {
            Section("Session") {
                LabeledContent("Status", value: session.message)
                LabeledContent("Background mode", value: session.backgroundMode)
                LabeledContent("Silent audio running", value: session.audioRunning ? "Yes" : "No")
                LabeledContent("Live Activity", value: session.activityStatus)
                Button(session.frozen ? "Resume collector" : "Freeze collector") { session.toggleFreeze() }
                    .disabled(!session.running).accessibilityIdentifier("freeze-collector")
                Text("Freeze intentionally stops samples. The old timestamp remains, so freshness can be checked. Activity update completion records a submission, not proof of visible delivery.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let sample = session.latest {
                Section("Monitor overhead") {
                    LabeledContent("App CPU", value: MonitorFormat.percent(sample.ownCPUPercent))
                    LabeledContent("App memory", value: MonitorFormat.bytes(sample.ownFootprintBytes))
                    Text("App CPU: 100% equals one fully occupied core. Device CPU on Monitor is aggregated across all cores.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Collector details") {
                    LabeledContent("Device CPU", value: sample.cpu.reading.status.rawValue)
                    if let reason = sample.cpu.reading.reason { Text(reason).font(.caption).textSelection(.enabled) }
                    LabeledContent("Device RAM", value: sample.ram.reading.status.rawValue)
                    if let reason = sample.ram.reading.reason { Text(reason).font(.caption).textSelection(.enabled) }
                    LabeledContent("Sample interval", value: sample.actualIntervalSeconds.map { String(format: "%.3f s", $0) } ?? "First sample")
                    ForEach(sample.interfaces) { interface in
                        if let reason = interface.rx.reason ?? interface.tx.reason {
                            Text("\(interface.id): \(reason)").font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }
            Section("Recent events") {
                if session.recentEvents.isEmpty { Text("No events yet").foregroundStyle(.secondary) }
                ForEach(Array(session.recentEvents.enumerated()), id: \.offset) { _, event in
                    Text(event).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            Section("Build") {
                Text(Bundle.main.object(forInfoDictionaryKey: "MonitorSourceCommit") as? String ?? "Local source")
                    .font(.caption.monospaced()).textSelection(.enabled)
            }
        }.navigationTitle("Diagnostics").navigationBarTitleDisplayMode(.inline)
    }
}
