import Foundation

/// Fetches and polls the account's nodes (`myMachines`) and exposes
/// pause/resume/forceStop actions with independent per-node in-flight/
/// error state — unlike AgentController (a single local agent), multiple
/// remote nodes can have actions in flight at the same time.
@MainActor
final class RemoteNodesController: ObservableObject {
    struct NodeActionState: Equatable {
        var isInFlight = false
        var errorMessage: String?
    }

    @Published private(set) var nodes: [RemoteNode] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastFetchError: String?
    @Published private(set) var actionStates: [String: NodeActionState] = [:]
    /// True for the duration of forceStopAll()'s loop — drives the bulk
    /// button's own disabled/progress state, separate from any individual
    /// node's actionStates (which also update as the loop reaches each one).
    @Published private(set) var isForceStoppingAll = false

    private let apiClient: APIClient
    private weak var session: AccountSession?
    private var pollTask: Task<Void, Never>?
    private var isFetching = false

    // Unlike AgentController's 3s local `launchctl print` (near-instant,
    // always available), this is a real network call to a remote API that
    // can be offline, rate-limited, or slow. 10s base — frequent enough
    // that a change made elsewhere shows up reasonably fast, rare enough
    // it isn't hammering the API — with exponential backoff up to 60s on
    // repeated failure so a backend outage doesn't turn into a retry
    // storm; resets to the base interval on the next success.
    private let basePollInterval: Duration = .seconds(10)
    private let maxPollInterval: Duration = .seconds(60)

    init(apiClient: APIClient, session: AccountSession) {
        self.apiClient = apiClient
        self.session = session
        startPolling()
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            var interval = self?.basePollInterval ?? .seconds(10)
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshNow()
                interval = self.lastFetchError == nil
                    ? self.basePollInterval
                    : min(interval * 2, self.maxPollInterval)
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Note: unlike AgentController, this does NOT gate on a global
    /// "action in flight" flag before polling — myMachines is a read-only
    /// call that doesn't race pause/resume/forceStop the way a status poll
    /// could race a local start/stop mid-transition, and multiple nodes can
    /// have independent in-flight actions simultaneously, so there is no
    /// single flag to gate on anyway.
    func refreshNow() async {
        guard !isFetching else { return }
        guard case .signedIn = session?.state else {
            nodes = []
            isLoading = false
            return
        }
        isFetching = true
        defer { isFetching = false }
        isLoading = nodes.isEmpty && lastFetchError == nil
        do {
            // Sorted here rather than trusted from the server as-is:
            // zsc-backend's own myMachines query is ordered the same way
            // now (oldest-created-first), but this had no ORDER BY at all
            // until that fix, and was visibly reshuffling on every poll as
            // a result — sorting independently client-side means this
            // list's order can never regress again even if the backend
            // does, for this or any future query. `id` is a secondary,
            // fully deterministic tie-break: `sorted` is stable, but that
            // only preserves *this poll's* input order for two nodes
            // sharing the exact same createdAt (seed data, a
            // batch-provisioned fleet) — without a real tie-break, those
            // two rows could still swap position every poll if the
            // backend's own tie order isn't identical across separate
            // queries, reintroducing the exact symptom this sort exists
            // to eliminate.
            let freshNodes = try await apiClient.myMachines()
                .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
            nodes = freshNodes
            // H5 (correctness audit): without this, actionStates grows
            // forever for any node deleted server-side while an action
            // was in flight for it (performAction's nodes.firstIndex
            // lookup already silently drops the nodes-array update in
            // that case, but nothing removed the actionStates entry).
            let currentIds = Set(freshNodes.map(\.id))
            actionStates = actionStates.filter { currentIds.contains($0.key) }
            lastFetchError = nil
        } catch {
            lastFetchError = PresentableError.message(for: error)
            // Deliberately keep showing the last-known `nodes` rather than
            // clearing them on a transient failure — flashing to an empty
            // list on every hiccup would be worse UX than slightly stale data.
        }
        isLoading = false
    }

    func pause(nodeId: String) async {
        await performAction(nodeId: nodeId) { try await self.apiClient.pauseMachine(id: nodeId) }
    }

    func resume(nodeId: String) async {
        await performAction(nodeId: nodeId) { try await self.apiClient.resumeMachine(id: nodeId) }
    }

    /// The UI layer (ForceStopConfirmation) MUST have already gotten
    /// explicit user confirmation before calling this — this method itself
    /// performs no confirmation, by design, so that concern stays a pure,
    /// independently reasoned-about UI responsibility.
    func forceStop(nodeId: String) async {
        await performAction(nodeId: nodeId) { try await self.apiClient.forceStopMachine(id: nodeId) }
    }

    /// M3 (correctness audit): a provider account can have a couple
    /// hundred nodes; running forceStopAll() one mutation at a time would
    /// lock the bulk button (and the account's whole "stop everything"
    /// intent) for well over a minute. Bounded rather than unbounded
    /// concurrency — mirrors the httpMaxConnectionsPerHost-style ceilings
    /// most HTTP stacks apply, so this can't itself look like a
    /// self-inflicted burst against the backend.
    private static let maxConcurrentForceStops = 8

    /// Force-stops every node currently in `nodes`, reusing
    /// forceStop(nodeId:) unchanged — each node's own actionStates entry
    /// updates as its task reaches it, so partial failures (e.g. a node
    /// that's already offline) surface per-row automatically, with no new
    /// per-node state needed here. The UI layer (ForceStopAllConfirmation)
    /// must have already gotten explicit confirmation before calling this,
    /// same convention as the single-node forceStop.
    func forceStopAll() async {
        isForceStoppingAll = true
        let nodeIds = nodes.map(\.id)
        await withTaskGroup(of: Void.self) { group in
            var nextIndex = 0
            func startNext() {
                guard nextIndex < nodeIds.count else { return }
                let nodeId = nodeIds[nextIndex]
                nextIndex += 1
                group.addTask { await self.forceStop(nodeId: nodeId) }
            }
            for _ in 0..<min(Self.maxConcurrentForceStops, nodeIds.count) {
                startNext()
            }
            while await group.next() != nil {
                startNext()
            }
        }
        isForceStoppingAll = false
    }

    /// Pessimistic update: wait for the server's response, then adopt the
    /// RemoteNode it returns as the new truth for that row. Chosen over an
    /// optimistic update because these are server-gated state transitions
    /// that can fail for reasons the client can't predict, and Force Stop
    /// is irreversible — an optimistic "stopped" UI that then has to roll
    /// back on failure would be exactly the wrong UX for a destructive
    /// action. The per-node isInFlight spinner (disables that row's
    /// buttons) makes the small added latency clear and acceptable for an
    /// infrequent admin action.
    private func performAction(nodeId: String, _ operation: @escaping () async throws -> RemoteNode) async {
        actionStates[nodeId] = NodeActionState(isInFlight: true, errorMessage: nil)
        do {
            let updated = try await operation()
            if let idx = nodes.firstIndex(where: { $0.id == nodeId }) { nodes[idx] = updated }
            actionStates[nodeId] = NodeActionState(isInFlight: false, errorMessage: nil)
        } catch {
            actionStates[nodeId] = NodeActionState(isInFlight: false, errorMessage: PresentableError.message(for: error))
        }
    }
}
