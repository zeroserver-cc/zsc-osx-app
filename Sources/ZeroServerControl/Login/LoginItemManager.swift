import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp`, the modern (macOS 13+) API for registering
/// this app to launch automatically at login. This intentionally does NOT
/// touch zsc-agent or launchd daemons in any way — it only controls whether
/// *this menu bar app itself* starts when you log in, which is a separate,
/// much lower-stakes toggle than anything AgentController does.
///
/// One important caveat: `SMAppService` only works correctly from a properly
/// bundled and (at least ad-hoc) code-signed .app — see
/// Scripts/build-app-bundle.sh. When you run this via `swift run` during
/// development, registration calls will typically fail; `isAvailable`
/// reflects that so the UI can hide/disable the toggle instead of showing a
/// confusing error every time.
@MainActor
final class LoginItemManager: ObservableObject {

    @Published private(set) var isEnabled: Bool
    /// Whether this environment can use SMAppService at all — decided ONCE,
    /// up front, from whether this process has a real bundle identifier
    /// (an unbundled `swift run` executable has no Info.plist, so this is
    /// reliably nil there — same signal SettingsView.versionString already
    /// uses to detect the same situation). Previously this started `true`
    /// and only flipped to `false` as a side effect of a failed
    /// register()/unregister() call — which meant the toggle appeared,
    /// the user clicked it, the call failed (as it always does unbundled),
    /// and the whole section vanished out from under them at that exact
    /// moment. Deciding this up front means it simply never appears in a
    /// dev build, instead of appearing and then disappearing on first use.
    @Published private(set) var isAvailable: Bool
    /// Set only when register()/unregister() fails while still available
    /// (a genuine, unexpected SMAppService error in a real packaged .app) —
    /// SettingsView surfaces this instead of the toggle silently reverting.
    @Published private(set) var lastErrorMessage: String?

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
        isAvailable = Bundle.main.bundleIdentifier != nil
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = SMAppService.mainApp.status == .enabled
            lastErrorMessage = nil
        } catch {
            // A real failure in an environment we already know supports
            // SMAppService — surface it, but don't hide the toggle over it;
            // isAvailable is a one-time environment fact, not a reaction to
            // this specific attempt.
            isEnabled = SMAppService.mainApp.status == .enabled
            lastErrorMessage = error.localizedDescription
        }
    }
}
