import Foundation

/// One cacheable content resource — a reference list, the curriculum, a picklist.
///
/// ADR-0009's content store keys everything by this rather than by a free string, so a typo cannot create a
/// second cache entry for the same list and the ETag file names are a closed set.
///
/// **Cacheable means not per-user** (invariant 8): every resource here is the same bytes for everybody, which is
/// exactly why it may be stored and revalidated. Nothing under `/v1/me`, `/v1/expenses`, or `/v1/reports` can
/// ever become one of these.
enum ContentResource: Hashable, Sendable {
    /// The 251 countries with their dial codes (#15).
    case countries
    /// The 160 ISO-4217 currencies (#15).
    case currencies
    /// The 14-question security bank (#15).
    case securityQuestions
    /// The 49 tips (#17).
    ///
    /// **The pool, not the day's tip.** The selected tip arrives inside Home's payload, chosen server-side by
    /// `dayKey` — the client owns no date arithmetic for it. This is what **Show me another** cycles through, and
    /// ADR-0016 requires that cycling to be in memory over cacheable content rather than a request per tap.
    case tips
    /// The two Expenses pick lists — 22 transport modes and 20 "Other" types (#18).
    ///
    /// One resource rather than two, because the design carries them as two constants side by side and every
    /// screen that wants one wants the other: Expenses opens with all seven categories on it, and a user who
    /// taps Transport is one tap from Other. Two ETagged resources would be two round trips for one screen's
    /// worth of options.
    case picklists
    /// One article's body, by id — `scams`, `remittance`, `credit` (#17).
    ///
    /// **The one resource with a parameter**, which is why this enum stopped being `String`-raw-valued: an
    /// article body is per-article and there are three of them today. The id is part of the cache key, so two
    /// articles cannot overwrite each other's file.
    ///
    /// Build it with ``forArticle(id:)`` rather than the case directly, so the id is sanitised **once, on the way
    /// in**. Sanitising it in `key` alone — which is what this did until review — left the *URL* built from the
    /// raw id, so `zakat_basics` and `zakatbasics` shared one cache key while fetching two different articles,
    /// and the reader got whichever was cached first with a `304` confirming it.
    case article(id: String)

    /// An article resource with its id reduced to letters, digits, and hyphens.
    ///
    /// The id arrives from a server payload and is used two ways — as a **file name** and as a **path segment** —
    /// so one containing a slash would write outside the store's directory and travel up the route. Filtering at
    /// the point of entry is what keeps the two consumers reading the same string.
    static func forArticle(id: String) -> ContentResource {
        .article(id: sanitised(id))
    }

    /// The characters an id may contain. Anything else is dropped rather than escaped: an article id is a slug the
    /// content pipeline chose, and one that needs escaping is a content bug worth noticing.
    private static func sanitised(_ id: String) -> String {
        id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    /// The resources that exist without being asked for by id. `CaseIterable` cannot describe this enum any
    /// more, and a hand-written list of the three fixed ones is honest about that — the articles are enumerated
    /// by the screen payload that carries their teasers, not by the client.
    static let fixed: [ContentResource] = [.countries, .currencies, .securityQuestions, .tips, .picklists]

    /// The cache key. Stable, and **safe as a file name**: an id arrives from a server payload, and one
    /// containing a slash would otherwise write outside the store's directory.
    var key: String {
        switch self {
        case .countries: "countries"
        case .currencies: "currencies"
        case .securityQuestions: "securityQuestions"
        case .tips: "tips"
        case .picklists: "picklists"
        case .article(let id): "article-\(Self.sanitised(id))"
        }
    }

    /// The file the store writes, and the name its ETag is recorded under.
    ///
    /// **No path here.** Which route a resource is fetched from belongs to `Endpoint`, one layer up: this type
    /// is an identity — a cache key and a file name — and a model that named a `/v1` path would be a model that
    /// knows there is a server (`LayeringTests`).
    var fileName: String { "\(key).json" }
}
