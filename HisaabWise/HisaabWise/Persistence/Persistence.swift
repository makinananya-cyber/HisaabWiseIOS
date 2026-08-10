/// Everything the app keeps on the device.
///
/// What is here now, both behind `Models`' `TokenStore` protocol (ADR-0007):
///
/// - ``KeychainTokenStore`` — the refresh token, with
///   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so a session does not travel with an iCloud
///   backup restore.
/// - ``InMemoryTokenStore`` — the same seam with no device footprint, which is what leaving
///   "Keep me signed in" unchecked means.
///
/// What is still to arrive:
///
/// - The on-disk curriculum PDF the user downloads (ADR-0019).
/// - The on-disk content store with a persisted ETag per resource, distinct from `URLCache`
///   (ADR-0009).
///
/// There is deliberately **no** write queue and no SwiftData: every write needs a connection
/// (ADR-0019, superseding ADR-0005).
///
/// It depends on `Models` alone: persistence stores DTOs, and never reaches the network itself. The
/// access token is not stored here and has no store to put it in — it lives in memory on the client
/// actor and is never persisted (ADR-0007).
///
/// The namespace stays as the folder's overview. Nothing is nested inside it: the types above are
/// top-level, like every other type in the app.
enum Persistence {}
