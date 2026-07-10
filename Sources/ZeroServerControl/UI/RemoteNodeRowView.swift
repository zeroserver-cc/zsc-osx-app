import SwiftUI

/// A single node's row in the "My Nodes" menu, matching the macOS
/// Bluetooth menu bar item's paired-device rows: an icon on the left whose
/// glyph reflects what a click currently does, and the whole row is one
/// click target — no submenu. Force Stop lives elsewhere now (the bulk
/// "Force Stop All Agents" button in RemoteNodesSectionView), not per-row,
/// so this view only ever needs Pause/Resume.
///
/// The icon is always visible, not hover-revealed — an earlier attempt at
/// a Bluetooth-style hover-reveal (icon hidden until the pointer is over
/// the row) never worked reliably inside .menuBarExtraStyle(.menu)'s
/// native NSMenuItem-hosted content, even after fixing a known SwiftUI
/// .onHover/.contentShape defect. That's a hard platform limitation, not
/// something fixable from here, so hover-tracking was dropped entirely.
struct RemoteNodeRowView: View {
    let node: RemoteNode
    let actionState: RemoteNodesController.NodeActionState
    let onPause: () -> Void
    let onResume: () -> Void

    /// Emergency revert for the CPU/RAM/Disk usage line below: flip to
    /// `false` and rebuild to go straight back to today's single-line
    /// rows, no other changes needed — same one-flag pattern as
    /// MenuBarIconProvider.useMonochromeTemplateIcon.
    private static let showsResourceUsage = true

    var body: some View {
        // Only wrap in the extra VStack when there's actually an error line
        // to show — matches every other plain item in this menu, which has
        // zero extra wrapping/padding (see MenuContentView's plain Buttons).
        // The usage metrics are NOT a second line (see rowContent) — an
        // earlier attempt putting them in a VStack sibling alongside
        // rowContent rendered each metric as its own separate menu-row-like
        // line instead of one inline block, so they live inside rowContent's
        // own HStack instead, the one structural shape proven to render
        // correctly as a single line in this NSMenu-hosted view.
        if let error = actionState.errorMessage {
            VStack(alignment: .leading, spacing: 2) {
                rowContent
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        } else {
            rowContent
        }
    }

    /// Matches the Bluetooth menu's device-icon-in-a-circle sizing: a 28pt
    /// circular background with a 14pt glyph centered inside it — bigger
    /// than a plain inline SF Symbol would render by default.
    private let iconCircleDiameter: CGFloat = 28
    private let iconGlyphSize: CGFloat = 14

    private var rowContent: some View {
        Button(action: performPrimaryAction) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: iconCircleDiameter, height: iconCircleDiameter)
                        .opacity(showsIconBackground ? 1 : 0)
                    if actionState.isInFlight {
                        // Replaces the icon in place while an action is
                        // running — matches Bluetooth's "Connecting…"
                        // spinner-in-place behavior, rather than showing
                        // icon + spinner together.
                        ProgressView()
                            .controlSize(.small)
                    } else if let iconName = node.primaryActionIconSystemName {
                        Image(systemName: iconName)
                            .font(.system(size: iconGlyphSize))
                    }
                }
                .frame(width: iconCircleDiameter, height: iconCircleDiameter)
                nameAndStatusText
                    .foregroundStyle(node.primaryAction == .none ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
        // NOTE: .menuActionDismissBehavior(.disabled) — the modifier that
        // keeps a menu open across an item's action elsewhere in SwiftUI —
        // is explicitly @available(macOS, unavailable): Apple disabled this
        // specific case on macOS entirely (confirmed by the compiler's own
        // availability metadata, not just missing docs). There is no
        // supported way to keep .menuBarExtraStyle(.menu)'s native NSMenu
        // open across a click; it always dismisses. See CLAUDE.md/chat
        // history for the .window-style alternative this would require.
    }

    /// Whether the circular background itself should be visible — only for
    /// a node that actually has an icon to show, or while an action for
    /// this node is in flight (so the spinner has its background too).
    private var showsIconBackground: Bool {
        actionState.isInFlight || node.primaryActionIconSystemName != nil
    }

    /// Name + status hint + (if enabled and available) trailing CPU/RAM/
    /// Disk metrics, all as ONE concatenated Text value — deliberately not
    /// Image/HStack/ForEach. Those all rendered nothing at all when tried
    /// here (three separate SwiftUI-in-NSMenu structural attempts failed
    /// in three different ways this session: hover broke clicks, a VStack
    /// sibling became separate lines, and Image/ForEach content simply
    /// didn't render) — plain Text concatenation is the one mechanism
    /// that's actually proven reliable in this exact spot all along.
    private var nameAndStatusText: Text {
        var text = Text(node.name) + Text(" (\(node.statusHintLabel))").italic()
        if Self.showsResourceUsage, let metrics = node.usageSummary {
            for metric in metrics {
                text = text + Text(" · \(metric.label) \(metric.percent)%").font(.caption2)
            }
        }
        // Deliberately NOT .foregroundStyle(...) here — Text's own
        // foregroundStyle(_:) overload (the one that returns Text, letting
        // it stay part of this concatenation chain) is macOS 14+ only; this
        // app's floor is macOS 13. Applied at the call site instead, where
        // the ViewBuilder context only needs `some View`, so the compiler
        // uses the older, macOS-12+ generic View.foregroundStyle modifier.
        return text
    }

    private func performPrimaryAction() {
        switch node.primaryAction {
        case .pause: onPause()
        case .resume: onResume()
        case .none: break
        }
    }
}
