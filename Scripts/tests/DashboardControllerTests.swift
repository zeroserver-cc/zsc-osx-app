import Foundation

@MainActor
private func makeSignedInSessionForDashboard() async throws -> AccountSession {
    // Same reasoning as RemoteNodesControllerTests.makeSignedInSession: clear
    // any leftover StoredSession first so AccountSession.init's own
    // background restoreSessionAtLaunch() can't race this explicit signIn()
    // against the same shared MockURLProtocol handler.
    CredentialStore.clear()
    MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let body = #"{"data":{"login":{"user":{"id":"u1","email":"a@b.com"},"accessToken":"at","refreshToken":"rt","expiresAt":"2026-01-01T00:00:00.000Z"}}}"#
        return (response, body.data(using: .utf8)!)
    }
    let graphQL = GraphQLClient(endpoint: URL(string: "https://unit-test.invalid/graphql")!, urlSession: MockURLProtocol.makeSession())
    let session = AccountSession(graphQLClient: graphQL)
    await session.signIn(email: "a@b.com", password: "secret")
    return session
}

/// Branches a single MockURLProtocol handler by `operationName` — needed
/// here (unlike most other test files) because `refreshDetail()` fires
/// `machineTelemetry` and `machineStatusEvents` concurrently via `async let`
/// against the one shared handler.
private func operationRoutedHandler(
    telemetryBody: String,
    statusEventsBody: String
) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
    { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let json = try JSONSerialization.jsonObject(with: MockURLProtocol.body(of: request)) as? [String: Any]
        let operationName = json?["operationName"] as? String
        let body = operationName == "MachineTelemetry" ? telemetryBody : statusEventsBody
        return (response, body.data(using: .utf8)!)
    }
}

