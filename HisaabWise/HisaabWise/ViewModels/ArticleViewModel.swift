import Observation

/// One article's body — the other half of a "Read more about" row.
///
/// **A `BaseViewModel` over a cacheable resource**, which is the first time those two things meet. Every other
/// `BaseViewModel` reads a per-user endpoint through `APIClient`; this reads editorial content through
/// ``ContentLoader``, so the second visit is a `304` and an offline visit is the copy already on disk (ADR-0009).
/// The taxonomy is unchanged: a body that will not load is `.offline` or `.failed` exactly as a screen payload
/// would be, because `load()` maps both the same way.
@MainActor
@Observable
final class ArticleViewModel: BaseViewModel {
    var state: LoadState<ArticleBody> = .loading

    /// Which article. From the teaser Home was showing, so a body cannot be fetched for an article that was not
    /// on screen.
    let id: String

    private let content: ContentLoader

    init(id: String, content: ContentLoader) {
        self.id = id
        self.content = content
    }

    func fetch() async throws -> ArticleBody {
        try await content.load(.article(id: id), as: ArticleBody.self)
    }

    /// An article with no sections is a body that arrived but says nothing — which is `.empty` rather than
    /// `.loaded`, because a screen drawing a title over white space looks broken in a way the empty state does
    /// not.
    func isEmpty(_ body: ArticleBody) -> Bool { body.sections.isEmpty }
}
