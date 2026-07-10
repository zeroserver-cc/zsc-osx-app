import Foundation

/// The single source of truth for "what is the agent doing right now, and
/// what can we do about it." This is an `ObservableObject` (not the newer
/// `@Observable` macro) on purpose: `@Observable`'s automatic SwiftUI view
/// invalidation needs macOS 14+ at runtime, and this app's deployment target
/// is macOS 13 (Ventura) to keep MenuBarExtra's minimum requirement as low
/// as possible. `@Published` + `ObservableObject` works correctly all the
/// way back to macOS 13.
///
/// Everything here runs on the main actor. The actual process-spawning work
/// happens off-actor inside LaunchctlRunner, so we never block the UI
/// thread — but all the state we publish, and all the decisions about what
/// command to run next, happen on the main actor so there's never a data
/// race between a poll tick and a user-initiated click.
@MainActor
final class AgentController: ObservableObject {

    // MARK: Published state consumed by the UI

    @Published private(set) var status: AgentStatus = .unknown(reason: "Not yet checked")
    @Published private(set) var lastCheckedAt: Date?

    /// True while a Start/Stop command we issued is still running (i.e. the
    /// admin prompt is up, or launchctl is doing its thing). While this is
    /// true, the background poller skips its tick — otherwise a poll could
    /// read a half-finished transition and show something confusing, and
    /// there's no point re-checking status while we already know we're
    /// mid-action.
    @Published private(set) var isActionInFlight = false

    /// A short, user-facing message about the last thing that went wrong
    /// (e.g. a launchctl command failed for a real reason). Deliberately
    /// left `nil` when the user simply cancelled the admin password prompt —
    /// that's an ordinary choice, not an error, and nagging them about it
    /// would be annoying.
    @Published var lastActionMessage: String?

    // MARK: Polling

    private var pollTask: Task<Void, Never>?
    private var isRefreshing = false
    private let pollInterval: Duration = .seconds(3)

    init() {
        // Polling starts immediately on creation rather than being tied to
        // any SwiftUI view appearing. MenuBarExtra's `.menu` style only
        // instantiates its content lazily (when the user actually opens the
        // dropdown), so if we waited for a view's `.task` to call this, the
        // icon wouldn't reflect real status until the first click. Since
        // AgentController itself is created once, at app launch (as a
        // `@StateObject` in ZeroServerControlApp), starting the loop here
        // guarantees it's always running.
        startPolling()
    }

    /// Starts the background status-polling loop. Called once from `init`;
    /// exposed so it can also be restarted manually if ever needed. Safe to
    /// call again later (it cancels any previous loop first).
    func startPolling() {
        pollTask?.cancel()
        // `@MainActor` on the Task closure itself (rather than sprinkling
        // `await` on every property access inside it) keeps this whole loop
        // running on the same actor as the rest of AgentController, which
        // is what makes it safe to read/write `isActionInFlight`/`status`
        // here with no risk of racing a user-initiated action.
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.isActionInFlight {
                    await self.refreshStatusNow()
                }
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    /// Re-checks status immediately, ignoring the poll timer. Called after
    /// every start/stop attempt finishes, so the UI reflects the outcome
    /// right away instead of waiting up to `pollInterval` for the next tick.
    func refreshStatusNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        status = await computeStatus()
        lastCheckedAt = Date()
    }

    // MARK: Status computation (always unprivileged)

    private func computeStatus() async -> AgentStatus {
        guard FileManager.default.fileExists(atPath: AgentTarget.plistPath) else {
            return .notInstalled
        }

        do {
            let result = try await LaunchctlRunner.run(["print", AgentTarget.serviceTarget])

            // Empirically verified (see CLAUDE.md): launchctl exits 113 when
            // the plist exists on disk but was never bootstrapped into
            // launchd. That's a "stopped" state to us, just one that needs
            // `bootstrap` rather than `kickstart` to start again.
            if result.exitCode == 113 {
                return .stopped(loaded: false)
            }

            guard result.exitCode == 0 else {
                return .unknown(reason: "launchctl print exited \(result.exitCode): \(result.stderr.trimmedOrDefault)")
            }

            if result.stdout.contains("state = running") {
                return .running(pid: Self.extractPID(from: result.stdout) ?? 0)
            } else if result.stdout.contains("state = not running") {
                // Loaded into launchd, but not currently running (e.g. it
                // crashed, or was killed directly instead of via launchctl).
                return .stopped(loaded: true)
            }

            return .unknown(reason: "Unrecognized launchctl output")
        } catch {
            return .unknown(reason: error.localizedDescription)
        }
    }

