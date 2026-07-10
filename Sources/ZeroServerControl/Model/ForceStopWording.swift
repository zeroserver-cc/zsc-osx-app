import Foundation

/// Shared singular/plural wording for the Force-Stop-All flow.
///
/// M5 (UI/HIG audit): the menu button (RemoteNodesSectionView) was always
/// plural ("Force Stop All Agents…"), while the confirmation alert's title
/// (ForceStopAllConfirmation) already singularized to "Force Stop This
/// Node?" for a one-node account — and the alert's own destructive button
/// stayed plural ("Force Stop All") even then. A one-node account saw three
/// disagreeing labels across one flow. This is the one place all three
/// decide together.
///
/// Pure Foundation, no AppKit/SwiftUI dependency — independently testable,
/// same convention as AgentTarget/APIEnvironment's env-var validation.
enum ForceStopWording {
    static func menuButtonLabel(nodeCount: Int) -> String {
        if nodeCount == 1 {
            return NSLocalizedString(
                "force_stop.button.singular",
                value: "Force Stop This Agent…",
                comment: ""
            )
        }
        let format = NSLocalizedString(
            "force_stop.button.plural",
            value: "Force Stop All %ld Agents…",
            comment: ""
        )
        return String(format: format, nodeCount)
    }

    static func confirmButtonLabel(nodeCount: Int) -> String {
        nodeCount == 1
            ? NSLocalizedString("force_stop.confirm_button.singular", value: "Force Stop", comment: "")
            : NSLocalizedString("force_stop.confirm_button.plural", value: "Force Stop All", comment: "")
    }
}
