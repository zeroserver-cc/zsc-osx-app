import Foundation

private func makeNode(status: RemoteNodeStatus, workloadsPaused: Bool, currentUsage: MachineUsage? = nil) -> RemoteNode {
    RemoteNode(
        id: "m1",
        name: "test-node",
        status: status,
        workloadsPaused: workloadsPaused,
        lastHeartbeat: nil,
        agentVersion: nil,
        updatedAt: Date(timeIntervalSince1970: 0),
        createdAt: Date(timeIntervalSince1970: 0),
        currentUsage: currentUsage
    )
}

/// Locks in the exact product rules behind RemoteNodeRowView's click
/// behavior and icon selection (see RemoteNode.swift's PrimaryAction /
/// primaryActionIconSystemName) across every status this app knows about,
/// both paused and unpaused. This is pure Model-layer logic with no
/// SwiftUI dependency, so — unlike the view itself — it's fully testable
/// here; the view is a thin, largely untested wiring layer on top of it.
func runRemoteNodeActionLogicTests(_ t: TestRunner) {
    struct Expectation {
        let status: RemoteNodeStatus
        let paused: Bool
        let isConnected: Bool
        let primaryAction: RemoteNode.PrimaryAction
        let iconSystemName: String?
    }

    let cases: [Expectation] = [
        // Connected statuses (Online/Idle/Busy/Overloaded), unpaused:
        // running -> primary action is Pause, icon is the pause glyph.
        Expectation(status: .online, paused: false, isConnected: true, primaryAction: .pause, iconSystemName: "pause.fill"),
        Expectation(status: .idle, paused: false, isConnected: true, primaryAction: .pause, iconSystemName: "pause.fill"),
        Expectation(status: .busy, paused: false, isConnected: true, primaryAction: .pause, iconSystemName: "pause.fill"),
        Expectation(status: .overloaded, paused: false, isConnected: true, primaryAction: .pause, iconSystemName: "pause.fill"),

        // Connected statuses, paused: primary action is Start (resume),
        // icon is the play glyph.
        Expectation(status: .online, paused: true, isConnected: true, primaryAction: .resume, iconSystemName: "play.fill"),
        Expectation(status: .idle, paused: true, isConnected: true, primaryAction: .resume, iconSystemName: "play.fill"),
        Expectation(status: .busy, paused: true, isConnected: true, primaryAction: .resume, iconSystemName: "play.fill"),
        Expectation(status: .overloaded, paused: true, isConnected: true, primaryAction: .resume, iconSystemName: "play.fill"),

        // Offline: fully inert regardless of workloadsPaused — there is no
        // live channel to this node at all, so no icon reveals and no
        // click action exists (verified against zsc-agent/zsc-backend:
        // no start/wake/restart command exists anywhere).
        Expectation(status: .offline, paused: false, isConnected: false, primaryAction: .none, iconSystemName: nil),
        Expectation(status: .offline, paused: true, isConnected: false, primaryAction: .none, iconSystemName: nil),

        // Registering, unpaused/paused: same shape as offline.
        Expectation(status: .registering, paused: false, isConnected: false, primaryAction: .none, iconSystemName: nil),
        Expectation(status: .registering, paused: true, isConnected: false, primaryAction: .none, iconSystemName: nil),

        // Unknown (forward-compat: some future backend status this client
        // doesn't recognize yet) behaves like any other disconnected state.
        Expectation(status: .unknown("SOME_FUTURE_STATUS"), paused: false, isConnected: false, primaryAction: .none, iconSystemName: nil),
        Expectation(status: .unknown("SOME_FUTURE_STATUS"), paused: true, isConnected: false, primaryAction: .none, iconSystemName: nil),
    ]

    for c in cases {
        let label = "status=\(c.status) paused=\(c.paused)"
        t.run("RemoteNode action logic: \(label)") {
            let node = makeNode(status: c.status, workloadsPaused: c.paused)
            t.expectEqual(node.isConnected, c.isConnected, "isConnected for \(label)")
            t.expectEqual(node.primaryAction, c.primaryAction, "primaryAction for \(label)")
            t.expectEqual(node.primaryActionIconSystemName, c.iconSystemName, "primaryActionIconSystemName for \(label)")

            // statusHintLabel must always carry the connectivity label
            // (status.label never changes just because a click paused the
            // node), with ", Paused" appended whenever workloadsPaused is
            // true — this is what fixes "shouldn't the status change after
            // I click a node?": the answer is the hint, not `status` itself.
            let expectedHint = c.paused ? "\(c.status.label), Paused" : c.status.label
            t.expectEqual(node.statusHintLabel, expectedHint, "statusHintLabel for \(label)")
        }
    }
}

