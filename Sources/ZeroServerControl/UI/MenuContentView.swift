import SwiftUI
import AppKit

/// The full dropdown content shown when you click the menu bar icon.
///
/// Rendered under `.menuBarExtraStyle(.menu)` (set in ZeroServerControlApp),
/// each top-level child here becomes a native NSMenuItem — this is what
/// keeps the UI feeling like a normal, "light and objective" system menu
/// (think Wi-Fi/Bluetooth) instead of a custom floating panel.
///
/// Deliberately just nodes + exit points now — everything that isn't a
/// node decision (account, preferences, about, this Mac's own agent) lives
/// in the Settings window (see SettingsView.swift) instead, opened via
/// openWindow(id:) the same way LoginView already is.
struct MenuContentView: View {
    @ObservedObject var session: AccountSession
    @ObservedObject var remoteNodes: RemoteNodesController
    @ObservedObject var agent: AgentController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        RemoteNodesSectionView(session: session, remoteNodes: remoteNodes)

        Divider()

        settingsMenuItem

        Divider()

        Button("Quit ZeroServer Control") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
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
