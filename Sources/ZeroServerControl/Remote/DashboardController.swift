import Foundation

/// Drives the Dashboard window's node-detail pane: which node is selected,
/// its last-24h telemetry series, and its recent status-event timeline.
/// Deliberately separate from RemoteNodesController (which owns the node
/// LIST and current-snapshot polling at a faster 10s cadence) — a 24h chart
/// doesn't need to refresh nearly as often, and mixing the two concerns
/// would make RemoteNodesController's existing tests harder to reason about.
///
/// Mirrors RemoteNodesController's idiom deliberately: selection changes
/// don't trigger a fetch by themselves (see `select(nodeId:)`) — the view
/// is responsible for calling `refreshDetail()` explicitly (via `.task(id:)`
/// on the selected node id), same as RemoteNodesSectionView explicitly
/// fires `refreshNow()` on a sign-in transition rather than the controller
/// doing it implicitly. This keeps `refreshDetail()` directly, deterministically
/// testable with no dependency on Task scheduling timing.
@MainActor
final class DashboardController: ObservableObject {
    @Published private(set) var selectedNodeId: String?
    @Published private(set) var telemetry: [MachineUsage] = []
    @Published private(set) var statusEvents: [MachineStatusEvent] = []
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var detailError: String?

    private let apiClient: APIClient
    private weak var session: AccountSession?
    private var pollTask: Task<Void, Never>?
    private var isFetchingDetail = false

    /// Matches the backend's own hard cap — `machineTelemetry` clamps
    /// `sinceHours` to [1, 24] server-side regardless of what's requested,
    /// since telemetry itself is pruned after 24h.
    static let telemetryWindowHours = 24
    static let statusEventLimit = 100

    /// Slower than RemoteNodesController's 10s node-list poll — a 24h chart
    /// doesn't need near-real-time refresh, and this is a second concurrent
    /// poll loop against the same account while the Dashboard window is open.
    private let pollInterval: Duration = .seconds(30)

    init(apiClient: APIClient, session: AccountSession) {
        self.apiClient = apiClient
        self.session = session
    }

    /// Called when the user picks a different node in the sidebar. Purely
    /// synchronous state reset — see the type doc comment for why the
    /// actual fetch is the view's responsibility, not this method's.
    func select(nodeId: String) {
        guard nodeId != selectedNodeId else { return }
        selectedNodeId = nodeId
        telemetry = []
        statusEvents = []
        detailError = nil
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: self.pollInterval)
                guard !Task.isCancelled else { return }
                await self.refreshDetail()
            }
        }
    }

    /// Called from the Dashboard window's onDisappear — without this, the
    /// poll loop would keep hitting the network every 30s even after the
    /// user closes the window, for as long as the app process lives.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshDetail() async {
        guard let nodeId = selectedNodeId else { return }
        guard !isFetchingDetail else { return }
        guard case .signedIn = session?.state else {
            telemetry = []
            statusEvents = []
            isLoadingDetail = false
            return
        }
        isFetchingDetail = true
        defer { isFetchingDetail = false }
        isLoadingDetail = telemetry.isEmpty && statusEvents.isEmpty && detailError == nil
        do {
            async let telemetryResult = apiClient.machineTelemetry(
                machineId: nodeId, sinceHours: Self.telemetryWindowHours
            )
            async let eventsResult = apiClient.machineStatusEvents(
                machineId: nodeId, sinceHours: Self.telemetryWindowHours, limit: Self.statusEventLimit
            )
            let (fetchedTelemetry, fetchedEvents) = try await (telemetryResult, eventsResult)
            telemetry = Self.sanitizedForChart(fetchedTelemetry)
            statusEvents = fetchedEvents.sorted { $0.createdAt > $1.createdAt }
            detailError = nil
        } catch {
            // Same "keep last-known data visible on a transient failure"
            // choice RemoteNodesController.refreshNow() already makes —
            // don't flash the chart to empty on a single hiccup.
            detailError = PresentableError.message(for: error)
        }
        isLoadingDetail = false
    }

    /// Non-finite points (NaN/Infinity) are a real possibility for
    /// server-reported telemetry — see RemoteNode.clampedPercent's doc
    /// comment on the crash-on-non-finite-telemetry bug this app already
    /// hit once. Swift Charts has no equivalent clamping of its own, so
    /// every point is filtered before it can reach a chart, and sorted by
    /// time since the backend gives no ordering guarantee.
    static func sanitizedForChart(_ points: [MachineUsage]) -> [MachineUsage] {
        points
            .filter { $0.cpuPercent.isFinite && $0.memoryPercent.isFinite && ($0.diskPercent?.isFinite ?? true) }
            .sorted { $0.recordedAt < $1.recordedAt }
    }
}
