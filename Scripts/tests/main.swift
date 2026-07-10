import Foundation

@MainActor
func runAllTests() async {
    let t = TestRunner()

    runCredentialStoreTests(t)
    runAPIEnvironmentTests(t)
    runAgentTargetTests(t)
    runModelDecodingTests(t)
    runRemoteNodeActionLogicTests(t)
    runRemoteNodeUsageSummaryTests(t)
    await runGraphQLClientTests(t)
    await runAPIClientTests(t)
    await runRemoteNodesControllerTests(t)
    await runAccountSessionTests(t)
    runPresentableErrorTests(t)
    runForceStopWordingTests(t)

    t.reportAndExit()
}

Task { @MainActor in
    await runAllTests()
}
RunLoop.main.run()
