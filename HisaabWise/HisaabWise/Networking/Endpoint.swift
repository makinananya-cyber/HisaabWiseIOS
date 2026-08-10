/// The `/v1` paths the app calls.
///
/// One owner per path. The literal was previously repeated by the view model, the composition root, and
/// the preview helpers, which is three places for one string to drift in. Tests deliberately keep their
/// own literals so that a path change fails a test rather than being silently agreed to.
enum Endpoint {
    /// The only place 50/30/20, `saved`, and the goal verdict are computed (invariant 3). Home,
    /// Expenses, and Reports all read it.
    static let budget = "/v1/budget"
}
