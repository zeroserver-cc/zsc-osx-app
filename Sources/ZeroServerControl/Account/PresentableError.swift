import Foundation

/// Maps this app's network/auth error types to short, human-readable copy.
///
/// M4 (correctness/UI audit): before this existed, `error.localizedDescription`
/// flowed straight into RemoteNodesSectionView, RemoteNodeRowView, LoginView,
/// and AccountSession's own `lastErrorMessage` — each call site independently,
/// with no shared "make this presentable" layer. `TransportError.errorDescription`
/// already avoids the worst of it (no stack traces, no raw NSError text) but
/// still leaks HTTP status codes and couples the UI to whatever wording
/// URLError happens to produce. This is the one place that decides what a
/// user actually sees; the underlying `Error` itself is still exactly what
/// gets logged/inspected during debugging.
///
/// Deliberately scoped to the GraphQL/network error path only — this app's
/// *other* error surface, AgentController's local launchctl/osascript stderr
/// (shown in SettingsView), is a different domain by design: raw command
/// output that's genuinely useful to this app's admin/developer audience, not
/// an opaque server exception. See CLAUDE.md's privilege & security notes for
/// why that surface is intentionally left as-is.
enum PresentableError {
    static func message(for error: Error) -> String {
        if let transportError = error as? GraphQLClient.TransportError {
            return message(for: transportError)
        }
        if case .sessionExpired? = error as? APIClientError {
            return sessionExpired
        }
        return genericFailure
    }

    static var sessionExpired: String {
        NSLocalizedString(
            "error.session_expired",
            value: "Your session expired. Please sign in again.",
            comment: ""
        )
    }

    private static var genericFailure: String {
        NSLocalizedString(
            "error.generic_request_failed",
            value: "Something went wrong. Please try again.",
            comment: ""
        )
    }

    private static func message(for error: GraphQLClient.TransportError) -> String {
        switch error {
        case .network:
            return NSLocalizedString(
                "error.network",
                value: "Couldn't reach the server. Check your internet connection and try again.",
                comment: ""
            )
        case .invalidHTTPResponse, .decoding:
            return NSLocalizedString(
                "error.malformed_response",
                value: "Something went wrong talking to the server. Please try again.",
                comment: ""
            )
        case .httpStatus(let code, _):
            if code == 401 || code == 403 {
                return sessionExpired
            }
            if (500...599).contains(code) {
                return NSLocalizedString(
                    "error.server_trouble",
                    value: "The server is having trouble right now. Please try again in a moment.",
                    comment: ""
                )
            }
            return genericFailure
        case .graphQL(let errors):
            // Deliberately passed through as-is, not replaced with generic
            // copy: these are backend business-logic messages authored to
            // be user-facing (e.g. ForceStopMachine's "node may be offline"
            // check), not raw exceptions — swapping them for a generic
            // string would throw away information the backend specifically
            // crafted for display.
            return errors.first?.message ?? genericFailure
        }
    }
}
