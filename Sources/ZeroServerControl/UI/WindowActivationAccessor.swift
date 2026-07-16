import SwiftUI
import AppKit

/// Posted by every button that calls `openWindow(id:)` in this app,
/// alongside that call — the one explicit, always-fired signal that a user
/// just asked to see a specific window right now. `WindowActivationAccessor`
/// listens for its own window's id and reasserts foreground/key status
/// unconditionally when it arrives, which is what makes "bring an
/// ALREADY-OPEN window (stuck behind another app's window) back to front"
/// work — the accessor's own first-appearance guard (see below) only fires
/// once per window instance and deliberately does NOT re-fire just because
/// `openWindow(id:)` was called again for a window that already exists.
enum WindowForegroundRequest {
    static let notificationName = Notification.Name("cc.zeroserver.control.requestWindowForeground")
    static let windowIDKey = "windowID"

    static func post(windowID: String) {
        NotificationCenter.default.post(name: notificationName, object: nil, userInfo: [windowIDKey: windowID])
    }
}

/// Bridges to the real AppKit `NSWindow` behind a SwiftUI `Window` scene's
/// content, so this app's ad hoc windows (Login/Settings/Dashboard) behave
/// like a normal app's windows instead of a background utility's.
///
/// This app is `.accessory` (LSUIElement — no Dock icon, no app-switcher
/// entry). Every place that opens one of these windows already calls
/// `NSApp.activate(ignoringOtherApps: true)` right before `openWindow(id:)`
/// — that alone turned out to be insufficient for several related, reported
/// bugs, all sharing the same root cause:
///
/// - A freshly-opened window could appear BEHIND another app's already-
///   frontmost window: `activate(ignoringOtherApps:)` fires before the
///   window actually exists (SwiftUI creates it asynchronously relative to
///   the call), so there's nothing yet to bring forward at the moment
///   activation happens. `orderFrontRegardless()` — the AppKit API
///   documented specifically for "move this window to the front of the
///   screen list even if this app isn't the active one" — fixes this once
///   the window genuinely exists (handled on first appearance, below).
/// - A window could fail to appear at all while another app owned the
///   active fullscreen Space: with no `collectionBehavior` set, a new
///   window is created on this app's own Space, not the one the user is
///   currently looking at. `.moveToActiveSpace` moves it to wherever the
///   user actually is; `.fullScreenAuxiliary` is the flag that specifically
///   permits a window to be shown at all alongside another app's native
///   fullscreen Space (the same flag system panels like Spotlight use).
/// - "Can't type" in a multi-Space setup is a consequence of the same gap:
///   a window that never becomes the *key* window never delivers keyboard
///   events to its SwiftUI TextFields, regardless of whether it's visible.
///   `makeKeyAndOrderFront(nil)` fixes that once the window exists.
/// - An already-open window that's gotten stuck BEHIND another app's window
///   (e.g. the user alt-tabbed away and back) needs a DIFFERENT trigger
///   than "first appearance" — see `WindowForegroundRequest` above, which
///   this also listens for.
private struct WindowActivationAccessor: NSViewRepresentable {
    /// Matches the same id passed to this window's `Window(id:)` scene and
    /// to `openWindow(id:)` at every call site — this is what lets this
    /// instance filter `WindowForegroundRequest` notifications down to the
    /// ones meant for its own window.
    let windowID: String

    final class Coordinator {
        /// Guards the first-appearance path from re-firing on every SwiftUI
        /// update pass (e.g. every keystroke in a form re-renders this
        /// view's siblings) — without it, a user who deliberately switches
        /// to a different app while this window is still open (e.g. to
        /// copy a password from a password manager) would get their focus
        /// stolen back on the next unrelated state change, which is a worse
        /// bug than the one this fixes. Tracks the identity of the last
        /// configured NSWindow (rather than a plain "did this ever run"
        /// flag) so that if SwiftUI ever hands this a genuinely different
        /// NSWindow instance for the same Window(id:) scene, it still
        /// reconfigures for it. Does NOT gate the notification-driven path
        /// below — that one is always a direct response to an explicit
        /// user click, never an incidental re-render, so it's safe (and
        /// necessary) for it to run unconditionally every time.
        var configuredWindow: ObjectIdentifier?
        var observerToken: NSObjectProtocol?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleFirstAppearanceConfiguration(for: view, coordinator: context.coordinator)
        context.coordinator.observerToken = NotificationCenter.default.addObserver(
            forName: WindowForegroundRequest.notificationName,
            object: nil,
            queue: .main
        ) { [weak view, windowID] notification in
            guard
                let requestedID = notification.userInfo?[WindowForegroundRequest.windowIDKey] as? String,
                requestedID == windowID,
                let window = view?.window
            else { return }
            Self.reassertForeground(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleFirstAppearanceConfiguration(for: nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let token = coordinator.observerToken {
            NotificationCenter.default.removeObserver(token)
        }
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
            Self.reassertForeground(window)
        }
    }

    private static func reassertForeground(_ window: NSWindow) {
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension View {
    /// Attaches `WindowActivationAccessor` behind this view — see its doc
    /// comment for exactly what this fixes. Apply once, to the outermost
    /// content of each `Window(...)` scene in ZeroServerControlApp.swift,
    /// passing the SAME id used for that scene's `Window(id:)` and every
    /// `openWindow(id:)` call site that targets it.
    func forceForegroundOnFirstAppearance(windowID: String) -> some View {
        background(WindowActivationAccessor(windowID: windowID))
    }
}
