import SwiftUI

/// App entry point. This whole app is just one MenuBarExtra scene — there's
/// no main window, no Dock icon (that's set via `LSUIElement = true` in
/// Packaging/Info.plist once this is bundled as a real .app; running via
/// `swift run` during development will still show a Dock icon since an
/// unbundled executable has no Info.plist to read that from).
@main
struct ZeroServerControlApp: App {
    // @StateObject (not @ObservedObject) here because the App struct owns
    // these for the entire lifetime of the process — they must not be
    // recreated if SwiftUI happens to re-evaluate this struct's body.
    @StateObject private var agent = AgentController()
    @StateObject private var loginItems = LoginItemManager()
    @StateObject private var accountSession: AccountSession
    @StateObject private var remoteNodes: RemoteNodesController

    init() {
        // AccountSession and RemoteNodesController must share the exact
        // same APIClient instance (so a token refresh triggered by one
        // request is immediately visible to the other) — that's only
        // expressible by constructing AccountSession first, then handing
        // its apiClient into RemoteNodesController, both wrapped via the
        // explicit StateObject(wrappedValue:) form rather than the usual
        // `= AccountSession()` property-default syntax.
        let session = AccountSession()
        _accountSession = StateObject(wrappedValue: session)
        _remoteNodes = StateObject(wrappedValue: RemoteNodesController(apiClient: session.apiClient, session: session))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(session: accountSession, remoteNodes: remoteNodes)
        } label: {
            MenuBarIconProvider.image(for: agent.status)
        }
        // .menu renders the dropdown as a native NSMenu (plain list of
        // items, dividers, etc.) rather than a custom floating panel —
        // this is what makes the app feel like a normal system status item
        // (Wi-Fi, Bluetooth, Battery) instead of introducing new UI chrome.
        .menuBarExtraStyle(.menu)

        // A separate window scene for the sign-in form, opened on demand via
        // openWindow(id:) from RemoteNodesSectionView and closed by LoginView
        // itself (see its onChange comment for why that's a plain AppKit
        // close() rather than SwiftUI's dismissWindow) — this app is
        // LSUIElement (no Dock icon, no regular window by default), so
        // there's nothing to show a login form in otherwise.
        Window("Sign In to ZeroServer", id: AccountLoginWindow.id) {
            LoginView(session: accountSession)
        }
        .windowResizability(.contentSize)

        // Settings, opened the same way from MenuContentView's "Settings…"
        // — everything that isn't a node decision lives here instead of
        // cluttering the main dropdown. A real Window, so SettingsView is
        // free of every .menuBarExtraStyle(.menu) hosting constraint this
        // session ran into elsewhere.
        Window("Settings", id: SettingsWindow.id) {
            SettingsView(agent: agent, loginItems: loginItems, session: accountSession)
        }
        .windowResizability(.contentSize)
    }
}
