import Foundation

/// One row of a node's status-transition audit trail, as returned by
/// `machineStatusEvents` (ZSC dashboard). Deliberately does NOT decode the
/// backend's `metadata` field (arbitrary JSON: agentVersion/ip/cpu-mem-disk
/// snapshot/tunnelStatus at the time of the event) — same "only decode what
/// the UI actually uses" philosophy as RemoteNode, so a backend-side
/// metadata shape change can't break this client.
struct MachineStatusEvent: Identifiable, Decodable, Equatable {
    let id: String
    let machineId: String
    let previousStatus: RemoteNodeStatus
    let newStatus: RemoteNodeStatus
    /// Free-form origin string (e.g. "AGENT_HEARTBEAT", "OFFLINE_JOB") — kept
    /// as raw String rather than a closed enum, same tolerant-decode
    /// reasoning as RemoteNodeStatus.unknown: the backend can add new
    /// sources without this client failing to decode the event at all.
    let source: String
    let reason: String?
    let createdAt: Date
}

extension MachineStatusEvent {
    /// e.g. "Idle → Overloaded" — same NSLocalizedString + String(format:)
    /// pattern RemoteNode.statusHintLabel already uses, so the view stays a
    /// dumb renderer and doesn't reassemble localized copy itself.
    var transitionLabel: String {
        let format = NSLocalizedString(
            "dashboard.status_transition_format",
            value: "%@ → %@",
            comment: "previousStatus.label, newStatus.label"
        )
        return String(format: format, previousStatus.label, newStatus.label)
    }
}
