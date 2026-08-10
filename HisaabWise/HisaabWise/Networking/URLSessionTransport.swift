import Foundation

/// The production ``Transport``: the one place in the app that performs an HTTP request.
///
/// It is deliberately almost empty. Everything a request means — which path, which verb, which
/// headers, what a status code implies — is ``APIClient``'s, so this type has nothing to test beyond
/// two facts about the session it runs on and one about cancellation. That thinness is what makes
/// `FixtureTransport` a fair stand-in for it (ADR-0013): a test that swaps this out is not skipping
/// any logic.
///
/// It takes no base URL and no configuration (ADR-0010). The URL arrives on the `URLRequest`
/// ``APIClient`` built from the base URL the composition root injected, and nothing here knows what
/// an environment is.
struct URLSessionTransport: Transport {
    private let session: URLSession

    init() {
        session = URLSession(configuration: Self.makeSessionConfiguration())
    }

    /// The configuration **this transport's session is actually running on**, so the two facts below
    /// are assertions rather than lines a reviewer has to notice.
    ///
    /// Read off the session rather than rebuilt, which is the difference between a test that pins the
    /// transport's behaviour and one that pins a factory the transport is free to stop calling.
    var sessionConfiguration: URLSessionConfiguration {
        session.configuration
    }

    private static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default

        // Invariant 8 — a cache HIT on per-user data is a data breach, not a performance win. The
        // per-request `.reloadIgnoringLocalCacheData` that `APIClient` sets stops a response being
        // *read* from the cache; it does not stop one being **written** to it. Every route this
        // session serves is per-user, so the cache is removed rather than bypassed, and a salary
        // never reaches the on-disk URL cache in the first place.
        //
        // This does not cost the content cache anything: curriculum, picklists, and the reference
        // lists use the explicit ETag'd store, and the cacheable content endpoints get a session of
        // their own when they arrive rather than sharing the one that carries per-user data
        // (ADR-0009, ADR-0022).
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        // ADR-0019 — there are no offline writes and no queue, so a request on a dead network must
        // fail and let the user retry. `waitsForConnectivity` would instead hold the request open
        // indefinitely, which is the queue we decided not to build, wearing a system API's name. It
        // defaults to `false`; it is set explicitly because the default *is* the decision here.
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30

        return configuration
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                // Unreachable over http(s), and not silently a success if it ever happens: the
                // protocol's contract is that a status code comes back with the body.
                throw URLError(.badServerResponse)
            }
            return (data, http)
        } catch let error as URLError where error.code == .cancelled {
            // `URLSession` reports a cancelled task as an ordinary network failure, which `APIClient`
            // reads as offline — telling a user who navigated away that they have no connection. The
            // translation belongs here, at the boundary that knows the difference; `BaseViewModel`
            // re-checks `Task.isCancelled` as a belt, and this is the braces.
            throw CancellationError()
        }
    }
}
