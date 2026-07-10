import Foundation

/// Whatever can produce/refresh the current access token. AccountSession
/// is the only conformer. APIClient depends on this protocol (not on
/// AccountSession directly) so it stays a small, independently reasoned-
/// about networking layer with no knowledge of Keychain/UI state.
@MainActor
protocol TokenSource: AnyObject {
    var accessToken: String? { get }
    /// Attempts one refresh using the stored refresh token. On failure,
    /// the conformer is responsible for transitioning itself to signed-out
    /// (clearing the Keychain, flipping @Published state) before returning
    /// false — APIClient just needs the true/false verdict.
    func refreshAccessToken() async -> Bool
}

enum APIClientError: Error, LocalizedError {
    case notAuthenticated
    case sessionExpired
    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You're not signed in."
        case .sessionExpired: return "Your session expired. Please sign in again."
        }
    }
}

/// Typed wrapper over GraphQLClient exposing exactly the operations this
/// app needs. Owns the retry-once-on-auth-failure policy so every
/// authenticated call gets it uniformly, without callers having to think
/// about token refresh at all.
@MainActor
final class APIClient {
    private let graphQL: GraphQLClient
    weak var tokenSource: TokenSource?

    init(graphQL: GraphQLClient = GraphQLClient(), tokenSource: TokenSource? = nil) {
        self.graphQL = graphQL
        self.tokenSource = tokenSource
    }

    // MARK: Auth operations — never go through the authenticated retry
    // wrapper below (login has no token yet; refreshToken must not itself
    // trigger a refresh-on-401 loop).

    func login(email: String, password: String) async throws -> AuthPayload {
        let result: LoginEnvelope = try await graphQL.execute(
            operationName: "Login",
            query: Self.loginMutation,
            variables: ["input": ["email": email, "password": password]]
        )
        return result.login
    }

    func refreshToken(_ refreshToken: String) async throws -> AuthPayload {
        let result: RefreshTokenEnvelope = try await graphQL.execute(
            operationName: "RefreshToken",
            query: Self.refreshTokenMutation,
            variables: ["refreshToken": refreshToken]
        )
        return result.refreshToken
    }

    // MARK: Authenticated operations — go through the retry-once wrapper.

    func me() async throws -> User {
        let result: MeEnvelope = try await executeAuthenticated(operationName: "Me", query: Self.meQuery)
        return result.me
    }

    func myMachines() async throws -> [RemoteNode] {
        let result: MachinesEnvelope = try await executeAuthenticated(
            operationName: "MyMachines", query: Self.myMachinesQuery
        )
        return result.myMachines
    }

    func pauseMachine(id: String) async throws -> RemoteNode {
        let result: PauseEnvelope = try await executeAuthenticated(
            operationName: "PauseMachine", query: Self.pauseMutation, variables: ["id": id]
        )
        return result.pauseMachine
    }

    func resumeMachine(id: String) async throws -> RemoteNode {
        let result: ResumeEnvelope = try await executeAuthenticated(
            operationName: "ResumeMachine", query: Self.resumeMutation, variables: ["id": id]
        )
        return result.resumeMachine
    }

    func forceStopMachine(id: String) async throws -> RemoteNode {
        let result: ForceStopEnvelope = try await executeAuthenticated(
            operationName: "ForceStopMachine", query: Self.forceStopMutation, variables: ["id": id]
        )
        return result.forceStopMachine
    }

    // MARK: The retry-once-on-auth-failure wrapper
    //
    // Concrete retry policy:
    // 1. Send the request with whatever access token TokenSource has now.
    // 2. If it fails with something that looks like an expired/invalid
    //    token (HTTP 401, or a GraphQL error whose extensions.code is
    //    UNAUTHENTICATED/UNAUTHORIZED, or whose message mentions
    //    jwt/unauthenticated — a deliberately generous heuristic), call
    //    tokenSource.refreshAccessToken().
    // 3. If refresh succeeds, retry the SAME request exactly once with the
    //    new token. Whatever that retry does (succeed or fail) is returned
    //    as-is — we never loop a second time, so a persistently-failing
    //    server can't cause a retry storm.
    // 4. If refresh fails, tokenSource has already flipped itself to
    //    signed-out; throw .sessionExpired so the caller's UI can show
    //    that instead of a confusing raw network error.

