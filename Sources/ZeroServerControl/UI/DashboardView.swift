import SwiftUI
import AppKit

/// Identifies the Dashboard window's Scene (see ZeroServerControlApp.swift).
/// Same pattern as AccountLoginWindow/SettingsWindow — this app is
/// LSUIElement (no Dock icon, no default window), so this needs an
/// explicitly opened Window rather than any SwiftUI default.
enum DashboardWindow {
    static let id = "dashboard"
}

/// The app's main resource view: per-node CPU/RAM/Disk charts over the last
/// 24h plus a recent status-event timeline. Reachable only via the
/// "Dashboard" button at the top of MenuContentView's dropdown, which forces
/// sign-in first (see MenuContentView.swift's `pendingDashboardOpen` flow) —
/// this view ALSO re-checks `session.state` itself (same defensive pattern
/// RemoteNodesSectionView already uses), so a sign-out that happens while
/// this window is already open falls back to the sign-in prompt instead of
/// continuing to show stale account data.
struct DashboardView: View {
    @ObservedObject var session: AccountSession
    @ObservedObject var remoteNodes: RemoteNodesController
    @ObservedObject var dashboard: DashboardController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            switch session.state {
            case .signedOut, .signingIn:
                signedOutPlaceholder
            case .signedIn:
                signedInContent
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private var signedOutPlaceholder: some View {
        VStack(spacing: 12) {
            Text("Sign in to view your Dashboard.")
                .font(.title3)
            Button("Sign In…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: AccountLoginWindow.id)
                WindowForegroundRequest.post(windowID: AccountLoginWindow.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var signedInContent: some View {
        NavigationSplitView {
            nodeSidebar
        } detail: {
            detailPane
        }
        .task(id: dashboard.selectedNodeId) {
            await dashboard.refreshDetail()
        }
        .onAppear {
            selectDefaultNodeIfNeeded()
            dashboard.startPolling()
        }
        .onDisappear {
            dashboard.stopPolling()
        }
        // Covers the case where the Dashboard opens before
        // RemoteNodesController's own poll has ever completed — the sidebar
        // (and this default-selection logic) reacts the moment nodes
        // actually arrive, rather than staying on an empty list forever.
        .onChange(of: remoteNodes.nodes) { _ in
            selectDefaultNodeIfNeeded()
        }
    }

    private func selectDefaultNodeIfNeeded() {
        guard dashboard.selectedNodeId == nil, let first = remoteNodes.nodes.first else { return }
        dashboard.select(nodeId: first.id)
    }

    private var nodeSidebar: some View {
        List(
            remoteNodes.nodes,
            selection: Binding(
                get: { dashboard.selectedNodeId },
                set: { newValue in if let newValue { dashboard.select(nodeId: newValue) } }
            )
        ) { node in
            Label(node.name, systemImage: "server.rack")
                .foregroundStyle(node.isConnected ? .primary : .secondary)
                .tag(node.id)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if remoteNodes.nodes.isEmpty {
            emptyState(Text("No nodes yet."))
        } else if let nodeId = dashboard.selectedNodeId,
                  let node = remoteNodes.nodes.first(where: { $0.id == nodeId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    snapshotHeader(for: node)

                    if dashboard.isLoadingDetail {
                        Text("Loading…").foregroundStyle(.secondary)
                    } else if let error = dashboard.detailError, dashboard.telemetry.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.caption).foregroundStyle(.red)
                            Button("Retry") { Task { await dashboard.refreshDetail() } }
                        }
                    } else {
                        charts
                        Divider()
                        statusTimeline
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            emptyState(Text("Select a node."))
        }
    }

    private func emptyState(_ text: Text) -> some View {
        text.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func snapshotHeader(for node: RemoteNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(node.name).font(.title2).bold()
                Text(node.statusHintLabel).foregroundStyle(.secondary)
            }
            if let metrics = node.usageSummary {
                HStack(spacing: 24) {
                    ForEach(metrics, id: \.label) { metric in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(metric.label, systemImage: metric.iconSystemName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(metric.percent)%").font(.title).bold()
                        }
                    }
                }
            }
        }
    }

    /// Thresholds match SendHeartbeatUseCase.classifyStatus in zsc-agent:
    /// cpu/mem ≥90% and disk ≥80% is what actually drives a node's own
    /// `.overloaded` status — see NodeUsageChartView's doc comment.
    private var charts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Last 24 Hours").font(.headline)
            NodeUsageChartView(
                title: NSLocalizedString("usage.cpu", value: "CPU", comment: ""),
                color: .blue, points: dashboard.telemetry, value: { $0.cpuPercent }, alertThreshold: 90
            )
            NodeUsageChartView(
                title: NSLocalizedString("usage.ram", value: "RAM", comment: ""),
                color: .green, points: dashboard.telemetry, value: { $0.memoryPercent }, alertThreshold: 90
            )
            NodeUsageChartView(
                title: NSLocalizedString("usage.disk", value: "DISK", comment: ""),
                color: .orange, points: dashboard.telemetry, value: { $0.diskPercent }, alertThreshold: 80
            )
        }
    }

    private var statusTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Activity").font(.headline)
            if dashboard.statusEvents.isEmpty {
                Text("No recent status changes.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(dashboard.statusEvents) { event in
                    HStack {
                        Text(event.transitionLabel)
                        Spacer()
                        Text(event.createdAt, style: .relative).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }
}
