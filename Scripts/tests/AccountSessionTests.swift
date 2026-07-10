import Foundation

/// H1 (security + correctness audits, independently): AccountSession's
/// token refresh had no single-flight guard and no way to detect a
/// sign-out that happened while a refresh was already in flight. Locks in
/// both fixes.
@MainActor
func runAccountSessionTests(_ t: TestRunner) async {
    // Snapshot/restore the real Keychain entry around every test here,
    // same convention as RemoteNodesControllerTests — this app's own
    // signed-in session on this machine must never be disturbed by a test
    // run, and a leftover session from a previous run must never leak in.
    let originalSnapshot = CredentialStore.load()
    CredentialStore.clear()
    defer {
        if let originalSnapshot { try? CredentialStore.save(originalSnapshot) } else { CredentialStore.clear() }
    }

    func makeSessionWithStoredRefreshToken() -> AccountSession {
        try? CredentialStore.save(StoredSession(refreshToken: "rt-original", userId: "u1", email: "a@b.com"))
        let graphQL = GraphQLClient(endpoint: URL(string: "https://unit-test.invalid/graphql")!, urlSession: MockURLProtocol.makeSession())
        // AccountSession's init kicks off its own restoreSessionAtLaunch()
        // Task immediately - these tests don't want that background
        // refresh racing the one they trigger explicitly, so give it a
        // response to consume (identical shape, harmless) before moving on.
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"data":{"refreshToken":{"user":{"id":"u1","email":"a@b.com"},"accessToken":"at-launch","refreshToken":"rt-launch","expiresAt":"2026-01-01T00:00:00.000Z"}}}"#
            return (response, body.data(using: .utf8)!)
        }
        return AccountSession(graphQLClient: graphQL)
    }

    await t.run("refreshAccessToken() coalesces concurrent calls into a single network request") {
        let session = makeSessionWithStoredRefreshToken()
        // Let init's own restoreSessionAtLaunch() refresh finish first, so
        // it isn't what gets counted below.
        try? await Task.sleep(for: .milliseconds(50))

        var refreshCallCount = 0
        MockURLProtocol.requestHandler = { request in
            refreshCallCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            // A deliberate delay: without this, both concurrent calls could
            // plausibly complete before either observes the other's
            // in-flight task. Sleeping here (off the main thread - custom
            // URLProtocol callbacks run on a background queue) widens the
            // race window so the single-flight guard is actually exercised,
            // not just accidentally not-triggered.
            Thread.sleep(forTimeInterval: 0.05)
            let body = #"{"data":{"refreshToken":{"user":{"id":"u1","email":"a@b.com"},"accessToken":"at-2","refreshToken":"rt-2","expiresAt":"2026-01-01T00:00:00.000Z"}}}"#
            return (response, body.data(using: .utf8)!)
        }

        async let first = session.refreshAccessToken()
        async let second = session.refreshAccessToken()
        let (firstResult, secondResult) = await (first, second)

        t.expect(firstResult, "first concurrent refresh should succeed")
        t.expect(secondResult, "second concurrent refresh should also report success (coalesced onto the first)")
        t.expectEqual(refreshCallCount, 1, "two concurrent refreshAccessToken() calls must result in exactly one network request")
    }

    await t.run("signOut() during an in-flight refresh prevents that refresh from resurrecting .signedIn") {
        let session = makeSessionWithStoredRefreshToken()
        try? await Task.sleep(for: .milliseconds(50))

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            // Long enough that signOut() below reliably lands while this
            // is still in flight.
            Thread.sleep(forTimeInterval: 0.1)
            let body = #"{"data":{"refreshToken":{"user":{"id":"u1","email":"a@b.com"},"accessToken":"at-3","refreshToken":"rt-3","expiresAt":"2026-01-01T00:00:00.000Z"}}}"#
            return (response, body.data(using: .utf8)!)
        }

        let refreshTask = Task { await session.refreshAccessToken() }
        try? await Task.sleep(for: .milliseconds(20)) // let the refresh actually start before signing out
        session.signOut()

        let refreshSucceeded = await refreshTask.value
        t.expect(!refreshSucceeded, "a refresh whose session already signed out must not report success")
        t.expectEqual(session.state, .signedOut, "explicit sign-out must not be silently undone by a stale in-flight refresh resolving afterwards")
        t.expect(CredentialStore.load() == nil, "signOut()'s Keychain clear must not be undone by the stale refresh writing a new token back")
    }
}
