import Foundation

/// Mirrors zsc-backend's MachineStatus. Decodes tolerantly (`.unknown(String)`
/// for any raw value we don't recognize) rather than failing the whole
/// decode — same philosophy as AgentStatus.unknown(reason:): surface
/// unexpected server states, never silently misreport or crash on a
/// backend addition.
///
/// NOTE: "paused" is deliberately NOT a case here. The backend models
/// pause as its own orthogonal `workloadsPaused` boolean on Machine, not a
/// status value — a paused node still reports its real status (e.g.
/// .online) alongside workloadsPaused: true. See RemoteNode below.
enum RemoteNodeStatus: Equatable, Decodable {
    case offline, registering, idle, busy, overloaded, online
    case unknown(String)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw.uppercased() {
        case "OFFLINE": self = .offline
        case "REGISTERING": self = .registering
        case "IDLE": self = .idle
        case "BUSY": self = .busy
        case "OVERLOADED": self = .overloaded
        case "ONLINE": self = .online
        default: self = .unknown(raw)
        }
    }

    var label: String {
        switch self {
        case .offline: return NSLocalizedString("status.offline", value: "Offline", comment: "Node connectivity status")
        case .registering: return NSLocalizedString("status.registering", value: "Registering…", comment: "Node connectivity status")
        case .idle: return NSLocalizedString("status.idle", value: "Idle", comment: "Node connectivity status")
        case .busy: return NSLocalizedString("status.busy", value: "Busy", comment: "Node connectivity status")
        case .overloaded: return NSLocalizedString("status.overloaded", value: "Overloaded", comment: "Node connectivity status")
        case .online: return NSLocalizedString("status.online", value: "Online", comment: "Node connectivity status")
        // Forward-compat passthrough of a raw server value this client
        // doesn't recognize yet — deliberately NOT localized, since it's
        // arbitrary future backend text, not app-authored copy.
        case .unknown(let raw): return raw.capitalized
        }
    }
}

/// The latest telemetry sample for a node, as reported via its own
/// heartbeat (ZSC-144). `cpuPercent`/`memoryPercent` are always present
/// whenever a node has ever reported at all; `diskPercent` is
/// independently optional — some agent versions/platforms don't report
/// disk usage at all, orthogonally to whether the node itself is online.
struct MachineUsage: Decodable, Equatable {
    let cpuPercent: Double
    let memoryPercent: Double
    let diskPercent: Double?
    let recordedAt: Date
}

/// A node (machine) on the account, as returned by `myMachines` and the
/// pause/resume/forceStop mutations. Deliberately decodes only the fields
/// this app's UI actually needs (id/name/status/workloadsPaused/
/// lastHeartbeat/agentVersion/updatedAt/createdAt/currentUsage) — dropping
/// userId/token/specs from the query entirely means a backend schema
/// change to those fields can't break this client.
struct RemoteNode: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let status: RemoteNodeStatus
    /// Durable "stopped accepting new work" flag — orthogonal to `status`.
    /// Drives which action (Pause vs Resume) the UI shows for this node.
    let workloadsPaused: Bool
    let lastHeartbeat: Date?
    let agentVersion: String?
    let updatedAt: Date
    /// Drives RemoteNodesController's sort order (oldest first) — the
    /// backend's own myMachines query is now ordered the same way, but the
    /// client sorts independently too rather than trusting server order
    /// blindly for something this visible (see RemoteNodesController).
    let createdAt: Date
    /// Nil for a node that's never sent a heartbeat with telemetry. Can
    /// still be non-nil for a node that's currently offline (its last
    /// known reading) — `usageSummary` below deliberately does NOT surface
    /// it in that case, since showing possibly-stale CPU/RAM numbers under
    /// an already-dimmed, fully-inert offline row would be misleading
    /// rather than useful.
    let currentUsage: MachineUsage?
}

