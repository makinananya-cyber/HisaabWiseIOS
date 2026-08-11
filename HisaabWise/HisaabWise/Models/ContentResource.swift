import Foundation

/// One cacheable content resource — a reference list, the curriculum, a picklist.
///
/// ADR-0009's content store keys everything by this rather than by a free string, so a typo cannot create a
/// second cache entry for the same list and the ETag file names are a closed set.
///
/// **Cacheable means not per-user** (invariant 8): every resource here is the same bytes for everybody, which is
/// exactly why it may be stored and revalidated. Nothing under `/v1/me`, `/v1/expenses`, or `/v1/reports` can
/// ever become one of these.
enum ContentResource: String, CaseIterable, Sendable {
    /// The 251 countries with their dial codes (#15).
    case countries
    /// The 160 ISO-4217 currencies (#15).
    case currencies
    /// The 14-question security bank (#15).
    case securityQuestions

    /// The file the store writes, and the name its ETag is recorded under.
    ///
    /// **No path here.** Which route a resource is fetched from belongs to `Endpoint`, one layer up: this type
    /// is an identity — a cache key and a file name — and a model that named a `/v1` path would be a model that
    /// knows there is a server (`LayeringTests`).
    var fileName: String { "\(rawValue).json" }
}
