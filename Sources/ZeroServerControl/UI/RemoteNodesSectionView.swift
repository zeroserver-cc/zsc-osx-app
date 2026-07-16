import SwiftUI
import AppKit

/// The "My Nodes" content inserted into MenuContentView's dropdown.
/// Sign Out lives in the Settings window instead (an account decision, not
/// a node one) — this section only ever shows Sign In (the one signed-out
/// action that has to stay one click away) and the node list itself.
struct RemoteNodesSectionView: View {
    @ObservedObject var session: AccountSession
    @ObservedObject var remoteNodes: RemoteNodesController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            switch session.state {
            case .signedOut:
                signedOutSection
            case .signingIn:
                Text("Signing in…").foregroundStyle(.secondary)
            case .signedIn:
                signedInSection
            }
        }
        // RemoteNodesController polls on its own fixed schedule (every
        // 10s), entirely independent of sign-in/out — without this, the
        // list shows its last signed-out state (nodes: [], isLoading:
        // false, so "No nodes yet.") for up to ~10s after a successful
        // sign-in, before the next scheduled tick actually fetches
        // anything. Firing an immediate refresh the moment we become
        // signed in closes that gap: isLoading flips true synchronously
        // inside refreshNow(), so "Loading…" shows right away instead.
        .onChange(of: session.state) { newState in
            if case .signedIn = newState {
                Task { await remoteNodes.refreshNow() }
            }
        }
    }

    private var signedOutSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sign in to control your ZeroServer nodes remotely.")
                .font(.callout)
            Button("Sign In…") {
                // Deferred — this content is hosted inside the menu bar's
                // NSMenu (.menuBarExtraStyle(.menu)); calling openWindow(id:)
                // synchronously inside an NSMenuItem's action can race the
                // menu's own dismissal, leaving its modal keyboard-tracking
                // loop alive underneath the new window — every keystroke
                // then bounces off the menu (audible system beep) instead
                // of ever reaching the window's first responder. See
                // MenuContentView.dashboardMenuItem's doc comment for the
                // full explanation — same fix, same reason, applied here
                // since this button lives in the same NSMenu-hosted tree.
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: AccountLoginWindow.id)
                }
            }
        }
    }

    @ViewBuilder
    private var signedInSection: some View {
        if remoteNodes.isLoading {
            Text("Loading…").foregroundStyle(.secondary)
        } else if let error = remoteNodes.lastFetchError, remoteNodes.nodes.isEmpty {
            Text(error).font(.caption).foregroundStyle(.red)
            Button("Retry") { Task { await remoteNodes.refreshNow() } }
        } else if remoteNodes.nodes.isEmpty {
            // Parity with the error state just above: "no nodes" is just as
            // plausible a moment to want a manual re-check (e.g. right
            // after provisioning one elsewhere) as an outright fetch error.
            Text("No nodes yet.").foregroundStyle(.secondary)
            Button("Retry") { Task { await remoteNodes.refreshNow() } }
        } else {
            ForEach(remoteNodes.nodes) { node in
                RemoteNodeRowView(
                    node: node,
                    actionState: remoteNodes.actionStates[node.id] ?? .init(),
                    onPause: { Task { await remoteNodes.pause(nodeId: node.id) } },
                    onResume: { Task { await remoteNodes.resume(nodeId: node.id) } }
                )
            }

            Divider()
            // M5 (UI/HIG audit): label wording (singular/plural) comes from
            // the same helper the confirmation alert uses, so this button
            // and the alert it opens never disagree on a one-node account.
            Button(ForceStopWording.menuButtonLabel(nodeCount: remoteNodes.nodes.count), role: .destructive) {
                if ForceStopAllConfirmation.confirm(nodeCount: remoteNodes.nodes.count) {
                    Task { await remoteNodes.forceStopAll() }
                }
            }
            .disabled(remoteNodes.isForceStoppingAll)
        }
    }
}
