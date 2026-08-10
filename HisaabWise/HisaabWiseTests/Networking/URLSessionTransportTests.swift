import Foundation
@testable import HisaabWise
import Testing

/// What the production transport is, as distinct from what it does.
///
/// It performs one call into `URLSession` and has no logic worth asserting, which is the property that
/// makes `FixtureTransport` a fair stand-in for it (ADR-0013). What is left to assert is the session it
/// runs on — read off the transport's own session, so a change to how one is built cannot leave these
/// green.
@Suite("URLSessionTransport")
struct URLSessionTransportTests {
    private let configuration = URLSessionTransport().sessionConfiguration

    @Test("keeps no URL cache, because a per-user response must not be written to one")
    func theSessionHasNoCache() {
        // Invariant 8 — a cache HIT on per-user data is a data breach. `APIClient`'s per-request policy
        // stops a response being *read* from the cache; only removing the cache stops one being written
        // to it. A salary on disk in `Caches/` is the failure this prevents (ADR-0022).
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("fails on a dead network instead of waiting for one")
    func doesNotWaitForConnectivity() {
        // ADR-0019 — no offline writes and no queue. A request held open until connectivity returns is
        // the queue we decided not to build, wearing a system API's name.
        #expect(configuration.waitsForConnectivity == false)
        // The 30 seconds itself is tuning, and is not what is asserted. What is asserted is that the
        // request gives up sooner than `URLSession`'s own 60-second default, because "the user retries"
        // is only a design if the failure arrives while they are still looking at the screen.
        #expect(configuration.timeoutIntervalForRequest < 60)
    }
}
