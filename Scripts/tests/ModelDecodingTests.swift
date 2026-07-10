import Foundation

private let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

func runModelDecodingTests(_ t: TestRunner) {
    t.run("RemoteNode decodes the exact JSON shape the real backend returns") {
        // Captured verbatim from a live myMachines query against the local
        // dev backend during manual verification this session.
        let json = """
        {"id":"c184cada-81da-4e31-a90f-57130e1cf58e","name":"Mac-mini-de-Fernando.local","status":"IDLE","workloadsPaused":false,"lastHeartbeat":"2026-07-09T21:05:20.985Z","agentVersion":"0.1.11","updatedAt":"2026-07-09T21:05:20.988Z","createdAt":"2026-01-01T00:00:00.000Z"}
        """
        let node = try decoder.decode(RemoteNode.self, from: Data(json.utf8))
        t.expectEqual(node.id, "c184cada-81da-4e31-a90f-57130e1cf58e")
        t.expectEqual(node.status, .idle)
        t.expectEqual(node.workloadsPaused, false)
        t.expect(node.agentVersion == "0.1.11")
        // Regression guard: JSONDecoder's default .iso8601 strategy must
        // handle the fractional-second timestamps the real backend sends
        // ("...20.985Z") — this was manually verified once this session but
        // had no regression test protecting it against a future Foundation
        // change or a copy-paste "fix" that swaps in a stricter formatter.
        t.expect(node.lastHeartbeat != nil, "fractional-second ISO8601 timestamp must decode, not be silently dropped")
    }

    t.run("RemoteNode decodes agentVersion: null without crashing") {
        let json = """
        {"id":"41eb861a-d2fc-434e-a79f-308847e6957b","name":"production-server-01","status":"OFFLINE","workloadsPaused":false,"lastHeartbeat":"2026-07-09T20:59:41.487Z","agentVersion":null,"updatedAt":"2026-07-09T21:01:48.650Z","createdAt":"2026-01-01T00:00:00.000Z"}
        """
        let node = try decoder.decode(RemoteNode.self, from: Data(json.utf8))
        t.expect(node.agentVersion == nil)
        t.expectEqual(node.status, .offline)
    }

    t.run("RemoteNode decodes a response with no currentUsage key as currentUsage: nil") {
        // Every decode test above predates the currentUsage field entirely
        // (captured before it was added to the query) - this locks in that
        // an older/simpler payload shape still decodes cleanly rather than
        // requiring every field this client ever adds to always be present.
        let json = """
        {"id":"m1","name":"n1","status":"IDLE","workloadsPaused":false,"lastHeartbeat":null,"agentVersion":null,"updatedAt":"2026-07-09T21:05:20.988Z","createdAt":"2026-01-01T00:00:00.000Z"}
        """
        let node = try decoder.decode(RemoteNode.self, from: Data(json.utf8))
        t.expect(node.currentUsage == nil)
    }

    t.run("RemoteNode decodes currentUsage with diskPercent present") {
        let json = """
        {"id":"m1","name":"n1","status":"BUSY","workloadsPaused":false,"lastHeartbeat":null,"agentVersion":null,"updatedAt":"2026-07-09T21:05:20.988Z","createdAt":"2026-01-01T00:00:00.000Z","currentUsage":{"cpuPercent":12.4,"memoryPercent":45.6,"diskPercent":30.0,"recordedAt":"2026-07-09T21:05:00.000Z"}}
        """
        let node = try decoder.decode(RemoteNode.self, from: Data(json.utf8))
        t.expect(node.currentUsage?.cpuPercent == 12.4)
        t.expect(node.currentUsage?.memoryPercent == 45.6)
        t.expect(node.currentUsage?.diskPercent == 30.0)
    }

    t.run("RemoteNode decodes currentUsage with diskPercent: null") {
        let json = """
        {"id":"m1","name":"n1","status":"BUSY","workloadsPaused":false,"lastHeartbeat":null,"agentVersion":null,"updatedAt":"2026-07-09T21:05:20.988Z","createdAt":"2026-01-01T00:00:00.000Z","currentUsage":{"cpuPercent":12.4,"memoryPercent":45.6,"diskPercent":null,"recordedAt":"2026-07-09T21:05:00.000Z"}}
        """
        let node = try decoder.decode(RemoteNode.self, from: Data(json.utf8))
        t.expect(node.currentUsage != nil, "currentUsage itself must still decode even though one of its own fields is null")
        t.expect(node.currentUsage?.diskPercent == nil)
    }

    t.run("RemoteNodeStatus decodes every known backend status value") {
        let cases: [(String, RemoteNodeStatus)] = [
            ("OFFLINE", .offline), ("REGISTERING", .registering), ("IDLE", .idle),
            ("BUSY", .busy), ("OVERLOADED", .overloaded), ("ONLINE", .online)
        ]
        for (raw, expected) in cases {
            let decoded = try decoder.decode(RemoteNodeStatus.self, from: Data(#"""#.utf8) + Data(raw.utf8) + Data(#"""#.utf8))
            t.expectEqual(decoded, expected, "raw value \(raw)")
        }
    }

    t.run("RemoteNodeStatus decodes an unrecognized value to .unknown rather than throwing") {
        let decoded = try decoder.decode(RemoteNodeStatus.self, from: Data(#""SOME_FUTURE_STATUS""#.utf8))
        guard case .unknown(let raw) = decoded else {
            t.fail("expected .unknown, got \(decoded)")
            return
        }
        t.expectEqual(raw, "SOME_FUTURE_STATUS")
    }

    t.run("AuthPayload decodes the real login/refreshToken response shape") {
        let json = """
        {"user":{"id":"u1","email":"a@b.com"},"accessToken":"tok_access","refreshToken":"tok_refresh","expiresAt":"2026-07-09T21:39:38.000Z"}
        """
        let payload = try decoder.decode(AuthPayload.self, from: Data(json.utf8))
        t.expectEqual(payload.user.email, "a@b.com")
        t.expectEqual(payload.accessToken, "tok_access")
        t.expectEqual(payload.refreshToken, "tok_refresh")
    }

    t.run("AuthPayload decodes fine even when the server sends an extra legacy `token` field") {
        // Decodable silently ignores unrecognized keys by default — this
        // locks in that AuthPayload deliberately does NOT declare a `token`
        // property (see its doc comment) and that the extra field doesn't
        // break decoding.
        let json = """
        {"user":{"id":"u1","email":"a@b.com"},"token":"legacy","accessToken":"at","refreshToken":"rt","expiresAt":"2026-01-01T00:00:00.000Z"}
        """
        let payload = try decoder.decode(AuthPayload.self, from: Data(json.utf8))
        t.expectEqual(payload.accessToken, "at")
    }
}
