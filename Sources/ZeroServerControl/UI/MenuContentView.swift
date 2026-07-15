import SwiftUI
import AppKit

/// The full dropdown content shown when you click the menu bar icon.
///
/// Rendered under `.menuBarExtraStyle(.menu)` (set in ZeroServerControlApp),
/// each top-level child here becomes a native NSMenuItem — this is what
/// keeps the UI feeling like a normal, "light and objective" system menu
/// (think Wi-Fi/Bluetooth) instead of a custom floating panel.
///
/// Deliberately just the Dashboard entry point, nodes, and exit points —
/// everything that isn't a node decision (account, preferences, about, this
/// Mac's own agent) lives in the Settings window (see SettingsView.swift)
/// instead, opened via openWindow(id:) the same way LoginView already is.
struct MenuContentView: View {
    @ObservedObject var session: AccountSession
    @ObservedObject var remoteNodes: RemoteNodesController
    @ObservedObject var agent: AgentController
    @ObservedObject var dashboard: DashboardController
    @Environment(\.openWindow) private var openWindow

    /// Set when "Dashboard" is tapped while signed out, instead of opening
    /// the Dashboard directly: it forces the sign-in window open first, and
    /// this flag is what tells `onChange(of: session.state)` below to open
    /// the Dashboard automatically the moment sign-in actually succeeds,
    /// rather than requiring a second click on this same button. Lives here
    /// (not on AccountSession) so the auth model itself stays free of any
    /// UI-navigation intent — same separation of concerns already drawn
    /// between APIClient (networking) and AccountSession (auth state).
    @State private var pendingDashboardOpen = false

    var body: some View {
        dashboardMenuItem

        Divider()

        RemoteNodesSectionView(session: session, remoteNodes: remoteNodes)

        Divider()

        settingsMenuItem

        Divider()

        Button("Quit ZeroServer Control") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        // Mirrors the exact idiom RemoteNodesSectionView already uses to
        // react to a sign-in transition (its own onChange there refreshes
        // the node list) — here, a sign-in that happened because the user
        // clicked "Dashboard" while signed out finishes by opening the
        // Dashboard, with no second click required.
        .onChange(of: session.state) { newState in
            guard pendingDashboardOpen, case .signedIn = newState else { return }
            pendingDashboardOpen = false
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: DashboardWindow.id)
        }
    }

    /// Top of the dropdown, ahead of the node list and Settings — the
    /// single entry point into the app's main resource view. Everything
    /// this button leads to (the node list already visible one section
    /// down, and the Dashboard itself) requires being signed in; this is
    /// the forced-login gate for that.
    private var dashboardMenuItem: some View {
        Button("Dashboard") {
            NSApp.activate(ignoringOtherApps: true)
            if case .signedIn = session.state {
                openWindow(id: DashboardWindow.id)
            } else {
                pendingDashboardOpen = true
                openWindow(id: AccountLoginWindow.id)
            }
        }
    }

    /// A quiet nudge, not an alarm: this Mac's own agent needing attention
    /// (not installed, or its status couldn't be determined) is otherwise
    /// invisible from this top-level menu unless you already know to open
    /// Settings and check. Uses the same VStack-sibling-for-a-caption-line
    /// shape RemoteNodeRowView already relies on for its per-row error text
    /// — the one structure proven to render as intended inside this
    /// .menuBarExtraStyle(.menu) NSMenu-hosted content.
    @ViewBuilder
    private var settingsMenuItem: some View {
        if let hint = settingsHint {
            VStack(alignment: .leading, spacing: 2) {
                openSettingsButton
                Text(hint).font(.caption2).foregroundStyle(.orange)
            }
        } else {
            openSettingsButton
        }
    }

    private var openSettingsButton: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: SettingsWindow.id)
        }
    }

    private var settingsHint: String? {
        switch agent.status {
        case .notInstalled:
            return NSLocalizedString(
                "zsc-agent isn't installed on this Mac.",
                value: "zsc-agent isn't installed on this Mac.",
                comment: ""
            )
        case .unknown:
            return NSLocalizedString(
                "menu.settings_hint.unknown",
                value: "This Mac's agent needs attention.",
                comment: ""
            )
        case .stopped, .starting, .stopping, .running:
            return nil
        }
    }
}
