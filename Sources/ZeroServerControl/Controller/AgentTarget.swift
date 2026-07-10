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
        ProcessInfo.processInfo.environment["ZSC_CONTROL_DEV_LABEL"] ?? productionLabel
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
