/// `GET /v1/budget?month=` — the only place 50/30/20, `saved`, and the goal verdict are computed
/// (invariant 3, Technical Spec §5). Home, Expenses, and Reports all read this one response, which
/// is why no client type derives any figure on it.
///
/// The walking skeleton decodes the two fields the tracer bullet needs. The response carries the
/// rest of the amended §5 field set — `needs`, `wantsSpent`, `wantsAllowance`, `savingsAllowance`,
/// `adapted`, `saved`, `net`, `overspent`, `surplus`, `verdict` — and the fixture corpus already
/// includes them, so each arrives here as a stored property when the screen that draws it does.
/// Unknown keys are ignored, so a field landing on the wire ahead of its screen is not a breakage.
struct BudgetSummary: Sendable, Hashable, Decodable {
    /// The month these figures describe, as a `monthKey` — `YYYY-MM` in the user's stored
    /// timezone. Server-owned: day and month boundaries are never computed from the device clock
    /// (invariant 6).
    let month: String

    /// Salary plus any additional income this month.
    ///
    /// Defect D1 — the prototype hardcoded `salary: 8000` on Home and defaulted to ₹65,000 on
    /// Account. Salary has exactly one owner, the server, and this is the field every screen reads.
    let income: Money
}
