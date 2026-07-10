import AppKit

/// Tiny wrapper around NSPasteboard so AgentController doesn't need to
/// import AppKit itself just for one call — keeps the "what talks to
/// launchctl" logic visually separate from "what talks to the OS clipboard."
enum ClipboardWriter {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