/// The decision logic behind each node row's click behavior in
/// RemoteNodeRowView, pulled out here (rather than left inline in the view)
/// specifically so it's plain, testable Swift with no SwiftUI dependency —
/// see Scripts/tests/RemoteNodeActionLogicTests.swift for the full
/// status × workloadsPaused matrix this locks in as regression tests.
extension RemoteNode {
    /// What a direct tap on the row's name does.
    enum PrimaryAction: Equatable {
        case pause
        case resume
        /// Disconnected (offline/registering/unknown) — there is no live
        /// channel to this node at all once its heartbeat lapses (verified
        /// against zsc-agent/zsc-backend: no start/wake/restart command
        /// exists anywhere, and the backend's own response to an offline
        /// node is to reschedule its workloads elsewhere, never to restart
        /// it). The row is fully inert in this case, regardless of
        /// `workloadsPaused` — there's nothing a click could meaningfully
        /// do that the user could observe.
        case none
    }

    /// True for any status where the agent is actually up and reachable —
    /// Idle/Busy/Overloaded all count as "connected", not just the literal
    /// .online case, per the product decision on what "click to pause"
    /// should cover.
    var isConnected: Bool {
        switch status {
        case .online, .idle, .busy, .overloaded: return true
        case .offline, .registering, .unknown: return false
        }
    }

    /// Disconnected nodes are always `.none` — see PrimaryAction.none.
    /// Only a connected node has a real pause/resume action: unpaused
    /// means it's actively working (click pauses), paused means it isn't
    /// (click resumes).
    var primaryAction: PrimaryAction {
        guard isConnected else { return .none }
        return workloadsPaused ? .resume : .pause
    }

    /// The SF Symbol reflecting what a click currently does — shown on the
    /// left of the row, inside a circular background drawn separately by
    /// the view (RemoteNodeRowView), matching the Bluetooth menu's
    /// device-icon-in-a-circle look. Deliberately the PLAIN glyph, not the
    /// self-contained "*.circle.fill" variant — that would draw its own
    /// circle and double up with the one the view adds. `nil` for `.none`
    /// — the view reveals no icon at all for a disconnected node.
    var primaryActionIconSystemName: String? {
        switch primaryAction {
        case .pause: return "pause.fill"
        case .resume: return "play.fill"
        case .none: return nil
        }
    }

    /// Shown in the row as "name (hint)" — `status.label` alone reflects
    /// only connectivity (Idle/Busy/Online/Offline), which never changes
    /// just because a click paused/resumed the node, so `workloadsPaused`
    /// is appended explicitly whenever true rather than folded into
    /// `status` (which stays a pure connectivity signal — see the note on
    /// RemoteNodeStatus).
    var statusHintLabel: String {
        guard workloadsPaused else { return status.label }
        let format = NSLocalizedString("status.paused_suffix", value: "%@, Paused", comment: "status.label with this node also currently paused")
        return String(format: format, status.label)
    }

    /// One row's worth of resource-usage readout — icon, localized label,
    /// and a rounded whole-number percent, in the fixed CPU/RAM/Disk order
    /// RemoteNodeRowView renders them in.
    struct UsageMetric: Equatable {
        let iconSystemName: String
        let label: String
        let percent: Int
    }

    /// `nil` whenever there's nothing worth showing: no telemetry has ever
    /// arrived, OR the node isn't currently connected (see the note on
    /// `currentUsage` above for why a stale reading is deliberately
    /// withheld rather than shown under an inert row). CPU/RAM are always
    /// included together whenever telemetry exists at all; Disk is
    /// independently omitted when `diskPercent` is nil.
    var usageSummary: [UsageMetric]? {
        guard isConnected, let usage = currentUsage else { return nil }
        var metrics: [UsageMetric] = [
            UsageMetric(
                iconSystemName: "cpu",
                label: NSLocalizedString("usage.cpu", value: "CPU", comment: "Resource usage label"),
                percent: Int(usage.cpuPercent.rounded())
            ),
            UsageMetric(
                iconSystemName: "memorychip",
                label: NSLocalizedString("usage.ram", value: "RAM", comment: "Resource usage label"),
                percent: Int(usage.memoryPercent.rounded())
            )
        ]
        if let diskPercent = usage.diskPercent {
            metrics.append(UsageMetric(
                iconSystemName: "internaldrive",
                label: NSLocalizedString("usage.disk", value: "DISK", comment: "Resource usage label"),
                percent: Int(diskPercent.rounded())
            ))
        }
        return metrics
    }
}
