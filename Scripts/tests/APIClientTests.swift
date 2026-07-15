import Foundation

@MainActor
final class FakeTokenSource: TokenSource {
    var accessToken: String?
    var refreshShouldSucceed = true
    var refreshCallCount = 0

    func refreshAccessToken() async -> Bool {
        refreshCallCount += 1
        if refreshShouldSucceed {
            accessToken = "refreshed-token"
            return true
        }
        return false
    }
}

@MainActor
func runAPIClientTests(_ t: TestRunner) async {
    let endpoint = URL(string: "https://unit-test.invalid/graphql")!

    await t.run("APIClient retries once after a successful refresh, then succeeds") {
        var callCount = 0
        var seenTokens: [String?] = []
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            seenTokens.append(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if callCount == 1 {
                // First attempt: server rejects the (expired) token.
                let errorBody = #"{"data":null,"errors":[{"message":"jwt expired","extensions":{"code":"UNAUTHENTICATED"}}]}"#
                return (response, errorBody.data(using: .utf8)!)
            }
            // Second attempt (after refresh): succeeds.
            let successBody = #"{"data":{"me":{"id":"u1","email":"a@b.com"}}}"#
            return (response, successBody.data(using: .utf8)!)
        }

        let graphQL = GraphQLClient(endpoint: endpoint, urlSession: MockURLProtocol.makeSession())
        let apiClient = APIClient(graphQL: graphQL)
        let tokenSource = FakeTokenSource()
        tokenSource.accessToken = "expired-token"
        apiClient.tokenSource = tokenSource

        let user = try await apiClient.me()

        t.expectEqual(callCount, 2, "should call the server exactly twice: once with the stale token, once after refresh")
        t.expectEqual(tokenSource.refreshCallCount, 1, "should refresh exactly once, not loop")
        t.expectEqual(seenTokens, ["Bearer expired-token", "Bearer refreshed-token"], "the retry must use the NEW token, not repeat the stale one")
        t.expectEqual(user.email, "a@b.com")
    }

    await t.run("APIClient throws .sessionExpired when refresh itself fails, without retrying further") {
        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let errorBody = #"{"data":null,"errors":[{"message":"jwt expired","extensions":{"code":"UNAUTHENTICATED"}}]}"#
            return (response, errorBody.data(using: .utf8)!)
        }

        let graphQL = GraphQLClient(endpoint: endpoint, urlSession: MockURLProtocol.makeSession())
        let apiClient = APIClient(graphQL: graphQL)
        let tokenSource = FakeTokenSource()
        tokenSource.accessToken = "expired-token"
        tokenSource.refreshShouldSucceed = false
        apiClient.tokenSource = tokenSource

        do {
            _ = try await apiClient.me()
            t.fail("expected .sessionExpired to be thrown")
        } catch let error as APIClientError {
            guard case .sessionExpired = error else {
                t.fail("expected .sessionExpired, got \(error)")
                return
            }
        }
        t.expectEqual(callCount, 1, "must not retry the request at all once refresh fails — only one server call")
        t.expectEqual(tokenSource.refreshCallCount, 1)
    }

    await t.run("APIClient passes through a non-auth error without ever attempting a refresh") {
        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let errorBody = #"{"data":null,"errors":[{"message":"Machine not found"}]}"#
            return (response, errorBody.data(using: .utf8)!)
        }

        let graphQL = GraphQLClient(endpoint: endpoint, urlSession: MockURLProtocol.makeSession())
        let apiClient = APIClient(graphQL: graphQL)
        let tokenSource = FakeTokenSource()
        tokenSource.accessToken = "valid-token"
        apiClient.tokenSource = tokenSource

        do {
            _ = try await apiClient.pauseMachine(id: "missing-id")
            t.fail("expected the GraphQL error to propagate")
        } catch let error as GraphQLClient.TransportError {
            guard case .graphQL(let errors) = error else {
                t.fail("expected .graphQL, got \(error)")
                return
            }
            t.expectEqual(errors.first?.message, "Machine not found")
        }
        t.expectEqual(callCount, 1, "a non-auth error must not trigger a refresh-and-retry at all")
        t.expectEqual(tokenSource.refreshCallCount, 0)
    }

    await t.run("APIClient.machineTelemetry decodes a series of MachineUsage points") {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"data":{"machineTelemetry":[
              {"cpuPercent":10.0,"memoryPercent":20.0,"diskPercent":30.0,"recordedAt":"2026-01-01T00:00:00.000Z"},
              {"cpuPercent":15.0,"memoryPercent":25.0,"diskPercent":null,"recordedAt":"2026-01-01T00:05:00.000Z"}
            ]}}
            """
            return (response, body.data(using: .utf8)!)
        }
        let graphQL = GraphQLClient(endpoint: endpoint, urlSession: MockURLProtocol.makeSession())
        let apiClient = APIClient(graphQL: graphQL)
        let tokenSource = FakeTokenSource()
        tokenSource.accessToken = "valid-token"
        apiClient.tokenSource = tokenSource

        let points = try await apiClient.machineTelemetry(machineId: "m1", sinceHours: 24)
        t.expectEqual(points.count, 2)
        t.expect(points[0].diskPercent == 30.0)
        t.expect(points[1].diskPercent == nil, "diskPercent must decode as nil, not fail the whole point")
    }

    await t.run("APIClient.machineStatusEvents decodes a list of status transitions") {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"data":{"machineStatusEvents":[
              {"id":"ev1","machineId":"m1","previousStatus":"IDLE","newStatus":"OVERLOADED","source":"AGENT_HEARTBEAT","reason":null,"createdAt":"2026-01-01T00:00:00.000Z"}
            ]}}
            """
            return (response, body.data(using: .utf8)!)
        }
        let graphQL = GraphQLClient(endpoint: endpoint, urlSession: MockURLProtocol.makeSession())
        let apiClient = APIClient(graphQL: graphQL)
        let tokenSource = FakeTokenSource()
        tokenSource.accessToken = "valid-token"
        apiClient.tokenSource = tokenSource

        let events = try await apiClient.machineStatusEvents(machineId: "m1", sinceHours: 24, limit: 100)
        t.expectEqual(events.count, 1)
        t.expectEqual(events[0].newStatus, .overloaded)
    }

    await t.run("APIClient.login and .refreshToken never go through the authenticated retry wrapper") {
        // Regression guard: login/refreshToken must work with NO tokenSource
        // set at all (there's no token yet to refresh), unlike every other
        // APIClient method.
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"data":{"login":{"user":{"id":"u1","email":"a@b.com"},"accessToken":"at","refreshToken":"rt","expiresAt":"2026-01-01T00:00:00.000Z"}}}"#
            return (response, body.data(using: .utf8)!)
        }
        let graphQL = GraphQLClient(endpoint: endpoint, urlSession: MockURLProtocol.makeSession())
        let apiClient = APIClient(graphQL: graphQL) // tokenSource left nil deliberately
        let payload = try await apiClient.login(email: "a@b.com", password: "secret")
        t.expectEqual(payload.accessToken, "at")
    }
}
