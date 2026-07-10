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
    @Published private(set) var isAvailable: Bool = true

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = SMAppService.mainApp.status == .enabled
            isAvailable = true
        } catch {
            // Most commonly hit when running unbundled (via `swift run`)
            // rather than as a real signed .app. We don't crash or show a
            // scary error for this — we just mark the feature unavailable
            // so MenuContentView can hide the toggle.
            isAvailable = false
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
