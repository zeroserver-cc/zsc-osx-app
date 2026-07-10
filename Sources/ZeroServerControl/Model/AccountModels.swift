import Foundation

struct User: Decodable, Equatable {
    let id: String
    let email: String
}

struct AuthPayload: Decodable {
    let user: User
    /// The canonical bearer credential — sent as "Authorization: Bearer
    /// <accessToken>" on every authenticated request. Short-lived
    /// (~15 minutes server-side); never persisted to the Keychain, see
    /// CredentialStore's doc comment for why.
    let accessToken: String
    /// Long-lived (~7 days server-side) — this is the only thing
    /// CredentialStore actually persists.
    let refreshToken: String
    let expiresAt: Date
}
