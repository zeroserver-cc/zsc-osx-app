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
        _ = await attemptRefresh(refreshToken: stored.refreshToken)
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
            lastErrorMessage = error.localizedDescription
        }
    }

    func signOut() {
        CredentialStore.clear()
        accessToken = nil
        state = .signedOut
    }

    // MARK: TokenSource

    func refreshAccessToken() async -> Bool {
        guard let stored = CredentialStore.load() else { return false }
        return await attemptRefresh(refreshToken: stored.refreshToken)
    }

    private func attemptRefresh(refreshToken: String) async -> Bool {
        do {
            let payload = try await apiClient.refreshToken(refreshToken)
            apply(payload)
            state = .signedIn(user: payload.user)
            return true
        } catch {
            // Refresh failing means the refresh token itself is dead
            // (expired ~7d, or revoked) — there is no path back except
            // signing in again.
            signOut()
            lastErrorMessage = NSLocalizedString(
                "Your session expired. Please sign in again.",
                value: "Your session expired. Please sign in again.",
                comment: ""
            )
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
