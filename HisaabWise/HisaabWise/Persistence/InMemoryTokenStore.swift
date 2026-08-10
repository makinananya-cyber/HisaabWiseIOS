/// The refresh token in memory — what leaving "Keep me signed in" unchecked means (ADR-0007).
///
/// The off-state Product Spec §3.2 never defined: the session works exactly as a kept one does for as
/// long as the app is running, and ends when the process does. There is no expiry to manage and nothing
/// to clean up on next launch, because nothing was written.
///
/// An `actor` rather than a `final class` with a lock, since `TokenStore` is `Sendable` and the client
/// reads this from its own actor. It is also what makes this a fair stand-in for the Keychain store in a
/// test: both are `await`ed, so nothing under test takes a synchronous path only one of them offers.
actor InMemoryTokenStore: TokenStore {
    private var token: String?

    /// - Parameter refreshToken: a session already in progress. Used by tests to stand up a client that
    ///   has something to refresh with, which is otherwise only reachable by signing in.
    init(refreshToken: String? = nil) {
        token = refreshToken
    }

    func refreshToken() -> String? { token }

    func save(refreshToken: String) { token = refreshToken }

    func clear() { token = nil }
}
