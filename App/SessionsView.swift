import SwiftUI
import UIKit

struct SessionsView: View {
    @ObservedObject var session: SessionController

    var body: some View {
        Group {
            if session.sessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "clock.arrow.circlepath", description: Text("Finished recordings appear here. Start a session from Monitor."))
            } else {
                List(session.sessions) { saved in
                    NavigationLink {
                        SessionDetailView(session: saved)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(saved.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Recovered recording").font(.headline)
                            if let summary = saved.summary {
                                Text("\(MonitorFormat.duration(summary.recordingDurationSeconds)) · \(summary.sampleCount) samples").font(.subheadline).foregroundStyle(.secondary)
                                Text(summary.tailUnknown ? "Interrupted · partial recording" : (summary.stopReason == "recording_error" ? "Recording error · partial session" : (summary.stopReason == "duration_complete" ? "Completed" : "Stopped")))
                                    .font(.caption).foregroundStyle(summary.tailUnknown || summary.stopReason == "recording_error" ? Color.orange : Color.secondary)
                            } else { Text("Summary not available").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("saved-session")
                }
            }
        }.navigationTitle("Sessions")
    }
}

struct SessionDetailView: View {
    let session: SavedSession
    @State private var share: SessionShare?

    var body: some View {
        Form {
            Section("Recording") {
                if let startedAt = session.startedAt {
                    LabeledContent("Started", value: startedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let summary = session.summary {
                    LabeledContent("Duration", value: MonitorFormat.duration(summary.recordingDurationSeconds))
                    LabeledContent("Samples") { Text("\(summary.sampleCount)").accessibilityIdentifier("summary-sample-count") }
                    LabeledContent("Sampling coverage", value: String(format: "%.2f%%", summary.continuity.coveragePercent))
                    LabeledContent("Longest gap", value: String(format: "%.2f s", summary.continuity.maxGapSeconds))
                    LabeledContent("P95 gap", value: String(format: "%.2f s", summary.continuity.p95GapSeconds))
                    LabeledContent("Valid CPU readings", value: "\(summary.validCPUSamples)")
                    LabeledContent("Valid RAM readings", value: "\(summary.validRAMSamples)")
                    if summary.tailUnknown {
                        Text("This session was interrupted. The recording ends at its last observed sample; time after that is unknown. Coverage describes that observed part only.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if summary.stopReason == "recording_error" {
                        Text(summary.note).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    }
                } else {
                    Text("The saved files can still be exported even when a summary cannot be read.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let metadata = session.metadata {
                Section("Session settings") {
                    LabeledContent("Coarse location", value: metadata.locationEnabled ? "On at start" : "Off at start")
                    LabeledContent("Silent audio", value: metadata.audioEnabled ? "On at start" : "Off at start")
                    LabeledContent("App version", value: "\(metadata.appVersion) (\(metadata.buildNumber))")
                    LabeledContent("iOS", value: metadata.operatingSystem)
                }
            }
            Section {
                Button { share = SessionShare(files: session.files) } label: {
                    Label("Export recording", systemImage: "square.and.arrow.up")
                }.disabled(session.files.isEmpty).accessibilityIdentifier("export-session")
            } footer: {
                Text("Share metadata.json, recording.jsonl and summary.json. Sampling coverage describes execution; check Live Activity freshness on the phone.")
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { request in SessionShareSheet(files: request.files) }
    }
}

private struct SessionShare: Identifiable {
    let id = UUID()
    let files: [URL]
}

private struct SessionShareSheet: UIViewControllerRepresentable {
    let files: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: files, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
