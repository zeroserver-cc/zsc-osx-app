import Foundation

/// M4 (correctness/UI audit): locks in PresentableError's mapping from
/// GraphQLClient.TransportError/APIClientError to the exact user-facing
/// copy shown by AccountSession/RemoteNodesController — see
/// PresentableError.swift's doc comment for why this exists.
func runPresentableErrorTests(_ t: TestRunner) {
    let sessionExpiredText = "Your session expired. Please sign in again."
    let genericText = "Something went wrong. Please try again."
    let networkText = "Couldn't reach the server. Check your internet connection and try again."
    let malformedText = "Something went wrong talking to the server. Please try again."
    let serverTroubleText = "The server is having trouble right now. Please try again in a moment."

    t.run("PresentableError: .network maps to a friendly, connectivity-specific message") {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let message = PresentableError.message(for: GraphQLClient.TransportError.network(underlying))
        t.expectEqual(message, networkText)
    }

    t.run("PresentableError: .invalidHTTPResponse maps to the generic malformed-response message") {
        let message = PresentableError.message(for: GraphQLClient.TransportError.invalidHTTPResponse)
        t.expectEqual(message, malformedText)
    }

    t.run("PresentableError: .decoding maps to the generic malformed-response message") {
        let underlying = NSError(domain: "test", code: 1)
        let message = PresentableError.message(for: GraphQLClient.TransportError.decoding(underlying))
        t.expectEqual(message, malformedText)
    }

    t.run("PresentableError: .httpStatus(401) and .httpStatus(403) both map to the session-expired message") {
        t.expectEqual(PresentableError.message(for: GraphQLClient.TransportError.httpStatus(401, body: "")), sessionExpiredText)
        t.expectEqual(PresentableError.message(for: GraphQLClient.TransportError.httpStatus(403, body: "")), sessionExpiredText)
    }

    t.run("PresentableError: .httpStatus(5xx) maps to the server-trouble message") {
        t.expectEqual(PresentableError.message(for: GraphQLClient.TransportError.httpStatus(500, body: "")), serverTroubleText)
        t.expectEqual(PresentableError.message(for: GraphQLClient.TransportError.httpStatus(503, body: "internal trace, DB pool exhausted")), serverTroubleText)
    }

    t.run("PresentableError: an unrecognized httpStatus code maps to the generic message, not the raw code") {
        let message = PresentableError.message(for: GraphQLClient.TransportError.httpStatus(418, body: ""))
        t.expectEqual(message, genericText)
        t.expect(!message.contains("418"), "raw status code must not leak into the presented message")
    }

    t.run("PresentableError: .graphQL passes through the backend's own message unchanged") {
        let backendMessage = "This node may be offline; the stop command could not be delivered."
        let error = GraphQLClient.GraphQLError(message: backendMessage, extensions: nil)
        let message = PresentableError.message(for: GraphQLClient.TransportError.graphQL([error]))
        t.expectEqual(message, backendMessage, "deliberate business-logic messages must survive unchanged")
    }

    t.run("PresentableError: .graphQL with zero errors falls back to the generic message") {
        let message = PresentableError.message(for: GraphQLClient.TransportError.graphQL([]))
        t.expectEqual(message, genericText)
    }

    t.run("PresentableError: APIClientError.sessionExpired maps to the session-expired message") {
        let message = PresentableError.message(for: APIClientError.sessionExpired)
        t.expectEqual(message, sessionExpiredText)
    }

    t.run("PresentableError: APIClientError.notAuthenticated maps to the generic message") {
        let message = PresentableError.message(for: APIClientError.notAuthenticated)
        t.expectEqual(message, genericText)
    }

    t.run("PresentableError: a wholly unrecognized error type falls back to the generic message, not its raw description") {
        struct WeirdError: Error, LocalizedError {
            var errorDescription: String? { "Fatal: pointer 0x00007ff8 deref at frame 12" }
        }
        let message = PresentableError.message(for: WeirdError())
        t.expectEqual(message, genericText)
    }
}
