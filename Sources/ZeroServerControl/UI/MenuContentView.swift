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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        RemoteNodesSectionView(session: session, remoteNodes: remoteNodes)

        Divider()

        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: SettingsWindow.id)
        }

        Divider()

        Button("Quit ZeroServer Control") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
