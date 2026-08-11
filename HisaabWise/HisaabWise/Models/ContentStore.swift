import Foundation

/// Where cacheable content is kept between launches, and the ETag it was fetched with.
///
/// ADR-0009 — the explicit on-disk JSON store, **distinct from `URLCache`**, which this app does not have at all
/// (`URLSessionTransport` keeps none, so that a per-user response can never be read from a cache — invariant 8).
///
/// A protocol so that tests and previews use a store that leaves nothing on the machine they run on, exactly as
/// `TokenStore` and `LanguageStore` are. `async` for the same reason those are: a disk read is one, and a
/// protocol that has to gain `async` later is one every call site must be revisited for.
protocol ContentStore: Sendable {
    /// The bytes last stored for this resource, or `nil` if it has never been fetched.
    func data(for resource: ContentResource) async throws -> Data?

    /// The ETag those bytes came with, or `nil`. Sent as `If-None-Match` so an unchanged list costs a `304`
    /// rather than a download.
    func etag(for resource: ContentResource) async throws -> String?

    /// Stores bytes and the ETag they arrived with, together — a store that could hold one without the other
    /// would eventually revalidate against an ETag for bytes it no longer has.
    func save(_ data: Data, etag: String?, for resource: ContentResource) async throws

    /// Forgets **one** resource. What a failed decode does, so a corrupt file is replaced rather than retried
    /// forever — and only that file: `clear()` removed all three, so one server payload this version of the app
    /// could not read took two perfectly good lists and their ETags with it, and the offline fallback the store
    /// exists for was gone until the next successful fetch.
    func remove(_ resource: ContentResource) async throws

    /// Forgets everything. Not a user-facing action either: it is for a sign-out or a reset, where *whose* content
    /// this is has changed.
    func clear() async throws
}
