import Foundation

/// A URLProtocol test double so GraphQLClient/APIClient can be tested
/// against deterministic canned responses — no test framework, no mocking
/// library, just standard Foundation. GraphQLClient already accepts an
/// injectable `URLSession`, so tests construct one with this protocol
/// registered instead of `.shared`, with zero changes to production code.
final class MockURLProtocol: URLProtocol {
    /// One handler per test, consulted once per request. Returning a
    /// closure (rather than a single canned response) lets a test model a
    /// SEQUENCE of responses across multiple calls to the same client
    /// (needed for APIClient's retry-after-refresh test), by having the
    /// handler itself track call count and branch.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// URLSession sometimes moves a POST body into `httpBodyStream` instead
    /// of leaving it on `httpBody` by the time a custom URLProtocol sees the
    /// request (a well-known Foundation quirk) — read whichever is present.
    static func body(of request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read > 0 { data.append(buffer, count: read) } else { break }
        }
        return data
    }
}