@MainActor
func runDashboardControllerTests(_ t: TestRunner) async {
    let originalSnapshot = CredentialStore.load()
    CredentialStore.clear()
    defer {
        if let originalSnapshot { try? CredentialStore.save(originalSnapshot) } else { CredentialStore.clear() }
    }

    await t.run("select(nodeId:) resets prior detail state, and is a no-op re-selecting the same node") {
        let session = try await makeSignedInSessionForDashboard()
        let controller = DashboardController(apiClient: session.apiClient, session: session)

        MockURLProtocol.requestHandler = operationRoutedHandler(
            telemetryBody: #"{"data":{"machineTelemetry":[{"cpuPercent":10.0,"memoryPercent":20.0,"diskPercent":30.0,"recordedAt":"2026-01-01T00:00:00.000Z"}]}}"#,
            statusEventsBody: #"{"data":{"machineStatusEvents":[]}}"#
        )
        controller.select(nodeId: "m1")
        await controller.refreshDetail()
        t.expectEqual(controller.telemetry.count, 1)

        controller.select(nodeId: "m1") // same id again
        t.expectEqual(controller.telemetry.count, 1, "re-selecting the already-selected node must not clear existing data")

        controller.select(nodeId: "m2")
        t.expectEqual(controller.telemetry.count, 0, "selecting a DIFFERENT node must clear the previous node's data immediately")
        t.expectEqual(controller.selectedNodeId, "m2")
    }

    await t.run("refreshDetail() fetches and stores both telemetry and status events for the selected node") {
        let session = try await makeSignedInSessionForDashboard()
        let controller = DashboardController(apiClient: session.apiClient, session: session)
        controller.select(nodeId: "m1")

        MockURLProtocol.requestHandler = operationRoutedHandler(
            telemetryBody: """
            {"data":{"machineTelemetry":[
              {"cpuPercent":10.0,"memoryPercent":20.0,"diskPercent":30.0,"recordedAt":"2026-01-01T00:00:00.000Z"},
              {"cpuPercent":15.0,"memoryPercent":25.0,"diskPercent":35.0,"recordedAt":"2026-01-01T00:05:00.000Z"}
            ]}}
            """,
            statusEventsBody: """
            {"data":{"machineStatusEvents":[
              {"id":"ev1","machineId":"m1","previousStatus":"IDLE","newStatus":"OVERLOADED","source":"AGENT_HEARTBEAT","reason":null,"createdAt":"2026-01-01T00:05:00.000Z"}
            ]}}
            """
        )
        await controller.refreshDetail()

        t.expectEqual(controller.telemetry.count, 2)
        t.expectEqual(controller.statusEvents.count, 1)
        t.expect(controller.detailError == nil)
        t.expect(controller.isLoadingDetail == false)
    }

    t.run("sanitizedForChart(_:) filters out non-finite telemetry points") {
        // A genuinely non-finite cpuPercent can't come through as JSON
        // `null` (that would fail MachineUsage's non-optional decode) — the
        // real-world failure mode this guards is NaN/Infinity arriving as a
        // literal JSON number (e.g. a division-by-zero server-side), so
        // this exercises the sanitizer directly instead of round-tripping
        // through JSON, which can't represent NaN/Infinity at all.
        let raw = [
            MachineUsage(cpuPercent: 10.0, memoryPercent: 20.0, diskPercent: 30.0, recordedAt: Date(timeIntervalSince1970: 0)),
            MachineUsage(cpuPercent: .nan, memoryPercent: 25.0, diskPercent: 35.0, recordedAt: Date(timeIntervalSince1970: 300)),
            MachineUsage(cpuPercent: 12.0, memoryPercent: .infinity, diskPercent: 35.0, recordedAt: Date(timeIntervalSince1970: 600))
        ]
        let sanitized = DashboardController.sanitizedForChart(raw)
        t.expectEqual(sanitized.count, 1, "both non-finite points must be dropped, leaving only the fully-finite one")
        t.expect(sanitized.first?.cpuPercent == 10.0)
    }

    t.run("sanitizedForChart(_:) sorts points by recordedAt ascending regardless of input order") {
        let newest = MachineUsage(cpuPercent: 1, memoryPercent: 1, diskPercent: 1, recordedAt: Date(timeIntervalSince1970: 600))
        let oldest = MachineUsage(cpuPercent: 2, memoryPercent: 2, diskPercent: 2, recordedAt: Date(timeIntervalSince1970: 0))
        let middle = MachineUsage(cpuPercent: 3, memoryPercent: 3, diskPercent: 3, recordedAt: Date(timeIntervalSince1970: 300))

        let sorted = DashboardController.sanitizedForChart([newest, oldest, middle])
        t.expectEqual(sorted.map(\.cpuPercent), [2, 3, 1], "must come out oldest-recordedAt-first regardless of input order")
    }

    await t.run("refreshDetail() keeps previously-fetched telemetry in place after a failed refresh") {
        let session = try await makeSignedInSessionForDashboard()
        let controller = DashboardController(apiClient: session.apiClient, session: session)
        controller.select(nodeId: "m1")

        MockURLProtocol.requestHandler = operationRoutedHandler(
            telemetryBody: #"{"data":{"machineTelemetry":[{"cpuPercent":10.0,"memoryPercent":20.0,"diskPercent":30.0,"recordedAt":"2026-01-01T00:00:00.000Z"}]}}"#,
            statusEventsBody: #"{"data":{"machineStatusEvents":[]}}"#
        )
        await controller.refreshDetail()
        t.expectEqual(controller.telemetry.count, 1)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, "Service Unavailable".data(using: .utf8)!)
        }
        await controller.refreshDetail()

        t.expectEqual(controller.telemetry.count, 1, "a transient failure must not clear already-fetched telemetry")
        t.expect(controller.detailError != nil, "the failure must still be surfaced")
    }

    await t.run("refreshDetail() is a no-op (no network call) while signed out") {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"data":{"login":{"user":{"id":"u1","email":"a@b.com"},"accessToken":"at","refreshToken":"rt","expiresAt":"2026-01-01T00:00:00.000Z"}}}"#
            return (response, body.data(using: .utf8)!)
        }
        let graphQL = GraphQLClient(endpoint: URL(string: "https://unit-test.invalid/graphql")!, urlSession: MockURLProtocol.makeSession())
        let signedOutSession = AccountSession(graphQLClient: graphQL) // never signed in
        let controller = DashboardController(apiClient: signedOutSession.apiClient, session: signedOutSession)
        controller.select(nodeId: "m1")

        var networkCallMade = false
        MockURLProtocol.requestHandler = { request in
            networkCallMade = true
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, #"{"data":{"machineTelemetry":[]}}"#.data(using: .utf8)!)
        }
        await controller.refreshDetail()
        t.expect(!networkCallMade, "refreshDetail() must not hit the network at all while signed out")
        t.expectEqual(controller.telemetry.count, 0)
    }
}
