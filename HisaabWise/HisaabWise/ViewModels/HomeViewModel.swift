import Observation

/// The view model behind Home (ADR-0018).
///
/// It declares one request and nothing else. The `.loading` → `.loaded` / `.empty` / `.offline` /
/// `.failed` mapping it used to carry inline now lives once, in ``BaseViewModel/load()`` — which is the
/// whole of issue #11: twelve screens each writing their own `catch` is twelve chances to render
/// `APIError.offline` as a fault.
///
/// It deliberately does not *derive* anything: every figure on Home is computed server-side by decision
/// (invariant 3), and `Money` has no formatting API to call even if it wanted to (ADR-0003). A view
/// model here is a presentation-state owner, not a client-side model layer.
///
/// `@MainActor` per ADR-0001: view models are main-actor, the networking client is an actor, models are
/// `Sendable`.
@MainActor
@Observable
final class HomeViewModel: BaseViewModel {
    /// Not `private(set)`: ``BaseViewModel`` requires a settable `state`, and the trade-off is recorded
    /// there. Mutation stays inside `load()` by convention.
    var state: LoadState<BudgetSummary> = .loading

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetch() async throws -> BudgetSummary {
        try await client.get(Endpoint.budget, as: BudgetSummary.self)
    }

    // `isEmpty` is defaulted to `false`, which is right here: a salary is always a figure, so Home has
    // no empty state that a *loaded* response can produce. The screen still supplies empty copy, for
    // the first-run case the server answers for.
}
