import SwiftUI
import Charts

/// One resource metric's 24h chart (CPU, RAM, or Disk) — shared by
/// DashboardView for all three metrics rather than three near-duplicate
/// views. Built on `Charts`, Apple's native SwiftUI charting framework
/// (macOS 13+): no new dependency, consistent with this package's
/// zero-external-deps policy (see Package.swift).
struct NodeUsageChartView: View {
    /// Already resolved via NSLocalizedString by the caller (e.g. the
    /// existing "usage.cpu"/"usage.ram"/"usage.disk" keys RemoteNode.swift
    /// already defines) — Text(String) does NOT auto-localize a runtime
    /// value the way Text(_ key: LocalizedStringKey) does for a literal, so
    /// this must arrive already localized.
    let title: String
    let color: Color
    let points: [MachineUsage]
    /// Picks which of MachineUsage's three metrics this instance charts —
    /// diskPercent is optional (some agent versions/platforms never report
    /// it), the other two are always present whenever a point exists at all.
    let value: (MachineUsage) -> Double?
    /// Same overloaded threshold zsc-agent itself uses to classify a node
    /// as `.overloaded` (cpu/mem ≥90%, disk ≥80% — see
    /// SendHeartbeatUseCase.classifyStatus) — drawn as a dashed rule so the
    /// chart visually explains *why* a node went overloaded, not just that
    /// it did.
    let alertThreshold: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).bold()
            if points.isEmpty {
                Text("No data yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Chart {
                    ForEach(points, id: \.recordedAt) { point in
                        if let y = value(point) {
                            LineMark(x: .value("Time", point.recordedAt), y: .value(title, y))
                                .foregroundStyle(color)
                            AreaMark(x: .value("Time", point.recordedAt), y: .value(title, y))
                                .foregroundStyle(color.opacity(0.15))
                        }
                    }
                    RuleMark(y: .value("Alert threshold", alertThreshold))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.red.opacity(0.6))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 100)
            }
        }
    }
}
