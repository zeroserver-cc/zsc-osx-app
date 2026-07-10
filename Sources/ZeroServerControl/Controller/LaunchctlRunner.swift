import Foundation

/// The captured result of running an external process: its exit code and
/// whatever it wrote to stdout/stderr. We always capture both, even when we
/// only care about one of them, because launchctl and osascript both put
/// diagnostic information on stderr that's worth surfacing in error
/// messages.
struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ProcessRunError: Error {
    case failedToLaunch(underlying: Error)
}

/// A tiny async wrapper around Foundation's `Process` for shelling out to
/// `launchctl` (unprivileged) and `osascript` (to request admin privileges
/// for the handful of commands that actually need root).
///
/// Why not just call `process.waitUntilExit()`? That blocks the calling
/// thread until the child process exits. For `launchctl print` that's
/// milliseconds and harmless, but for the privileged calls it blocks for as
/// long as the admin password dialog is on screen — which, on the main
/// actor, would freeze the whole app's UI. Using a `terminationHandler`
/// callback bridged into `async` via a checked continuation avoids blocking
/// any thread while we wait.
enum LaunchctlRunner {

    /// Runs `/bin/launchctl <arguments>` directly, with no elevated
    /// privileges. This is what status checks use — we verified empirically
    /// that `launchctl print system/<label>` works fine as a normal user
    /// even for a root-owned LaunchDaemon, so there's no reason to prompt
    /// for a password just to look at status.
    static func run(_ arguments: [String]) async throws -> ProcessResult {
        try await runProcess(executable: "/bin/launchctl", arguments: arguments)
    }

    /// Runs a launchctl command *with administrator privileges*, via
    /// AppleScript's `do shell script ... with administrator privileges`.
    /// macOS shows the standard password/Touch ID prompt; if the user
    /// cancels it, osascript exits non-zero with "User canceled." and error
    /// number -128 in stderr — AgentController treats that specific case as
    /// "the user chose not to," not as a failure worth alarming them about.
    ///
    /// Security note: `shellCommand` must ALWAYS be built by the caller from
    /// hardcoded launchctl verbs plus AgentTarget's constants — never from
    /// user-typed or network-provided text. It gets interpolated into the
    /// AppleScript source string below, so anything attacker-controlled in
    /// here would be a shell-injection hole. AgentController.swift is the
    /// only caller, and it only ever passes together fixed strings.
    static func runPrivileged(_ shellCommand: String) async throws -> ProcessResult {
        // Escape embedded double quotes and backslashes so the command
        // survives being placed inside the outer AppleScript string
        // literal. (Our actual commands never contain quotes today, but
        // this keeps the escaping correct if that ever changes.)
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
        return try await runProcess(executable: "/usr/bin/osascript", arguments: ["-e", appleScript])
    }

    private static func runProcess(executable: String, arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { finishedProcess in
                // Reading to end-of-file here is safe/non-blocking-forever
                // because the process has already terminated by the time
                // this handler fires — there's no more data coming.
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let result = ProcessResult(
                    exitCode: finishedProcess.terminationStatus,
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? ""
                )
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ProcessRunError.failedToLaunch(underlying: error))
            }
        }
    }
}
