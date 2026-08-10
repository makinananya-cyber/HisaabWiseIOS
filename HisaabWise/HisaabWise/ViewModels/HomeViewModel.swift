import Observation

/// The view model behind Home (ADR-0018).
///
/// It fetches, maps the outcome to a ``LoadState``, and exposes that. It deliberately does not
/// *derive* anything: every figure on Home is computed server-side by decision (invariant 3), and
/// `Money` has no formatting API to call even if it wanted to (ADR-0003). A view model here is a
/// presentation-state owner, not a client-side model layer.
///
/// `@MainActor` per ADR-0001: view models are main-actor, the networking client is an actor, models
/// are `Sendable`.
@MainActor
@Observable
final class HomeViewModel {
    private(set) var state: LoadState<BudgetSummary> = .loading

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await client.get(Endpoint.budget, as: BudgetSummary.self))
        } catch APIError.offline {
            // Distinct from `.failed` on purpose, and the distinction is the reason the taxonomy
            // exists (ADR-0016).
            state = .offline
        } catch let error as APIError {
            state = .failed(error.errorCode ?? .unknown)
        } catch {
            state = .failed(.unknown)
        }
    }
}
