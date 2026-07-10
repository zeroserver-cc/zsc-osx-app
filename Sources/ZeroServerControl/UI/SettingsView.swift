import SwiftUI
import AppKit

/// Identifies the Settings window's Scene (see ZeroServerControlApp.swift).
/// Same pattern as AccountLoginWindow — this app is LSUIElement (no Dock
/// icon, no default window), so this needs an explicitly opened Window
/// rather than relying on SwiftUI's automatic Settings scene (which is
/// itself unavailable pre-macOS 14 anyway).
enum SettingsWindow {
    static let id = "settings"
}

/// Everything that isn't a node decision: this Mac's own agent, account,
/// preferences, connection, and about — pulled out of the main dropdown
/// into one hub, opened via Settings… in MenuContentView. A real Window,
/// not .menuBarExtraStyle(.menu) content, so none of that hosting mode's
/// constraints apply here (hover, VStack siblings, Image/ForEach all work
/// completely normally in a real window).
struct SettingsView: View {
    @ObservedObject var agent: AgentController
    @ObservedObject var loginItems: LoginItemManager
    @ObservedObject var session: AccountSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title2).bold()

            sectionHeader("This Mac's Agent")
            StatusRowView(status: agent.status)
            if let message = agent.lastActionMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            agentPrimaryAction

            Divider()

            sectionHeader("Account")
            accountRow

            Divider()

            if loginItems.isAvailable {
                sectionHeader("Preferences")
                Toggle("Launch at Login", isOn: Binding(
                    get: { loginItems.isEnabled },
                    set: { loginItems.setEnabled($0) }
                ))
                Divider()
            }

            sectionHeader("Connection")
            Text(APIEnvironment.displayName).foregroundStyle(.secondary)

            Divider()

            sectionHeader("About")
            HStack {
                Text(versionString).foregroundStyle(.secondary)
                Spacer()
                Button("Open zeroserver.cc") {
                    if let url = URL(string: "https://zeroserver.cc") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("About ZeroServer Control") {
                    // See MenuContentView's former copy of this call for
                    // why .activate(...) is needed first — same
                    // .accessory-activation-policy reasoning, unchanged by
                    // the move to Settings.
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    // LocalizedStringKey, not String — a String parameter would make
    // Text(key) resolve to Text's verbatim (non-localizing) initializer
    // instead of the one that looks the literal up in Localizable.strings.
    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.headline)
    }

    @ViewBuilder
    private var accountRow: some View {
        switch session.state {
        case .signedIn(let user):
            HStack {
                Text(user.email)
                Spacer()
                Button("Sign Out") { session.signOut() }
            }
        case .signedOut, .signingIn:
            Text("Not signed in").foregroundStyle(.secondary)
        }
    }

    /// Reconstructs exactly what MenuContentView showed before this Mac's
    /// agent controls were pulled out of the main dropdown into Settings —
    /// same AgentController methods, same per-status branching, just a new
    /// home.
    @ViewBuilder
    private var agentPrimaryAction: some View {
        switch agent.status {
        case .notInstalled:
            VStack(alignment: .leading, spacing: 4) {
                Text("zsc-agent isn't installed on this Mac.")
                    .font(.callout)
                Button("Copy Install Command") {
                    agent.copyInstallCommandToClipboard()
                }
            }
        case .stopped:
            Button("Start Agent") {
                Task { await agent.performPrimaryAction() }
            }
        case .running:
            Button("Stop Agent") {
                Task { await agent.performPrimaryAction() }
            }
        case .starting, .stopping:
            Text(agent.status.shortLabel)
                .foregroundStyle(.secondary)
        case .unknown:
            Button("Retry") {
                Task { await agent.refreshStatusNow() }
            }
        }
    }

    /// e.g. "Version 1.0.0 (1)" — same Info.plist keys AppKit's own About
    /// panel already reads (CFBundleShortVersionString/CFBundleVersion),
    /// just surfaced inline here too for convenience.
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        let format = NSLocalizedString("about.version_format", value: "Version %@ (%@)", comment: "e.g. Version 1.0.0 (1)")
        return String(format: format, shortVersion, build)
    }
}
