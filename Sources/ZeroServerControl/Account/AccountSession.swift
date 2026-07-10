import Foundation

/// The account/auth controller: signed-out/signing-in/signed-in state,
/// the login form's submission handling, logout, and Keychain-backed
/// session restore at launch.
///
/// Named `AccountSession`, not anything with "Login" in it, to avoid any
/// confusion with Login/LoginItemManager.swift — that's a wholly
/// unrelated "Launch at Login" OS feature.
@MainActor
final class AccountSession: ObservableObject, TokenSource {
    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn(user: User)
    }

    @Published private(set) var state: State = .signedOut
    @Published var lastErrorMessage: String?

    /// In-memory only — never written to disk. See CredentialStore's doc
    /// comment for why only the refresh token is persisted.
    private(set) var accessToken: String?

    /// Shared with RemoteNodesController — not private, so the app's
    /// composition root can hand the same instance to both controllers.
    let apiClient: APIClient
    private let graphQLClient: GraphQLClient

    /// Bumped on every signOut(). Lets an in-flight refresh that resolves
    /// *after* a sign-out detect it's stale and discard its own result,
    /// instead of silently resurrecting a session the user just explicitly
    /// ended (an in-flight refresh's success handler otherwise had no way
    /// to know signOut() had already run).
    private var sessionEpoch = 0

    /// Single-flight guard: RemoteNodesController's ~10s poll and any
    /// user-initiated action can both hit an expired access token around
    /// the same moment and each independently call refreshAccessToken().
    /// Without this, both send the *same* stored refresh token
    /// concurrently — if the backend rotates refresh tokens on use, the
    /// loser gets rejected and calls signOut(), wiping the Keychain entry
    /// the winner just wrote and forcing a spurious logout from ordinary
    /// concurrent traffic. Every concurrent caller now awaits the same
    /// in-flight task instead of starting its own.
    private var inFlightRefresh: Task<Bool, Never>?

    init(graphQLClient: GraphQLClient = GraphQLClient(), apiClient: APIClient? = nil) {
        self.graphQLClient = graphQLClient
        self.apiClient = apiClient ?? APIClient(graphQL: graphQLClient)
        self.apiClient.tokenSource = self
        // Same convention as AgentController: start the real work
        // immediately in init rather than waiting for a view's .task, so
        // the menu already reflects sign-in state the first time it's opened.
        Task { await self.restoreSessionAtLaunch() }
    }

    func restoreSessionAtLaunch() async {
        guard let stored = CredentialStore.load() else { state = .signedOut; return }
        state = .signingIn
        _ = await attemptRefresh(refreshToken: stored.refreshToken, expectedEpoch: sessionEpoch)
    }

    func signIn(email: String, password: String) async {
        state = .signingIn
        lastErrorMessage = nil
        do {
            let payload = try await apiClient.login(email: email, password: password)
            apply(payload)
            state = .signedIn(user: payload.user)
        } catch {
            state = .signedOut
            lastErrorMessage = PresentableError.message(for: error)
        }
    }

    func signOut() {
        sessionEpoch += 1
        CredentialStore.clear()
        accessToken = nil
        state = .signedOut
    }

    // MARK: TokenSource

    func refreshAccessToken() async -> Bool {
        if let existing = inFlightRefresh {
            return await existing.value
        }
        let epochAtStart = sessionEpoch
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            guard let stored = CredentialStore.load() else { return false }
            return await self.attemptRefresh(refreshToken: stored.refreshToken, expectedEpoch: epochAtStart)
        }
        inFlightRefresh = task
        let result = await task.value
        inFlightRefresh = nil
        return result
    }

    private func attemptRefresh(refreshToken: String, expectedEpoch: Int) async -> Bool {
        do {
            let payload = try await apiClient.refreshToken(refreshToken)
            // A sign-out (or another refresh that already failed and
            // signed out) happened while this network call was in flight —
            // the session isn't "current" anymore from the user's
            // perspective, so don't resurrect it just because a stale
            // request happened to succeed after the fact.
            guard sessionEpoch == expectedEpoch else { return false }
            apply(payload)
            state = .signedIn(user: payload.user)
            return true
        } catch {
            // Same staleness check on the failure path: if the session
            // already moved on (e.g. the user manually signed out, or the
            // single-flight winner already handled this), don't call
            // signOut() again or overwrite lastErrorMessage for a session
            // that isn't current anymore.
            guard sessionEpoch == expectedEpoch else { return false }
            // Refresh failing means the refresh token itself is dead
            // (expired ~7d, or revoked) — there is no path back except
            // signing in again.
            signOut()
            lastErrorMessage = PresentableError.sessionExpired
            return false
        }
    }

    private func apply(_ payload: AuthPayload) {
        accessToken = payload.accessToken
        try? CredentialStore.save(StoredSession(
            refreshToken: payload.refreshToken,
            userId: payload.user.id,
            email: payload.user.email
        ))
    }
}
