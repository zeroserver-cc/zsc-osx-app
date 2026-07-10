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
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

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
