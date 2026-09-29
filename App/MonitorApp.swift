import SwiftUI
import UIKit
import MonitorCore

@main
struct MonitorDiagnosticsApp: App {
    @StateObject private var session = SessionController()
    var body: some Scene { WindowGroup { DiagnosticView().environmentObject(session) } }
}

private struct ShareRequest: Identifiable {
    let id = UUID()
    var files: [URL]
}

struct DiagnosticView: View {
    @EnvironmentObject var session: SessionController
    @State private var share: ShareRequest?

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    Picker("Duration", selection: $session.minutes) {
                        ForEach([5, 15, 30, 60], id: \.self) { Text("\($0)m").tag($0) }
                    }.pickerStyle(.segmented).disabled(session.running)
                    Toggle("Silent background audio", isOn: $session.audioEnabled)
                    Toggle("Coarse background location", isOn: $session.locationEnabled)
                    HStack {
                        Button(session.running ? "Stop" : "Start") {
                            if session.running { session.stop() } else { session.start() }
                        }.buttonStyle(.borderedProminent).tint(session.running ? .red : .blue).disabled(!session.running && !session.ready)
                        Spacer()
                        if session.running { Text(session.frozen ? "Samples frozen" : "Recording").foregroundStyle(session.frozen ? .orange : .green) }
                    }
                    Text(session.message).font(.footnote).foregroundStyle(.secondary)
                }
                Section("Latest device sample") {
                    if let sample = session.latest {
                        LabeledContent("Sequence", value: "#\(sample.sequence)")
                        HStack { Text("Last sample"); Spacer(); Text(sample.timestamp, style: .relative).foregroundStyle(.secondary) }
                        readingRow("CPU", reading: sample.cpu.reading, divisor: 1, unit: "%")
                        readingRow("RAM estimate", reading: sample.ram.reading, divisor: 1_073_741_824, unit: "GiB")
                        LabeledContent("Thermal state", value: sample.thermalState)
                        LabeledContent("Battery", value: sample.batteryLevel.map { String(format: "%.0f%% · %@", $0 * 100, sample.batteryState) } ?? "Unavailable")
                        LabeledContent("Available storage", value: sample.storageFreeBytes.map { String(format: "%.1f GiB", Double($0) / 1_073_741_824) } ?? "Unavailable")
                        LabeledContent("GPU / Neural Engine", value: "Unavailable")
                        LabeledContent("Disk throughput", value: "Unavailable")
                    } else { Text("Start a session to probe device counters.").foregroundStyle(.secondary) }
                }
                if let sample = session.latest {
                    Section("Network interfaces · B/s") {
                        if let error = sample.networkError { Text(error).font(.caption).foregroundStyle(.secondary) }
                        ForEach(sample.interfaces) { interface in
                            LabeledContent(interface.id, value: "↓ \(rate(interface.rx))  ↑ \(rate(interface.tx))")
                                .font(.caption).monospacedDigit()
                        }
                    }
                    Section("Monitor overhead") {
                        LabeledContent("Own CPU · one core", value: sample.ownCPUPercent.map { String(format: "%.2f%%", $0) } ?? "Warming up")
                        LabeledContent("Own memory footprint", value: sample.ownFootprintBytes.map { String(format: "%.1f MiB", Double($0) / 1_048_576) } ?? "Unavailable")
                        LabeledContent("Silent audio", value: session.audioRunning ? "Running" : "Inactive")
                        LabeledContent("Location permission", value: session.authorization)
                    }
                }
                Section("Diagnostic controls") {
                    Button(session.frozen ? "Resume collector" : "Freeze collector") { session.toggleFreeze() }.disabled(!session.running)
                    Text("Freeze leaves the actual sample sequence unchanged. The Live Activity should become stale after 5 seconds. A moving age label does not prove sampling.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Saved sessions") {
                    if session.sessions.isEmpty { Text("Stop a session to save its summary.").foregroundStyle(.secondary) }
                    ForEach(session.sessions) { saved in
                        VStack(alignment: .leading, spacing: 6) {
                            if let summary = saved.summary {
                                Text(summary.endedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                Text("\(summary.sampleCount) samples · CPU \(summary.validCPUSamples) valid · RAM \(summary.validRAMSamples) valid").font(.caption)
                                if summary.tailUnknown {
                                    Text("Interrupted recording; tail unknown").font(.caption).foregroundStyle(.orange)
                                } else {
                                    Text(String(format: "Attempt coverage %.1f%% · P95 gap %.2fs · max %.2fs", summary.continuity.coveragePercent, summary.continuity.p95GapSeconds, summary.continuity.maxGapSeconds)).font(.caption).monospacedDigit()
                                }
                                Text(summary.stopReason).font(.caption).foregroundStyle(.secondary)
                            } else { Text("Incomplete recording").foregroundStyle(.secondary) }
                            Button("Share recording + summary") { share = ShareRequest(files: saved.files) }
                        }.padding(.vertical, 4)
                    }
                }
                Section("Recent events") {
                    ForEach(Array(session.recentEvents.enumerated()), id: \.offset) { _, event in Text(event).font(.caption).textSelection(.enabled) }
                }
                Section {
                    Text("Diagnostic build · native, JIT not required. CPU/RAM access and background reliability are being tested on your phone. Recordings are available in Files → On My iPhone → Monitor Diagnostics → Sessions.").font(.footnote).foregroundStyle(.secondary)
                    Text("Commit \(Bundle.main.object(forInfoDictionaryKey: "MonitorSourceCommit") as? String ?? "unrecorded")").font(.caption2).textSelection(.enabled)
                }
            }
            .navigationTitle("Monitor Diagnostics")
            .sheet(item: $share) { ShareSheet(files: $0.files) }
        }
    }

    private func readingRow(_ name: String, reading: MetricReading, divisor: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            LabeledContent(name, value: reading.value.map { String(format: "%.2f %@", $0 / divisor, unit) } ?? (reading.status == .warmingUp ? "Warming up" : "Unavailable"))
            if let reason = reading.reason { Text(reason).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
        }
    }
    private func rate(_ reading: MetricReading) -> String { reading.value.map { String(format: "%.0f", $0) } ?? "—" }
}

struct ShareSheet: UIViewControllerRepresentable {
    var files: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: files, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
