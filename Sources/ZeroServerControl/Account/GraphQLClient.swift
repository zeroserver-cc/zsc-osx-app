import Foundation

/// Dependency-free POST-JSON GraphQL transport. Knows nothing about auth
/// refresh, sign-in state, or which operations exist — APIClient owns all
/// of that. This type's only job is: send {query, variables}, decode
/// {data, errors}, and surface transport failures distinctly from
/// GraphQL-level errors so callers (APIClient) can tell "the network is
/// down" apart from "the server rejected an expired token."
///
/// Hand-rolled on URLSession rather than pulling in a GraphQL package —
/// this app talks to a handful of operations total, and staying
/// dependency-free keeps `swift build` fast and Xcode-CLT-only friendly
/// (see CLAUDE.md).
final class GraphQLClient {

    struct GraphQLError: Decodable {
        struct Extensions: Decodable { let code: String? }
        let message: String
        let extensions: Extensions?
    }

    enum TransportError: Error, LocalizedError {
        case network(Error)
        case invalidHTTPResponse
        case httpStatus(Int, body: String)
        case decoding(Error)
        case graphQL([GraphQLError])

        var errorDescription: String? {
            switch self {
            case .network(let e): return "Could not reach the server: \(e.localizedDescription)"
            case .invalidHTTPResponse: return "Received an unexpected response from the server."
            case .httpStatus(let code, _): return "Server returned HTTP \(code)."
            case .decoding: return "Could not understand the server's response."
            case .graphQL(let errors): return errors.first?.message ?? "The server reported an error."
            }
        }
    }

    private let endpoint: URL
    private let urlSession: URLSession
    private let decoder = GraphQLClient.makeDecoder()

    /// Exposed (not just built inline into `decoder`) so anything decoding
    /// this app's GraphQL response shapes outside of `execute` — today,
    /// only `ModelDecodingTests.swift`'s fixture-based regression tests —
    /// uses this exact same date-decoding behavior instead of independently
    /// reimplementing an `.iso8601` `JSONDecoder`. That duplication is
    /// exactly what let this decoder's real bug (below) go unnoticed:
    /// the test file had its own separate, naive `.iso8601` decoder that
    /// happened to still work, so it never exercised the fix.
    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            // zsc-backend (Node's `Date.toISOString()`) always emits
            // millisecond fractional seconds ("...20.985Z"). JSONDecoder's
            // built-in `.iso8601` strategy relies on ISO8601DateFormatter's
            // *default* formatOptions, and whether those defaults tolerate
            // fractional seconds has changed across Foundation
            // implementations (confirmed the hard way: this decoded fine
            // locally on a newer Swift/Foundation but failed outright with
            // "Expected date string to be ISO8601-formatted." the first
            // time this ran in CI, on an older one) — every authenticated
            // response has a date field, so that difference alone was a
            // total, silent decode failure for every GraphQL call on
            // whichever end users happen to run an OS/Foundation on the
            // stricter side of that line. Explicit formatOptions (tried
            // with, then without, fractional seconds) are deterministic
            // regardless of which Foundation the OS ships.
            if let date = iso8601WithFractionalSeconds.date(from: dateString) {
                return date
            }
            if let date = iso8601.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected date string to be ISO8601-formatted: \(dateString)"
            )
        }
        return d
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601 = ISO8601DateFormatter()

    init(endpoint: URL = APIEnvironment.graphQLEndpoint, urlSession: URLSession = .shared) {
        self.endpoint = endpoint
        self.urlSession = urlSession
    }

    /// `variables` is a plain `[String: Any]` (not a generic Encodable)
    /// deliberately — a heterogeneous Encodable dictionary is awkward in
    /// Swift for no real benefit here; JSONSerialization handles the
    /// handful of String/nested-dictionary shapes our operations need.
    func execute<Response: Decodable>(
        operationName: String,
        query: String,
        variables: [String: Any] = [:],
        accessToken: String? = nil
    ) async throws -> Response {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "operationName": operationName,
            "query": query,
            "variables": variables
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw TransportError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TransportError.invalidHTTPResponse
        }

        let envelope: Envelope<Response>
        do {
            envelope = try decoder.decode(Envelope<Response>.self, from: data)
        } catch {
            // A misconfigured endpoint/proxy can return a non-2xx with no
            // JSON body at all — prefer that diagnosis over a raw decode error.
            if !(200...299).contains(http.statusCode) {
                throw TransportError.httpStatus(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
            }
            throw TransportError.decoding(error)
        }

        if let errors = envelope.errors, !errors.isEmpty {
            throw TransportError.graphQL(errors)
        }
        guard let value = envelope.data else {
            throw TransportError.invalidHTTPResponse
        }
        return value
    }
}

/// A generic type can't be declared nested inside a generic function in
/// Swift, so this lives at file scope instead of inline in `execute`.
private struct Envelope<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLClient.GraphQLError]?
}
