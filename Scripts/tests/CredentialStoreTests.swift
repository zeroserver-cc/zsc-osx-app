import Foundation

func runCredentialStoreTests(_ t: TestRunner) {
    // Snapshot whatever is really stored (if the developer running this has
    // a real signed-in session) and restore it afterward — this test hits
    // the REAL Keychain entry CredentialStore.swift uses, since that's the
    // whole point of the test, but it must never destroy real user state.
    let originalSnapshot = CredentialStore.load()
    defer {
        if let originalSnapshot {
            try? CredentialStore.save(originalSnapshot)
        } else {
            CredentialStore.clear()
        }
    }

    t.run("CredentialStore save -> load returns an equal value") {
        let session = StoredSession(refreshToken: "rt_test_123", userId: "user_1", email: "test@example.com")
        try CredentialStore.save(session)
        let loaded = CredentialStore.load()
        t.expectEqual(loaded, session)
    }

    t.run("CredentialStore save overwrites a previous value (upsert, not append/error)") {
        let first = StoredSession(refreshToken: "rt_first", userId: "user_1", email: "first@example.com")
        let second = StoredSession(refreshToken: "rt_second", userId: "user_2", email: "second@example.com")
        try CredentialStore.save(first)
        try CredentialStore.save(second)
        let loaded = CredentialStore.load()
        t.expectEqual(loaded, second)
    }

    t.run("CredentialStore clear removes the stored session; load then returns nil") {
        let session = StoredSession(refreshToken: "rt_test_456", userId: "user_1", email: "test@example.com")
        try CredentialStore.save(session)
        t.expect(CredentialStore.load() != nil, "sanity check: save actually persisted something")
        CredentialStore.clear()
        t.expect(CredentialStore.load() == nil, "load after clear must return nil")
    }

    t.run("CredentialStore.load returns nil when nothing has ever been saved") {
        CredentialStore.clear()
        t.expect(CredentialStore.load() == nil)
    }
}
