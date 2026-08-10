import Foundation

/// The one seam in the app.
///
/// Everything above this line is real code exercised by tests: real decoding, real state
/// transitions, real store logic. Below it sits either `URLSessionTransport` in production or
/// `FixtureTransport` in tests and previews. There are deliberately **no other injection points** —
/// a second seam means tests start exercising mocks of our own design instead of the app.
public protocol Transport: Sendable {
    /// Performs the request, or throws if it could not be completed.
    ///
    /// A thrown error means *the network did not answer*. Anything the server said, including a
    /// `4xx` or `5xx`, comes back as a normal return value; deciding what a status code means is
    /// ``APIClient``'s job, not the transport's.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
