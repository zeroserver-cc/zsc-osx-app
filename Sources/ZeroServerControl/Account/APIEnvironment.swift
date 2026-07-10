import Foundation

/// Identifies which zsc-backend GraphQL endpoint this app talks to for the
/// account/remote-nodes feature.
///
/// Mirrors AgentTarget.swift's ZSC_CONTROL_DEV_LABEL pattern exactly: normal
/// use always talks to production; ZSC_CONTROL_API_BASE_URL exists purely so
/// this feature can be exercised against a local docker-compose.dev.yml
/// zsc-backend stack instead (e.g.
/// `ZSC_CONTROL_API_BASE_URL=http://localhost:3001 swift run`). Only ever
/// set manually on the command line for development — the packaged .app
/// never has it set.
struct APIEnvironment {
    static let productionBaseURL = URL(string: "https://api.zeroserver.cc")!

    static var baseURL: URL {
        if let override = ProcessInfo.processInfo.environment["ZSC_CONTROL_API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        return productionBaseURL
    }

    /// zsc-backend serves GraphQL at this fixed path off the base URL in
    /// every environment — only scheme/host/port ever change, so that's all
    /// the override needs to control.
    static var graphQLEndpoint: URL {
        baseURL.appendingPathComponent("graphql")
    }

    /// Shown in Settings so it's never a mystery which backend you're
    /// talking to — this session alone involved manually toggling this via
    /// relaunch many times. Deliberately just "Production" vs "Local", never
    /// the raw override URL itself — that string shouldn't be surfaced in
    /// the UI even though it's already visible to anyone who set the env
    /// var in the first place.
    static var displayName: String {
        baseURL == productionBaseURL
            ? NSLocalizedString("connection.production", value: "Production", comment: "Shown in Settings' Connection section")
            : NSLocalizedString("connection.local", value: "Local", comment: "Shown in Settings' Connection section")
    }
}
