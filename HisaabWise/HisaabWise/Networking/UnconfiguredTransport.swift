import Foundation

/// The transport a build has when no real one has been wired up yet.
///
/// It always fails, which ``APIClient`` maps to `.offline`, so an unconfigured build shows the offline
/// state rather than crashing on launch. Temporary by construction: `URLSessionTransport` and the base
/// URL from build configuration replace it (issue #3, ADR-0010), and Rule 7 forbids the obvious
/// shortcut of hardcoding a host in the meantime.
struct UnconfiguredTransport: Transport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.cannotConnectToHost)
    }
}
