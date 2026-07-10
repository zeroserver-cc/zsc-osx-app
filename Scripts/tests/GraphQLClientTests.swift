import Foundation

struct DummyResponse: Decodable, Equatable { let dummy: String }

func runGraphQLClientTests(_ t: TestRunner) async {
    let endpoint = URL(string: "https://unit-test.invalid/graphql")!

    await t.run("GraphQLClient decodes a successful {data:...} response") {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"data":{"dummy":"hello"}}"#.data(using: .utf8)!
            return (response, body)
        }
        let client = GraphQLClient(endpoint: endpoint, urlSession: MockURLProtocol.makeSession())
        let result: DummyResponse = try await client.execute(operationName: "Dummy", query: "query Dummy { dummy }")
        t.expectEqual(result, DummyResponse(dummy: "hello"))
    }

    await t.run("GraphQLClient surfaces GraphQL-level errors as .graphQL, not a crash") {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"data":null,"errors":[{"message":"Access denied"}]}"#.data(using: .utf8)!
            return (response, body)
        }
        let client = GraphQLClient(endpoint: endpoint, urlSession: MockURLProtocol.makeSession())
        do {
            let _: DummyResponse = try await client.execute(operationName: "Dummy", query: "query Dummy { dummy }")
            t.fail("expected a thrown error, got a decoded value")
        } catch let error as GraphQLClient.TransportError {
            guard case .graphQL(let errors) = error else {
                t.fail("expected .graphQL, got \(error)")
                return
            }
            t.expectEqual(errors.first?.message, "Access denied")
        }
    }

    await t.run("GraphQLClient surfaces a non-2xx response with no JSON body as .httpStatus") {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!
            let body = "Bad Gateway".data(using: .utf8)!
            return (response, body)
        }
        let client = GraphQLClient(endpoint: endpoint, urlSession: MockURLProtocol.makeSession())
        do {
            let _: DummyResponse = try await client.execute(operationName: "Dummy", query: "query Dummy { dummy }")
            t.fail("expected a thrown error, got a decoded value")
        } catch let error as GraphQLClient.TransportError {
            guard case .httpStatus(let code, _) = error else {
                t.fail("expected .httpStatus, got \(error)")
                return
            }
            t.expectEqual(code, 502)
        }
    }

    await t.run("GraphQLClient surfaces malformed JSON on a 2xx response as .decoding") {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = "{not valid json".data(using: .utf8)!
            return (response, body)
        }
        let client = GraphQLClient(endpoint: endpoint, urlSession: MockURLProtocol.makeSession())
        do {
            let _: DummyResponse = try await client.execute(operationName: "Dummy", query: "query Dummy { dummy }")
            t.fail("expected a thrown error, got a decoded value")
        } catch let error as GraphQLClient.TransportError {
            guard case .decoding = error else {
                t.fail("expected .decoding, got \(error)")
                return
            }
        }
    }

    await t.run("GraphQLClient surfaces a real connection failure as .network") {
        // A real unreachable port, no mock — proves the transport-error path
        // works against genuine URLSession network failures, not just the
        // MockURLProtocol double used by every other test in this file.
        let unreachable = URL(string: "http://127.0.0.1:1")!
        let client = GraphQLClient(endpoint: unreachable, urlSession: URLSession(configuration: .ephemeral))
        do {
            let _: DummyResponse = try await client.execute(operationName: "Dummy", query: "query Dummy { dummy }")
            t.fail("expected a thrown error, got a decoded value")
        } catch let error as GraphQLClient.TransportError {
            guard case .network = error else {
                t.fail("expected .network, got \(error)")
                return
            }
        }
    }

    await t.run("GraphQLClient attaches the Authorization header when an access token is given") {
        var capturedAuthHeader: String?
        MockURLProtocol.requestHandler = { request in
            capturedAuthHeader = request.value(forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"data":{"dummy":"x"}}"#.data(using: .utf8)!
            return (response, body)
        }
        let client = GraphQLClient(endpoint: endpoint, urlSession: MockURLProtocol.makeSession())
        let _: DummyResponse = try await client.execute(
            operationName: "Dummy", query: "query Dummy { dummy }", accessToken: "tok_abc123"
        )
        t.expectEqual(capturedAuthHeader, "Bearer tok_abc123")
    }

    await t.run("GraphQLClient never string-interpolates variables into the query document text") {
        // A GraphQL-injection check: the query string sent over the wire
        // must be the fixed operation text, and untrusted values (email/
        // password/ids) must only ever appear inside the separate
        // `variables` JSON object, never spliced into `query`.
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { request in
            capturedBody = try JSONSerialization.jsonObject(with: MockURLProtocol.body(of: request)) as? [String: Any]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"data":{"dummy":"x"}}"#.data(using: .utf8)!
            return (response, body)
        }
        let client = GraphQLClient(endpoint: endpoint, urlSession: MockURLProtocol.makeSession())
        let maliciousInput = #"" } mutation Evil { deleteEverything } query Q { dummy(x: ""#
        let _: DummyResponse = try await client.execute(
            operationName: "Dummy",
            query: "query Dummy($x: String!) { dummy(x: $x) }",
            variables: ["x": maliciousInput]
        )
        let sentQuery = capturedBody?["query"] as? String
        t.expect(sentQuery == "query Dummy($x: String!) { dummy(x: $x) }", "query text must be exactly the fixed operation string, unmodified by variable content")
        let sentVariables = capturedBody?["variables"] as? [String: Any]
        t.expectEqual(sentVariables?["x"] as? String, maliciousInput, "the untrusted value must travel in `variables`, not be spliced into `query`")
    }
}
