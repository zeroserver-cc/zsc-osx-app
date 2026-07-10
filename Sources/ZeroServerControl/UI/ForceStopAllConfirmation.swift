import AppKit

/// A blocking, native confirmation before force-stopping every node on the
/// account at once. Uses NSAlert directly rather than SwiftUI's
/// .confirmationDialog because this action originates inside a
/// MenuBarExtra `.menu`-style dropdown (a real NSMenu) — SwiftUI's own
/// dialog presentation attaching to a menu's internal hosting window is
/// untested and risky for something this consequential. NSAlert as a
/// standalone modal window is the safe, well-established choice, and
/// matches this app's existing comfort with direct AppKit calls
/// (NSApp.activate / NSWorkspace / NSPasteboard elsewhere in this codebase).
enum ForceStopAllConfirmation {
    @MainActor
    static func confirm(nodeCount: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        if nodeCount == 1 {
            alert.messageText = NSLocalizedString("force_stop.title.singular", value: "Force Stop This Node?", comment: "")
        } else {
            let format = NSLocalizedString("force_stop.title.plural", value: "Force Stop All %ld Nodes?", comment: "")
            alert.messageText = String(format: format, nodeCount)
        }
        alert.informativeText = NSLocalizedString("force_stop.informative", value: """
        This immediately exits the agent process on every node in your \
        account. Unlike Pause, this cannot be undone remotely for any of \
        them — each one can only come back via local/physical access, or \
        its own next reboot.
        """, comment: "")
        // Cancel added first (gets the default Return-key + Escape
        // behavior); Force Stop All added second and explicitly marked
        // destructive (red-tinted) so Return can never accidentally
        // trigger the irreversible action.
        alert.addButton(withTitle: NSLocalizedString("Cancel", value: "Cancel", comment: ""))
        let confirmButton = alert.addButton(withTitle: ForceStopWording.confirmButtonLabel(nodeCount: nodeCount))
        confirmButton.hasDestructiveAction = true

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }
}