    /// Pulls the process ID out of a line like "pid = 12345" in
    /// `launchctl print`'s output. Returns nil if no such line is found
    /// (shouldn't happen when state = running, but we don't want to crash
    /// if launchctl's output format ever shifts slightly).
    private static func extractPID(from output: String) -> Int32? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("pid = ") else { continue }
            let numberPart = trimmed.dropFirst("pid = ".count)
            return Int32(numberPart)
        }
        return nil
    }

    // MARK: User-initiated actions

    /// What the primary button in the menu does: start if stopped, stop if
    /// running. Everything else (not installed, mid-transition, unknown) has
    /// no primary action — the UI hides or disables the button in those
    /// states, but we guard here too since this is also reachable
    /// programmatically.
    func performPrimaryAction() async {
        switch status {
        case .running:
            await stopAgent()
        case .stopped:
            await startAgent()
        case .notInstalled, .starting, .stopping, .unknown:
            break
        }
    }

    private func startAgent() async {
        guard case let .stopped(loaded) = status else { return }
        isActionInFlight = true
        status = .starting
        defer { isActionInFlight = false }

        // "loaded but not running" (e.g. crashed) needs a restart-kick;
        // "never bootstrapped" needs to be bootstrapped from the plist file
        // on disk in the first place. Using the wrong one of these against
        // the wrong state either no-ops or errors, so we branch on exactly
        // what refreshStatusNow() last observed.
        let command = loaded
            ? "/bin/launchctl kickstart -k \(AgentTarget.serviceTarget)"
            : "/bin/launchctl bootstrap system \(AgentTarget.plistPath)"
        await runPrivilegedCommand(command)
        await refreshStatusNow()
    }

    private func stopAgent() async {
        // Mirrors startAgent()'s guard — hardening, not a live bug today:
        // performPrimaryAction() only calls this from `.running`, but this
        // makes that invariant explicit here too rather than relying solely
        // on the caller's switch statement never changing.
        guard case .running = status else { return }
        isActionInFlight = true
        status = .stopping
        defer { isActionInFlight = false }

        // `bootout` unloads the job from launchd entirely (full stop, per
        // the product decision that "off" means fully stopped) but never
        // touches the plist file on disk — so this is always reversible by
        // starting again, and never uninstalls anything.
        await runPrivilegedCommand("/bin/launchctl bootout \(AgentTarget.serviceTarget)")
        await refreshStatusNow()
    }

    private func runPrivilegedCommand(_ command: String) async {
        do {
            let result = try await LaunchctlRunner.runPrivileged(command)
            if result.exitCode != 0 {
                // AppleScript error -128 means "User canceled." — the
                // person running this app just decided not to enter their
                // password. That's expected, ordinary behavior, not
                // something to show as an error.
                if result.stderr.contains("-128") {
                    lastActionMessage = nil
                } else {
                    lastActionMessage = result.stderr.trimmedOrDefault.isEmpty
                        ? "Command failed (exit code \(result.exitCode))"
                        : result.stderr.trimmedOrDefault
                }
            } else {
                lastActionMessage = nil
            }
        } catch {
            lastActionMessage = error.localizedDescription
        }
    }

    // MARK: Convenience for the "not installed" UI branch

    /// The exact one-liner from zsc-agent-runner's README. Copied to the
    /// clipboard so a provider who doesn't have the agent installed yet can
    /// paste-and-run it in Terminal. Deliberately hardcoded rather than
    /// fetched at runtime — this app never reaches out to the network, and
    /// the install command is stable/public.
    func copyInstallCommandToClipboard() {
        let installCommand = "curl -fsSL https://raw.githubusercontent.com/zeroserver-cc/zsc-agent-runner/main/install.sh | sh"
        ClipboardWriter.copy(installCommand)
    }
}

private extension String {
    var trimmedOrDefault: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
