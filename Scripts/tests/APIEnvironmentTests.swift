import Foundation

/// Locks in APIEnvironment.displayName — shown in Settings' Connection
/// section so it's never a mystery which backend you're talking to.
func runAPIEnvironmentTests(_ t: TestRunner) {
    let envKey = "ZSC_CONTROL_API_BASE_URL"
    // Snapshot/restore around this test, same convention as
    // CredentialStoreTests — this env var can be genuinely set on a
    // developer's machine (that's its whole purpose), so a test must never
    // permanently clear or leak a value past its own run.
    let original = ProcessInfo.processInfo.environment[envKey]
    defer {
        if let original {
            setenv(envKey, original, 1)
        } else {
            unsetenv(envKey)
        }
    }

    t.run("displayName is \"Production\" when no override is set") {
        unsetenv(envKey)
        t.expectEqual(APIEnvironment.baseURL, APIEnvironment.productionBaseURL)
        t.expectEqual(APIEnvironment.displayName, "Production")
    }

    t.run("displayName is \"Local\" (never the raw URL) when ZSC_CONTROL_API_BASE_URL is set") {
        setenv(envKey, "http://localhost:3001", 1)
        t.expectEqual(APIEnvironment.displayName, "Local", "the actual override URL must never be surfaced in the UI")
    }
}
