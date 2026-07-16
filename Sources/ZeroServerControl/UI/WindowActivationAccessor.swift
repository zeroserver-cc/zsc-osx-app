import SwiftUI
import AppKit

/// Bridges to the real AppKit `NSWindow` behind a SwiftUI `Window` scene's
/// content, so this app's ad hoc windows (Login/Settings/Dashboard) behave
/// like a normal app's windows instead of a background utility's.
///
/// This app is `.accessory` (LSUIElement — no Dock icon, no app-switcher
/// entry). Every place that opens one of these windows already calls
/// `NSApp.activate(ignoringOtherApps: true)` right before `openWindow(id:)`
/// — that alone turned out to be insufficient for three related, reported
/// bugs, all sharing the same root cause:
///
/// - A freshly-opened window could appear BEHIND another app's already-
///   frontmost window: `activate(ignoringOtherApps:)` fires before the
///   window actually exists (SwiftUI creates it asynchronously relative to
///   the call), so there's nothing yet to bring forward at the moment
///   activation happens. `orderFrontRegardless()` — the AppKit API
///   documented specifically for "move this window to the front of the
///   screen list even if this app isn't the active one" — fixes this once
///   the window genuinely exists.
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
private struct WindowActivationAccessor: NSViewRepresentable {
    final class Coordinator {
        /// Guards this from re-firing on every SwiftUI update pass (e.g.
        /// every keystroke in a form re-renders this view's siblings) —
        /// without it, a user who deliberately switches to a different app
        /// while this window is still open (e.g. to copy a password from a
        /// password manager) would get their focus stolen back on the next
        /// unrelated state change, which is a worse bug than the one this
        /// fixes. Runs exactly once, the first time the underlying NSView
        /// is actually attached to a window.
        var didConfigure = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleConfiguration(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleConfiguration(for: nsView, coordinator: context.coordinator)
    }

    /// `.window` is nil at the moment `makeNSView`/`updateNSView` run in
    /// many cases — the view isn't attached to its window's hierarchy yet
    /// on that exact call. Deferring to the next run-loop turn is the
    /// standard way to observe attachment; `updateNSView` runs again on
    /// every subsequent SwiftUI render pass regardless, so this reliably
    /// catches the moment `.window` becomes non-nil.
    private func scheduleConfiguration(for view: NSView, coordinator: Coordinator) {
        guard !coordinator.didConfigure else { return }
        DispatchQueue.main.async {
            guard let window = view.window, !coordinator.didConfigure else { return }
            coordinator.didConfigure = true
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

extension View {
    /// Attaches `WindowActivationAccessor` behind this view — see its doc
    /// comment for exactly what this fixes. Apply once, to the outermost
    /// content of each `Window(...)` scene in ZeroServerControlApp.swift.
    func forceForegroundOnFirstAppearance() -> some View {
        background(WindowActivationAccessor())
    }
}
