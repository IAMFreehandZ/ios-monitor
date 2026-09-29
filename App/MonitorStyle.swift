import SwiftUI
import MonitorCore

struct MonitorCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

enum MonitorFormat {
    static func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
    static func gibibytes(_ value: Double?) -> String { value.map { String(format: "%.2f", $0 / 1_073_741_824) } ?? "—" }
    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "Not available" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }
    static func rate(_ reading: MetricReading) -> String {
        guard reading.status == .ok, let value = reading.value else { return reading.status == .warmingUp ? "Starting…" : "—" }
        if value >= 1_000_000 { return String(format: "%.2f MB/s", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1f kB/s", value / 1_000) }
        return String(format: "%.0f B/s", value)
    }
    static func duration(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds.rounded(.down)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

struct TrendChart: View {
    let history: TrendHistory
    let metric: TrendMetric
    let ceiling: Double
    let tint: Color

    var body: some View {
        Canvas { context, size in
            var guides = Path()
            for fraction in [CGFloat(0), 0.5, 1.0] {
                let y = (size.height - 6) * fraction + 3
                guides.move(to: CGPoint(x: 0, y: y)); guides.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(guides, with: .color(.secondary.opacity(0.15)), lineWidth: 1)
            let first = history.points.first?.elapsedSeconds ?? 0
            let span = max(1, (history.points.last?.elapsedSeconds ?? first) - first)
            for segment in history.segments(for: metric) {
                var line = Path()
                for (index, point) in segment.enumerated() {
                    guard let value = point.value(for: metric) else { continue }
                    let x = CGFloat((point.elapsedSeconds - first) / span) * size.width
                    let fraction = CGFloat(min(1, max(0, value / max(1, ceiling))))
                    let position = CGPoint(x: x, y: 3 + (1 - fraction) * (size.height - 6))
                    if index == 0 { line.move(to: position) } else { line.addLine(to: position) }
                    if segment.count == 1 { context.fill(Path(ellipseIn: CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: 4)), with: .color(tint)) }
                }
                context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 64)
        .accessibilityLabel(metric == .cpu ? "Recent CPU trend" : "Recent occupied RAM trend")
    }
}
