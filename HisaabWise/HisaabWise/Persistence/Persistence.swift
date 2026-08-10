/// Everything the app keeps on the device.
///
/// The target exists from the first commit so that the things arriving in it have an obvious home
/// rather than being invented wherever they are first needed:
///
/// - `KeychainTokenStore` — the refresh token behind `HWCore`'s `TokenStore` protocol
///   (ADR-0007), with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so a session does not
///   travel with an iCloud backup restore.
/// - The SwiftData write queue of `PendingWrite` rows, drained in `createdAt` order (ADR-0005).
/// - The on-disk content store with a persisted ETag per resource, distinct from `URLCache`
///   (ADR-0009).
///
/// It depends on `HWCore` alone: persistence stores DTOs, and never reaches the network itself.
///
/// The namespace is empty until the first of those lands.
enum Persistence {}
