import Foundation

/// Identifies *which* LaunchDaemon this app is controlling.
///
/// In normal use this is always the real zsc-agent service. The
/// `ZSC_CONTROL_DEV_LABEL` environment variable override exists purely so
/// we (or you, later) can exercise the exact same launchctl orchestration
/// code in AgentController/LaunchctlRunner against a harmless throwaway
/// LaunchDaemon, instead of the real agent — see
/// Scripts/devtest-daemon-install.sh and the "Devtest daemon" section of
/// CLAUDE.md.
///
/// IMPORTANT: this override is only ever meant to be set manually on the
/// command line for development (`ZSC_CONTROL_DEV_LABEL=... swift run`).
/// The packaged .app you build with Scripts/build-app-bundle.sh never has
/// this variable set, so it always controls the real agent.
struct AgentTarget {
    static let productionLabel = "cc.zeroserver.agent"

    static var label: String {
        guard let override = ProcessInfo.processInfo.environment["ZSC_CONTROL_DEV_LABEL"] else {
            return productionLabel
        }
        return isValidLabel(override) ? override : productionLabel
    }

    /// Real launchd labels are reverse-DNS-style identifiers: letters,
    /// digits, dots, hyphens, underscores only. This is a security
    /// boundary, not a format nicety — `label` flows unescaped into
    /// privileged `osascript ... with administrator privileges` shell
    /// strings built in AgentController.swift, and LaunchctlRunner's
    /// AppleScript-string-literal escaping (`\`/`"` only) does nothing
    /// against shell metacharacters. Any unprivileged local process can
    /// set this env var via `launchctl setenv ZSC_CONTROL_DEV_LABEL '...'`
    /// (inherited by every GUI app subsequently launched, no admin rights
    /// needed) — a payload like `cc.zeroserver.agent; curl ... | sh #`
    /// would otherwise run as root the next time this app's Start/Stop is
    /// clicked and the victim enters their own password. Silently falling
    /// back to the real production label on anything outside this
    /// charset — rather than trying to escape it — is what actually closes
    /// that hole.
    private static func isValidLabel(_ candidate: String) -> Bool {
        guard !candidate.isEmpty, candidate.count <= 255 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return candidate.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// zsc-agent-runner's install.sh always registers the service as a
    /// LaunchDaemon (system-wide, root-owned) at this exact path — see its
    /// README's uninstall section. If that ever changes, this is the only
    /// place that needs updating.
    static var plistPath: String {
        "/Library/LaunchDaemons/\(label).plist"
    }

    /// The `service-target` form launchctl expects for a LaunchDaemon in the
    /// system domain, e.g. "system/cc.zeroserver.agent".
    static var serviceTarget: String {
        "system/\(label)"
    }
}
