import Foundation

/// A minimal, hand-rolled assertion + reporting harness. This project has no
/// XCTest/swift-testing available in this environment (see Package.swift's
/// header comment for why) — this is the plain-Foundation substitute:
/// `expect`/`expectEqual` record failures instead of throwing, `TestRunner`
/// collects results across every test function and reports a summary,
/// exiting non-zero if anything failed (so `Scripts/run-tests.sh` can be
/// used as a real CI/regression gate, not just a manual smoke check).
final class TestRunner {
    private(set) var failures: [String] = []
    private(set) var passCount = 0
    private var currentTest = "<unknown>"

    func run(_ name: String, _ body: () throws -> Void) {
        currentTest = name
        do {
            try body()
            passCount += 1
        } catch {
            failures.append("\(name): threw \(error)")
        }
    }

    func run(_ name: String, _ body: () async throws -> Void) async {
        currentTest = name
        do {
            try await body()
            passCount += 1
        } catch {
            failures.append("\(name): threw \(error)")
        }
    }

    func expect(_ condition: Bool, _ message: String = "expectation failed", file: String = #fileID, line: Int = #line) {
        if !condition {
            fail("\(message) (\(file):\(line))")
        }
    }

    func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #fileID, line: Int = #line) {
        if a != b {
            fail("expected \(a) == \(b). \(message) (\(file):\(line))")
        }
    }

    func fail(_ message: String, file: String = #fileID, line: Int = #line) {
        failures.append("\(currentTest): \(message)")
    }

    func reportAndExit() -> Never {
        let total = passCount + failures.count
        print("")
        if failures.isEmpty {
            print("✅ All \(total) checks passed.")
            exit(0)
        } else {
            print("❌ \(failures.count)/\(total) checks failed:")
            for failure in failures {
                print("   - \(failure)")
            }
            exit(1)
        }
    }
}
