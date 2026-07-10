import SwiftUI

/// The small colored dot + status text + optional caption shown in
/// Settings' "This Mac's Agent" section. This is where color lives (the
/// persistent menu bar glyph itself stays monochrome per Apple's HIG for
/// status items — see MenuBarIconProvider).
struct StatusRowView: View {
    let status: AgentStatus

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.shortLabel)
                    .font(.body)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var dotColor: Color {
        switch status {
        case .running:
            return .green
        case .stopped, .notInstalled:
            return .gray
        case .starting, .stopping:
            return .orange
        case .unknown:
            return .red
        }
    }

    /// A secondary line with extra detail: the PID while running, or the
    /// reason string when we couldn't determine status confidently. Nil
    /// (no second line) for the plain, self-explanatory states.
    private var caption: String? {
        switch status {
        case let .running(pid):
            guard pid > 0 else { return nil }
            let format = NSLocalizedString("agent.pid_format", value: "PID %d", comment: "e.g. PID 1234")
            return String(format: format, pid)
        case let .unknown(reason):
            return reason
        case .stopped, .starting, .stopping, .notInstalled:
            return nil
        }
    }
}