/// Locks in RemoteNode.usageSummary's rules — see its doc comment in
/// RemoteNode.swift for the reasoning behind each of these.
func runRemoteNodeUsageSummaryTests(_ t: TestRunner) {
    let fullUsage = MachineUsage(cpuPercent: 12.4, memoryPercent: 45.6, diskPercent: 30.0, recordedAt: Date(timeIntervalSince1970: 0))
    let noDiskUsage = MachineUsage(cpuPercent: 12.4, memoryPercent: 45.6, diskPercent: nil, recordedAt: Date(timeIntervalSince1970: 0))

    t.run("usageSummary is nil when there's no telemetry at all") {
        let node = makeNode(status: .online, workloadsPaused: false, currentUsage: nil)
        t.expect(node.usageSummary == nil, "no currentUsage -> no usage summary")
    }

    t.run("usageSummary is nil for a disconnected node, even with a last-known reading") {
        let node = makeNode(status: .offline, workloadsPaused: false, currentUsage: fullUsage)
        t.expect(node.usageSummary == nil, "offline nodes must not surface a possibly-stale reading")
    }

    t.run("usageSummary includes CPU+RAM+DISK, in that order, when all three are present") {
        let node = makeNode(status: .online, workloadsPaused: false, currentUsage: fullUsage)
        let metrics = node.usageSummary
        t.expectEqual(metrics?.count, 3, "expected CPU, RAM, and DISK entries")
        t.expectEqual(metrics?[0].label, "CPU")
        t.expectEqual(metrics?[0].percent, 12, "cpuPercent rounds 12.4 -> 12")
        t.expectEqual(metrics?[1].label, "RAM")
        t.expectEqual(metrics?[1].percent, 46, "memoryPercent rounds 45.6 -> 46")
        t.expectEqual(metrics?[2].label, "DISK")
        t.expectEqual(metrics?[2].percent, 30)
    }

    t.run("usageSummary omits DISK (but keeps CPU+RAM) when diskPercent is nil") {
        let node = makeNode(status: .busy, workloadsPaused: false, currentUsage: noDiskUsage)
        let metrics = node.usageSummary
        t.expectEqual(metrics?.count, 2, "diskPercent: nil -> no DISK entry")
        t.expect(metrics?.contains(where: { $0.label == "DISK" }) == false, "DISK must not appear at all")
    }

    t.run("usageSummary is still populated for a paused-but-connected node") {
        // Pausing only sets workloadsPaused; it doesn't disconnect the
        // node, so its live resource usage is still meaningful to show.
        let node = makeNode(status: .idle, workloadsPaused: true, currentUsage: fullUsage)
        t.expectEqual(node.usageSummary?.count, 3)
    }

    // H2 (correctness audit): Int(someDouble.rounded()) traps (crashes,
    // not throws) on .nan/.infinity, and passed negative/>100 values
    // through verbatim - both are real possibilities for server-reported
    // telemetry, and this runs on every poll tick. These lock in that
    // non-finite values become 0 and everything else clamps into 0...100,
    // instead of crashing the whole app or rendering "CPU -12%".
    t.run("usageSummary does not crash and clamps to 0 for non-finite telemetry (.infinity/.nan)") {
        let nonFiniteUsage = MachineUsage(cpuPercent: .infinity, memoryPercent: .nan, diskPercent: -.infinity, recordedAt: Date(timeIntervalSince1970: 0))
        let node = makeNode(status: .online, workloadsPaused: false, currentUsage: nonFiniteUsage)
        let metrics = node.usageSummary
        t.expectEqual(metrics?.count, 3, "non-finite values must still produce entries, not crash or vanish")
        t.expectEqual(metrics?[0].percent, 0, "cpuPercent: .infinity -> 0, not a trap")
        t.expectEqual(metrics?[1].percent, 0, "memoryPercent: .nan -> 0, not a trap")
        t.expectEqual(metrics?[2].percent, 0, "diskPercent: -.infinity -> 0, not a trap")
    }

    t.run("usageSummary clamps out-of-range telemetry into 0...100") {
        let outOfRangeUsage = MachineUsage(cpuPercent: -12.0, memoryPercent: 137.5, diskPercent: 250.0, recordedAt: Date(timeIntervalSince1970: 0))
        let node = makeNode(status: .online, workloadsPaused: false, currentUsage: outOfRangeUsage)
        let metrics = node.usageSummary
        t.expectEqual(metrics?[0].percent, 0, "cpuPercent: -12.0 clamps up to 0, not shown as negative")
        t.expectEqual(metrics?[1].percent, 100, "memoryPercent: 137.5 clamps down to 100")
        t.expectEqual(metrics?[2].percent, 100, "diskPercent: 250.0 clamps down to 100")
    }
}
