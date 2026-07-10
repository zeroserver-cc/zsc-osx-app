import Foundation

@MainActor
private func makeSignedInSession() async throws -> AccountSession {
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

@MainActor
func runRemoteNodesControllerTests(_ t: TestRunner) async {
    // AccountSession's init kicks off a real Keychain read + (if something
    // is stored) a real network refresh as a side effect of construction —
    // snapshot/restore around every test in this file so a developer's real
    // signed-in session on this machine is never disturbed, and so a
    // leftover session from a previous run never leaks into this one.
    let originalSnapshot = CredentialStore.load()
    CredentialStore.clear()
    defer {
        if let originalSnapshot { try? CredentialStore.save(originalSnapshot) } else { CredentialStore.clear() }
    }

    await t.run("pause() updates only the targeted node's workloadsPaused, and clears its action state") {
        let session = try await makeSignedInSession()
        let controller = RemoteNodesController(apiClient: session.apiClient, session: session)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"data":{"myMachines":[
              {"id":"m1","name":"node-one","status":"ONLINE","workloadsPaused":false,"lastHeartbeat":null,"agentVersion":null,"updatedAt":"2026-01-01T00:00:00.000Z","createdAt":"2026-01-01T00:00:00.000Z"},
              {"id":"m2","name":"node-two","status":"ONLINE","workloadsPaused":false,"lastHeartbeat":null,"agentVersion":null,"updatedAt":"2026-01-01T00:00:00.000Z","createdAt":"2026-01-02T00:00:00.000Z"}
            ]}}
            """
            return (response, body.data(using: .utf8)!)
        }
        await controller.refreshNow()
        t.expectEqual(controller.nodes.count, 2)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"data":{"pauseMachine":{"id":"m1","name":"node-one","status":"ONLINE","workloadsPaused":true,"lastHeartbeat":null,"agentVersion":null,"updatedAt":"2026-01-01T00:00:01.000Z","createdAt":"2026-01-01T00:00:00.000Z"}}}
            """
            return (response, body.data(using: .utf8)!)
        }
        await controller.pause(nodeId: "m1")

        let m1 = controller.nodes.first(where: { $0.id == "m1" })
        let m2 = controller.nodes.first(where: { $0.id == "m2" })
        t.expect(m1?.workloadsPaused == true, "the targeted node must reflect the server's response")
        t.expect(m2?.workloadsPaused == false, "an untargeted node must be left alone")
        t.expect(controller.actionStates["m1"]?.isInFlight == false, "in-flight flag must clear after success")
        t.expect(controller.actionStates["m1"]?.errorMessage == nil, "no error should be recorded on success")
    }

    await t.run("a failed action records a per-node error without touching that node's last-known data") {
        let session = try await makeSignedInSession()
        let controller = RemoteNodesController(apiClient: session.apiClient, session: session)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"data":{"myMachines":[{"id":"m1","name":"node-one","status":"OFFLINE","workloadsPaused":false,"lastHeartbeat":null,"agentVersion":null,"updatedAt":"2026-01-01T00:00:00.000Z","createdAt":"2026-01-01T00:00:00.000Z"}]}}
            """
            return (response, body.data(using: .utf8)!)
        }
        await controller.refreshNow()

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"data":null,"errors":[{"message":"Failed to deliver stop command to the node — it may be offline."}]}"#
            return (response, body.data(using: .utf8)!)
        }
        await controller.forceStop(nodeId: "m1")

        t.expect(controller.actionStates["m1"]?.isInFlight == false)
        t.expect(controller.actionStates["m1"]?.errorMessage?.contains("may be offline") == true)
        t.expectEqual(controller.nodes.first?.status, .offline, "the node's last-known data must survive a failed action untouched")
    }

    await t.run("a failed refresh leaves previously-fetched nodes in place rather than clearing them") {
        let session = try await makeSignedInSession()
        let controller = RemoteNodesController(apiClient: session.apiClient, session: session)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"data":{"myMachines":[{"id":"m1","name":"node-one","status":"ONLINE","workloadsPaused":false,"lastHeartbeat":null,"agentVersion":null,"updatedAt":"2026-01-01T00:00:00.000Z","createdAt":"2026-01-01T00:00:00.000Z"}]}}
            """
            return (response, body.data(using: .utf8)!)
        }
        await controller.refreshNow()
        t.expectEqual(controller.nodes.count, 1)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, "Service Unavailable".data(using: .utf8)!)
        }
        await controller.refreshNow()

        t.expectEqual(controller.nodes.count, 1, "a transient fetch failure must not clear already-known nodes")
        t.expect(controller.lastFetchError != nil, "the failure must still be surfaced, just without wiping the list")
    }

    await t.run("forceStopAll() stops every node individually, surfacing partial failures per-row") {
        let session = try await makeSignedInSession()
        let controller = RemoteNodesController(apiClient: session.apiClient, session: session)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"data":{"myMachines":[
              {"id":"m1","name":"node-one","status":"ONLINE","workloadsPaused":false,"lastHeartbeat":null,"agentVersion":null,"updatedAt":"2026-01-01T00:00:00.000Z","createdAt":"2026-01-01T00:00:00.000Z"},
              {"id":"m2","name":"node-two","status":"OFFLINE","workloadsPaused":false,"lastHeartbeat":null,"agentVersion":null,"updatedAt":"2026-01-01T00:00:00.000Z","createdAt":"2026-01-02T00:00:00.000Z"}
            ]}}
            """
            return (response, body.data(using: .utf8)!)
        }
        await controller.refreshNow()
        t.expectEqual(controller.nodes.count, 2)

        // m1's forceStop succeeds, m2's fails (e.g. already offline) — the
        // mock branches per-request on which node id the GraphQL variables
        // actually target, exactly like the real backend would treat them
        // independently.
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = try JSONSerialization.jsonObject(with: MockURLProtocol.body(of: request)) as? [String: Any]
            let variables = json?["variables"] as? [String: Any]
            let targetId = variables?["id"] as? String

            if targetId == "m1" {
                let body = """
                {"data":{"forceStopMachine":{"id":"m1","name":"node-one","status":"ONLINE","workloadsPaused":false,"lastHeartbeat":null,"agentVersion":null,"updatedAt":"2026-01-01T00:00:01.000Z","createdAt":"2026-01-01T00:00:00.000Z"}}}
                """
                return (response, body.data(using: .utf8)!)
            } else {
                let body = #"{"data":null,"errors":[{"message":"Failed to deliver stop command to the node — it may be offline."}]}"#
                return (response, body.data(using: .utf8)!)
            }
        }

        await controller.forceStopAll()

        t.expect(controller.actionStates["m1"]?.errorMessage == nil, "m1's force-stop succeeded and should have no error")
        t.expect(controller.actionStates["m2"]?.errorMessage?.contains("may be offline") == true, "m2's force-stop failed and should record its own error, independent of m1")
        t.expect(controller.isForceStoppingAll == false, "the bulk flag must clear once the loop finishes, success or not")
    }

    await t.run("refreshNow() sorts nodes by createdAt ascending, regardless of the order the server returns them in") {
        let session = try await makeSignedInSession()
        let controller = RemoteNodesController(apiClient: session.apiClient, session: session)

        // Deliberately scrambled: server returns newest, then oldest, then
        // middle - regression guard for the "My Nodes" list reshuffling on
        // every poll (zsc-backend's own myMachines query lacked an ORDER
        // BY entirely). The client must not simply trust server order.
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"data":{"myMachines":[
              {"id":"newest","name":"newest","status":"ONLINE","workloadsPaused":false,"lastHeartbeat":null,"agentVersion":null,"updatedAt":"2026-01-01T00:00:00.000Z","createdAt":"2026-01-03T00:00:00.000Z"},
              {"id":"oldest","name":"oldest","status":"ONLINE","workloadsPaused":false,"lastHeartbeat":null,"agentVersion":null,"updatedAt":"2026-01-01T00:00:00.000Z","createdAt":"2026-01-01T00:00:00.000Z"},
              {"id":"middle","name":"middle","status":"ONLINE","workloadsPaused":false,"lastHeartbeat":null,"agentVersion":null,"updatedAt":"2026-01-01T00:00:00.000Z","createdAt":"2026-01-02T00:00:00.000Z"}
            ]}}
            """
            return (response, body.data(using: .utf8)!)
        }
        await controller.refreshNow()

        t.expectEqual(controller.nodes.map(\.id), ["oldest", "middle", "newest"], "must be sorted oldest-created-first regardless of server order")
    }

    await t.run("refreshNow() is a no-op (no network call, nodes cleared) while signed out") {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"data":{"login":{"user":{"id":"u1","email":"a@b.com"},"accessToken":"at","refreshToken":"rt","expiresAt":"2026-01-01T00:00:00.000Z"}}}"#
            return (response, body.data(using: .utf8)!)
        }
        let graphQL = GraphQLClient(endpoint: URL(string: "https://unit-test.invalid/graphql")!, urlSession: MockURLProtocol.makeSession())
        let signedOutSession = AccountSession(graphQLClient: graphQL) // never signed in
        let controller = RemoteNodesController(apiClient: signedOutSession.apiClient, session: signedOutSession)

        var networkCallMade = false
        MockURLProtocol.requestHandler = { request in
            networkCallMade = true
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, #"{"data":{"myMachines":[]}}"#.data(using: .utf8)!)
        }
        await controller.refreshNow()
        t.expect(!networkCallMade, "refreshNow() must not hit the network at all while signed out")
        t.expectEqual(controller.nodes.count, 0)
    }
}
