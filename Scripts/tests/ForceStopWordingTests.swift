import Foundation

/// M5 (UI/HIG audit): locks in that the menu button and the confirmation
/// alert's destructive button always agree on singular vs. plural wording —
/// see ForceStopWording.swift's doc comment for the mismatch this replaces.
func runForceStopWordingTests(_ t: TestRunner) {
    t.run("menuButtonLabel singularizes for exactly one node") {
        t.expectEqual(ForceStopWording.menuButtonLabel(nodeCount: 1), "Force Stop This Agent…")
    }

    t.run("menuButtonLabel pluralizes and interpolates the count for zero or many nodes") {
        t.expectEqual(ForceStopWording.menuButtonLabel(nodeCount: 0), "Force Stop All 0 Agents…")
        t.expectEqual(ForceStopWording.menuButtonLabel(nodeCount: 5), "Force Stop All 5 Agents…")
    }

    t.run("confirmButtonLabel singularizes for exactly one node") {
        t.expectEqual(ForceStopWording.confirmButtonLabel(nodeCount: 1), "Force Stop")
    }

    t.run("confirmButtonLabel stays \"Force Stop All\" for zero or many nodes") {
        t.expectEqual(ForceStopWording.confirmButtonLabel(nodeCount: 0), "Force Stop All")
        t.expectEqual(ForceStopWording.confirmButtonLabel(nodeCount: 5), "Force Stop All")
    }
}
