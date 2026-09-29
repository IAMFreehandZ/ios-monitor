import SwiftUI
import MonitorCore

struct DashboardView: View {
    @ObservedObject var session: SessionController
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sessionControls
                if textSize.isAccessibilitySize {
                    cpuCard; ramCard
                } else {
                    HStack(alignment: .top, spacing: 12) { cpuCard; ramCard }
                }
                if let sample = session.latest {
                    networkCard(sample)
                    deviceCard(sample)
                } else {
                    MonitorCard {
                        Label("Start a session to see your iPhone's vitals.", systemImage: "iphone")
                            .foregroundStyle(.secondary)
                    }
                }
            }.padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("iOS Monitor")
    }

    private var sessionControls: some View {
        MonitorCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(session.running ? (session.frozen ? "Paused" : "Monitoring") : "Ready", systemImage: session.running ? "record.circle" : "waveform.path.ecg")
                        .font(.headline).foregroundStyle(session.running ? Color.green : Color.primary)
                    Spacer()
                    if session.running {
                        Text(MonitorFormat.duration(session.remainingSeconds) + " left").font(.subheadline).monospacedDigit()
                    } else {
                        Menu {
                            ForEach(MonitorPreferences.durations, id: \.self) { minutes in
                                Button("\(minutes) minutes") { session.minutes = minutes }
                            }
                        } label: { Text("\(session.minutes) min"); Image(systemName: "chevron.down") }
                    }
                }
                if session.running {
                    HStack {
                        Text("\(session.latest?.sequence ?? 0) samples").accessibilityIdentifier("sample-count")
                        Spacer()
                        freshness
                    }.font(.caption).foregroundStyle(.secondary)
                    Label(session.backgroundMode, systemImage: "location.circle").font(.caption)
                    if session.locationNeedsPermission {
                        Text("Allow location access for monitoring in other apps. You can change access in Settings.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    LabeledContent("Live Activity", value: session.activityStatus).font(.caption).foregroundStyle(.secondary)
                    Button(role: .destructive) { session.stop() } label: {
                        Label("Stop monitoring", systemImage: "stop.fill").frame(maxWidth: .infinity).padding(.vertical, 5)
                    }.buttonStyle(.bordered).accessibilityIdentifier("stop-session")
                } else {
                    Text(session.message).font(.subheadline).foregroundStyle(.secondary)
                    Text(session.locationEnabled ? "Coarse location keeps this session available while you use other apps." : (session.audioEnabled ? "Silent audio is enabled for the next session." : "Foreground monitoring is selected."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button { session.start() } label: {
                        Label("Start monitoring", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent).disabled(!session.ready).accessibilityIdentifier("start-session")
                }
            }
        }
    }

    private var freshness: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let sample = session.latest {
                let age = max(0, context.date.timeIntervalSince(sample.timestamp))
                Text(age > 5 ? "Stale · \(Int(age))s old" : "Updated \(Int(age))s ago")
                    .foregroundStyle(age > 5 ? Color.orange : Color.secondary)
            } else { Text("Starting…") }
        }
    }

    private var cpuCard: some View {
        metricCard(title: "CPU", icon: "cpu", value: MonitorFormat.percent(session.latest?.cpu.reading.value), unit: "Device total", reading: session.latest?.cpu.reading, metric: .cpu, ceiling: 100, tint: .cyan)
    }

    private var ramCard: some View {
        metricCard(title: "RAM estimate", icon: "memorychip", value: MonitorFormat.gibibytes(session.latest?.ram.reading.value), unit: "GiB occupied", reading: session.latest?.ram.reading, metric: .ram, ceiling: Double(ProcessInfo.processInfo.physicalMemory), tint: .purple)
    }

    private func metricCard(title: String, icon: String, value: String, unit: String, reading: MetricReading?, metric: TrendMetric, ceiling: Double, tint: Color) -> some View {
        MonitorCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon).font(.subheadline).foregroundStyle(.secondary)
                Text(value).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
                    .accessibilityLabel("\(title), \(value), \(unit)")
                Text(unit).font(.caption).foregroundStyle(.secondary)
                TrendChart(history: session.history, metric: metric, ceiling: ceiling, tint: tint)
                Text(reading?.status == .warmingUp ? "Warming up…" : (reading?.value == nil ? (session.latest == nil ? "Waiting for samples" : "Not available") : "Recent samples"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func networkCard(_ sample: DeviceSample) -> some View {
        MonitorCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Network", systemImage: "network").font(.headline)
                if let error = sample.networkError { Text(error).font(.caption).foregroundStyle(.secondary) }
                if sample.interfaces.isEmpty { Text("No readable interface counters").font(.caption).foregroundStyle(.secondary) }
                let active = sample.interfaces.filter { ($0.rx.value ?? 0) > 0 || ($0.tx.value ?? 0) > 0 }
                if active.isEmpty && !sample.interfaces.isEmpty {
                    Text("No traffic in this sample").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(active) { interface in interfaceRow(interface) }
                if !sample.interfaces.isEmpty {
                    DisclosureGroup("All interfaces (\(sample.interfaces.count))") {
                        ForEach(sample.interfaces) { interface in interfaceRow(interface).padding(.vertical, 4) }
                    }.font(.caption)
                }
                Text("Per interface · download / upload").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func interfaceRow(_ interface: InterfaceReading) -> some View {
        HStack(alignment: .top) {
            Text(interface.id).font(.caption.monospaced()).textSelection(.enabled)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Label(MonitorFormat.rate(interface.rx), systemImage: "arrow.down")
                Label(MonitorFormat.rate(interface.tx), systemImage: "arrow.up")
            }.font(.caption).monospacedDigit()
        }
    }

    private func deviceCard(_ sample: DeviceSample) -> some View {
        MonitorCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Device", systemImage: "iphone").font(.headline)
                LabeledContent("Battery", value: sample.batteryLevel.map { "\(Int(($0 * 100).rounded()))% · \(sample.batteryState)" } ?? "Not available")
                LabeledContent("Thermal state", value: sample.thermalState.capitalized)
                LabeledContent("Low Power Mode", value: sample.lowPowerMode ? "On" : "Off")
                LabeledContent("Storage free", value: MonitorFormat.bytes(sample.storageFreeBytes))
                LabeledContent("Storage capacity", value: MonitorFormat.bytes(sample.storageCapacityBytes))
                Text("RAM includes cached and reclaimable memory. Physical capacity: \(MonitorFormat.gibibytes(Double(ProcessInfo.processInfo.physicalMemory))) GiB.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.font(.subheadline)
        }
    }
}
