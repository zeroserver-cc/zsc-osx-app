import SwiftUI
import AppKit

/// Bridges to the real AppKit `NSWindow` behind a SwiftUI `Window` scene's
/// content, so its first appearance gets the two documented AppKit calls
/// for "make this window the frontmost, key window": `NSApp.activate(
/// ignoringOtherApps:)` followed by `window.makeKeyAndOrderFront(nil)`.
/// SwiftUI's `Window(id:)`/`openWindow(id:)` give no direct way to reach
/// the underlying NSWindow, which is the only reason this
/// NSViewRepresentable plumbing exists at all — it is NOT a place for
/// anything beyond that documented two-call sequence. (History: earlier
/// revisions of this file added collectionBehavior tweaks, a manual
/// `orderFrontRegardless()`, a cross-window "please re-foreground"
/// notification system, and a window registry — none of that was ever
/// confirmed to fix anything by an actual test, one of those changes
/// produced a regression, and the underlying focus bug it was all chasing
/// was never confirmed to reproduce outside of running via `swift run`
/// unbundled. Deliberately reverted to exactly what Apple's docs describe,
/// pending a real test against the packaged .app.)
private struct WindowActivationAccessor: NSViewRepresentable {
    final class Coordinator {
        /// Guards this from re-firing on every SwiftUI update pass (e.g.
        /// every keystroke in a form re-renders this view's siblings) —
        /// without it, a user who deliberately switches to a different app
        /// while this window is still open (e.g. to copy a password from a
        /// password manager) would get their focus stolen back on the next
        /// unrelated state change. Tracks the identity of the last
        /// configured NSWindow (rather than a plain "did this ever run"
        /// flag) so that if SwiftUI ever hands this a genuinely different
        /// NSWindow instance for the same Window(id:) scene, it still
        /// reconfigures for it.
        var configuredWindow: ObjectIdentifier?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleFirstAppearanceConfiguration(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleFirstAppearanceConfiguration(for: nsView, coordinator: context.coordinator)
    }

    /// `.window` is nil at the moment `makeNSView`/`updateNSView` run in
    /// many cases — the view isn't attached to its window's hierarchy yet
    /// on that exact call. Deferring to the next run-loop turn is the
    /// standard way to observe attachment; `updateNSView` runs again on
    /// every subsequent SwiftUI render pass regardless, so this reliably
    /// catches the moment `.window` becomes non-nil.
    private func scheduleFirstAppearanceConfiguration(for view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let identity = ObjectIdentifier(window)
            guard coordinator.configuredWindow != identity else { return }
            coordinator.configuredWindow = identity
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}

extension View {
    /// Attaches `WindowActivationAccessor` behind this view. Apply once, to
    /// the outermost content of each `Window(...)` scene in
    /// ZeroServerControlApp.swift.
    func forceForegroundOnFirstAppearance() -> some View {
        background(WindowActivationAccessor())
    }
}
