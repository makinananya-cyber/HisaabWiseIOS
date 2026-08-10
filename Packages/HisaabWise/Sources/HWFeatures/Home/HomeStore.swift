import HWCore
import HWNetworking
import Observation

/// Home's state.
///
/// ADR-0002 — one `@Observable` **store** per tab, injected via `@Environment`. Not a view model:
/// every figure on Home is computed server-side by decision (invariant 3), so a client-side model
/// layer would have nothing to model. What is left is fetch, decode, and expose a ``LoadState`` — and
/// that is deliberately all this does.
///
/// `@MainActor` per ADR-0001: stores are main-actor, the networking client is an actor, DTOs are
/// `Sendable`.
@MainActor
@Observable
public final class HomeStore {
    public private(set) var state: LoadState<BudgetSummary> = .loading

    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func load() async {
        state = .loading
        do {
            state = .loaded(try await client.get(Self.budgetPath, as: BudgetSummary.self))
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

    /// `GET /v1/budget` — the single endpoint behind every figure on Home, Expenses, and Reports.
    private static let budgetPath = "/v1/budget"
}
