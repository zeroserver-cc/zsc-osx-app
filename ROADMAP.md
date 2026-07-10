# Roadmap

This roadmap starts from a hardened baseline: a full adversarial security,
correctness, and UI/HIG audit was completed first (critical command
injection, session-refresh races, a crash-on-non-finite-telemetry bug, and a
dozen smaller correctness/UI issues — all fixed, all covered by regression
tests). Consider that hardening pass done, not "Phase 1" itself. The four
phases below build forward from there.

## Phase 1 (now) — Define the next iteration

This phase's job is to figure out what's genuinely worth building next and
commit to a focused goal, not to build yet.

**Candidates considered** (a senior product/eng/UX read of the real gap in
what exists today):

1. **Node health notifications** — the app is entirely *pull*-based right
   now: you only learn a node went offline, started erroring, or is
   overloaded by opening the menu. There's no ambient signal.
2. Historical usage graphs — zsc-backend already retains 24h of telemetry
   per node (`machineTelemetry`/`getMachineTelemetryUseCase` already exist
   server-side), unused by this client today.
3. Search/sort/filter for large accounts — currently a flat, creation-order
   list with no way to narrow it down.
4. Multi-account switching without a full sign-out/sign-in cycle.

**Recommended focus — #1, Node Health Notifications.** It's the single
highest-leverage change because it converts the app's whole value
proposition from "a place to check" into "something that tells you," which
is the actual reason a menu bar utility beats a dashboard tab. It also
builds directly on infrastructure that already exists —
`RemoteNodesController`'s poll loop already has every state transition
available; this is a diffing + `UNUserNotificationCenter` layer on top, not
new plumbing. Candidates #2–4 are real and worth doing, just after this, so
focus isn't diluted across all four at once.

**Concrete Phase 1 goal:** detect online→offline, new-error, and overloaded
transitions per node; surface each via a native macOS notification plus a
menu bar icon badge; let the user opt in/out per event type from Settings.

## Phase 2 — Build it

Implement Phase 1's defined notification system:

- Diffing logic in `RemoteNodesController` (compare each poll's fresh
  `nodes` against the previous snapshot, classify the transitions that
  matter).
- `UNUserNotificationCenter` integration (permission request, posting,
  respecting the user's per-event-type opt-in/out).
- A new Settings section for that opt-in/out control.
- Localized notification copy (EN / pt-BR, extending the existing
  `Localizable.strings` pipeline).

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
- Historical usage graphs and search/sort/filter (deferred from Phase 1's
  candidate list).
- Revisiting the `.menuBarExtraStyle(.window)` rewrite — the only way to get
  a dropdown that stays open across a click, which `.menu` style
  fundamentally can't do on macOS.
