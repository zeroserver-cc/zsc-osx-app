# Roadmap

This roadmap starts from a hardened baseline: a full adversarial security,
correctness, and UI/HIG audit was completed first (critical command
injection, session-refresh races, a crash-on-non-finite-telemetry bug, and a
dozen smaller correctness/UI issues — all fixed, all covered by regression
tests). Consider that hardening pass done, not "Phase 1" itself.

## Phase 1 (shipped) — Resource Dashboard with an Auth Gate

Delivered: a Dashboard window (the app's new main resource view, reachable
via the "Dashboard" button at the top of the menu bar dropdown) showing, per
node, the last 24h of CPU/RAM/Disk telemetry as charts (Swift Charts —
native, zero new dependency), a current-snapshot header, and a recent
status-event timeline. Opening it while signed out forces sign-in first,
then opens automatically once that succeeds — no second click needed. This
was zsc-backend's `machineTelemetry`/`machineStatusEvents` data sitting
unused by this client (see the old candidate list below); it's now the
single most-used screen in the app pending real usage data.

Scope decision made explicitly at kickoff: the auth gate covers remote
nodes + the Dashboard only. This Mac's own local agent control (Settings →
"This Mac's Agent") stays ungated — it's a local `launchctl` operation with
no account/network involved, so requiring sign-in for it would add friction
with no security benefit.

**Original candidates considered for this phase** (kept for context on why
the others weren't picked first):

1. Node health notifications — the app was entirely *pull*-based; you only
   learned a node went offline/errored/overloaded by opening the menu.
2. **Historical usage graphs (picked, expanded into the full Dashboard
   above).** zsc-backend already retained 24h of telemetry per node
   (`machineTelemetry`/`getMachineTelemetryUseCase`), unused by this client.
3. Search/sort/filter for large accounts.
4. Multi-account switching without a full sign-out/sign-in cycle.

## Phase 2 — Node Health Notifications

The original Phase 1 candidate #1, now next up:

- Diffing logic in `RemoteNodesController` (compare each poll's fresh
  `nodes` against the previous snapshot, classify the transitions that
  matter).
- `UNUserNotificationCenter` integration (permission request, posting,
  respecting the user's per-event-type opt-in/out).
- A new Settings section for that opt-in/out control.
- Localized notification copy (EN / pt-BR, extending the existing
  `Localizable.strings` pipeline).
- Deep-link a tapped notification straight into that node's Dashboard
  detail pane (now that the Dashboard exists) instead of just opening the
  menu dropdown.

## Phase 3 — Release engineering & production readiness

Now that this is public:

- GitHub Actions CI — build + `Scripts/run-tests.sh` on every PR
  (zsc-backend already has a `ci.yml` to model this on).
- Developer ID signing + notarization — removes the Gatekeeper
  right-click-to-open friction every new user hits today with the ad-hoc
  signed build.
- A lightweight auto-update mechanism (Sparkle, or a GitHub-Releases-based
  version checker).
- Basic crash reporting.

## Phase 4 — Growth

- Multi-account support.
- Search/sort/filter for large accounts (deferred from Phase 1's candidate
  list).
- Revisiting the `.menuBarExtraStyle(.window)` rewrite — the only way to get
  a dropdown that stays open across a click, which `.menu` style
  fundamentally can't do on macOS.

## Insights gerados por IA (a partir do scan de zsc-agent/zsc-agent-runner/zsc-backend/zsc-cli/zsc-osx-app)

A curated list from scanning all five sibling repos while building the
Dashboard, split by whether they need new backend/agent work first or can
ship from this client alone.

**Client-only** (the data already exists in zsc-backend's GraphQL schema —
nothing to build server-side):

- AI Capability badges per node (`Machine.specs.aiCapabilities`:
  gpu/llm/video/audio/image, gpuModel, vramMb) — zsc-agent already detects
  and reports this on every heartbeat's `specs`, but no screen shows it.
  Lets a provider see at a glance which nodes can host GPU/LLM workloads.
- Extend the Dashboard's status timeline to also show application-instance
  status (`applicationInstancesByMachine` — PENDING/RUNNING/ERROR/etc.),
  turning it into a real ops view instead of just CPU/RAM/Disk.
- Volume snapshot/restore visibility — `ApplicationVolume.lastSnapshotAt` /
  `lastSnapshotKey` and the `restoreApplicationVolumes` mutation already
  exist server-side; today there is no UI for either at all.
- Color the Dashboard's alert-threshold rule line dynamically (it's static
  today) or add a banner when a node's live reading crosses the same
  thresholds `zsc-agent` itself uses to classify `.overloaded`
  (cpu/mem ≥90%, disk ≥80% — `SendHeartbeatUseCase.classifyStatus`).
- CSV export of a node's 24h telemetry — the data is already fetched
  client-side for the chart; useful for support conversations.
- "Coming soon" placeholder tiles for earnings/billing/KYC
  (`providerEarnings` / `billingSummary` / `kycStatus` already exist in the
  schema but return `notImplemented: true`) — lets the UI space be designed
  now and wired to real data later with no rework.

**Cross-repo** (needs work in `zsc-agent` and/or `zsc-backend` before any UI
can show it):

- Per-container Docker stats (CPU%/memory/network) — `dockerode`'s
  `container.stats()` is never called anywhere in `zsc-agent` today; needs a
  new agent-side collection + a new report field/endpoint before any
  per-app resource chart is possible.
- Network throughput — `MachineSpecs.network` already has the fields in the
  type, but `zsc-agent`'s `SystemInformationMonitor` never populates them.
- Historical telemetry beyond 24h (e.g. 7/30-day trends) — purely a
  backend change (a new aggregation table + longer retention); the current
  `machineTelemetry` query hard-clamps `sinceHours` to 24 and the underlying
  rows are pruned after 24h, so the client has no way to ask for more.
- An "agent maintenance activity" feed (last volume snapshot, last cluster
  reconcile, space reclaimed by the last prune) — `AgentRunner`'s own
  snapshot/reconcile/prune jobs only log locally today; none of their
  outcomes are reported to the backend except volume snapshots.
- GraphQL subscriptions for telemetry/status — everything today is
  request/response; the Dashboard and node list both poll. A real "live"
  dashboard would need backend subscription support first.