    private func executeAuthenticated<Response: Decodable>(
        operationName: String,
        query: String,
        variables: [String: Any] = [:]
    ) async throws -> Response {
        guard let tokenSource else { throw APIClientError.notAuthenticated }
        do {
            return try await graphQL.execute(
                operationName: operationName, query: query, variables: variables,
                accessToken: tokenSource.accessToken
            )
        } catch {
            guard Self.isAuthError(error) else { throw error }
            guard await tokenSource.refreshAccessToken() else { throw APIClientError.sessionExpired }
            return try await graphQL.execute(
                operationName: operationName, query: query, variables: variables,
                accessToken: tokenSource.accessToken
            )
        }
    }

    private static func isAuthError(_ error: Error) -> Bool {
        guard let transportError = error as? GraphQLClient.TransportError else { return false }
        switch transportError {
        case .httpStatus(let code, _):
            return code == 401
        case .graphQL(let errors):
            return errors.contains {
                let code = $0.extensions?.code?.uppercased()
                return code == "UNAUTHENTICATED" || code == "UNAUTHORIZED"
                    || $0.message.localizedCaseInsensitiveContains("jwt")
                    || $0.message.localizedCaseInsensitiveContains("unauthenticated")
            }
        default:
            return false
        }
    }

    // MARK: GraphQL operation strings + envelope structs
    //
    // Deliberately one struct per operation (not a single struct with all
    // the mutation keys) — a shared struct would need every key to be
    // Optional (since a given response only ever populates the one field
    // matching the operation actually sent), which defeats using
    // non-optional RemoteNode/AuthPayload fields cleanly. One field each
    // keeps every decode strict.

    private struct LoginEnvelope: Decodable { let login: AuthPayload }
    private struct RefreshTokenEnvelope: Decodable { let refreshToken: AuthPayload }
    private struct MeEnvelope: Decodable { let me: User }
    private struct MachinesEnvelope: Decodable { let myMachines: [RemoteNode] }
    private struct PauseEnvelope: Decodable { let pauseMachine: RemoteNode }
    private struct ResumeEnvelope: Decodable { let resumeMachine: RemoteNode }
    private struct ForceStopEnvelope: Decodable { let forceStopMachine: RemoteNode }

    private static let loginMutation = """
    mutation Login($input: LoginInput!) {
      login(input: $input) {
        user { id email }
        accessToken
        refreshToken
        expiresAt
      }
    }
    """

    private static let refreshTokenMutation = """
    mutation RefreshToken($refreshToken: String!) {
      refreshToken(refreshToken: $refreshToken) {
        user { id email }
        accessToken
        refreshToken
        expiresAt
      }
    }
    """

    private static let meQuery = "query Me { me { id email } }"

    private static let machineFields = """
    id name status workloadsPaused lastHeartbeat agentVersion updatedAt createdAt \
    currentUsage { cpuPercent memoryPercent diskPercent recordedAt }
    """

    private static let myMachinesQuery = "query MyMachines { myMachines { \(machineFields) } }"

    private static let pauseMutation = """
    mutation PauseMachine($id: ID!) {
      pauseMachine(id: $id) { \(machineFields) }
    }
    """

    private static let resumeMutation = """
    mutation ResumeMachine($id: ID!) {
      resumeMachine(id: $id) { \(machineFields) }
    }
    """

    private static let forceStopMutation = """
    mutation ForceStopMachine($id: ID!) {
      forceStopMachine(id: $id) { \(machineFields) }
    }
    """
}
