import Foundation

/// Every state the menu bar app can observe the zsc-agent LaunchDaemon being in.
///
/// This is deliberately more granular than a plain on/off Bool. The extra
/// cases exist because launchd itself distinguishes them, and the app needs
/// to react differently to each:
///   - `.notInstalled` vs `.stopped`   -> is there even a plist to control?
///   - `.stopped(loaded: false/true)`  -> "never bootstrapped" needs a
///                                        different start command
///                                        (`bootstrap`) than "bootstrapped
///                                        but not currently running"
///                                        (`kickstart -k`). See
///                                        AgentController.startAgent().
///   - `.starting` / `.stopping`       -> a privileged action is in flight;
///                                        used to disable buttons and avoid
///                                        the background poller fighting
///                                        with the user's click.
///   - `.unknown(reason:)`             -> launchctl gave us something we
///                                        didn't expect to parse. We surface
///                                        the raw reason rather than
///                                        guessing, so problems are visible
///                                        instead of silently misreported.
enum AgentStatus: Equatable {
    case notInstalled
    case stopped(loaded: Bool)
    case starting
    case running(pid: Int32)
    case stopping
    case unknown(reason: String)

    /// Whether the primary Start/Stop button should currently do anything.
    /// Transitional and unknown states disable the button — you can't
    /// meaningfully "start" something that's mid-transition, and we don't
    /// want to fire a command based on a status we're not confident about.
    var isActionable: Bool {
        switch self {
        case .stopped, .running:
            return true
        case .notInstalled, .starting, .stopping, .unknown:
            return false
        }
    }

    /// Short label for the status row in Settings' "This Mac's Agent" section.
    var shortLabel: String {
        switch self {
        case .notInstalled: return NSLocalizedString("agent.not_installed", value: "Not Installed", comment: "This Mac's agent status")
        case .stopped: return NSLocalizedString("agent.stopped", value: "Stopped", comment: "This Mac's agent status")
        case .starting: return NSLocalizedString("agent.starting", value: "Starting…", comment: "This Mac's agent status")
        case .running: return NSLocalizedString("agent.running", value: "Running", comment: "This Mac's agent status")
        case .stopping: return NSLocalizedString("agent.stopping", value: "Stopping…", comment: "This Mac's agent status")
        case .unknown: return NSLocalizedString("agent.status_unknown", value: "Status Unknown", comment: "This Mac's agent status")
        }
    }
}
