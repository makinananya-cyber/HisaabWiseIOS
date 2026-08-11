import Foundation

/// `POST /v1/expenses` — one new entry in a `log` category.
///
/// **The amount is `{minor, currency}` and the currency is the one the user typed in** (invariant 1, Product
/// Spec §4.1 **[FIX]**): money is stored exactly as authored and there is no storage base, so this is not "the
/// amount converted into something" — it is what was typed, with a label saying what it was typed in. The
/// design filed everything into a hardcoded `BASE = 'AED'`, converting on the way in, which is the storage
/// base the [FIX] removes.
///
/// **No date and no `monthKey`.** The server derives the month from the entry date in the user's stored
/// timezone at write time and freezes it (§4.5); a client-supplied `monthKey` is never trusted, so there is
/// nothing to supply. That is also what makes the `MONTH_CLOSED` path a plain re-send rather than a request
/// carrying a corrected month.
struct NewExpense: Sendable, Hashable, Encodable {
    let categoryID: String
    let amount: MoneyAmount

    /// The chosen pick-list option, or `nil` for a typed or unlabelled entry.
    ///
    /// **The id, not the name** — the same rule §4.3 **[FIX]** applies to a security question. The server
    /// resolves it into a name in whichever language the reader asks for, so the entry an Arabic user files
    /// reads in Arabic and the same entry reads in English for an English one. Sending the displayed string
    /// would freeze one language into the stored data.
    let optionID: String?

    /// What the user typed, or `nil`.
    ///
    /// Both this and ``optionID`` are set together in exactly one case: the "Other" option that asks for free
    /// text. The option says *which* kind of thing it was and the text says what.
    let label: String?

    private enum CodingKeys: String, CodingKey {
        case categoryID = "categoryId"
        case amount
        case optionID = "optionId"
        case label
    }
}

/// `PUT /v1/expenses/fixed/{categoryId}` — the one editable monthly amount of a `fixed` category.
///
/// A `PUT` because it **replaces** a value: sending it twice leaves the user where sending it once did, which
/// is why it carries no `Idempotency-Key` (ADR-0022). Rent is the only caller today, and the route is keyed by
/// category rather than named `rent` so that a second `fixed` category needs no second route.
struct FixedCostUpdate: Sendable, Hashable, Encodable {
    let amount: MoneyAmount
}

/// `PUT /v1/expenses/lines/{categoryId}` — the whole set of bills for a `lines` category, replaced.
///
/// **One request for the whole set, because that is the gesture the design has.** Utilities' edit mode lets the
/// user rename a bill, change two amounts, delete a third, and add a fourth, and then commits all of it with
/// **Update bills**. Expressing that as a `POST`, two `PUT`s, and a `DELETE` would be four requests for one
/// user intent, four chances to fail halfway, and four screen payloads of which only the last is the truth.
///
/// So the set is replaced: a line with an `id` is the one that already existed, and a line without one is new.
/// Anything the client does not send is gone — which is exactly what the design's `harvest()` does when it
/// filters the deleted rows out before saving.
struct BillLinesUpdate: Sendable, Hashable, Encodable {
    let lines: [BillLine]

    /// One bill, as it is being saved.
    struct BillLine: Sendable, Hashable, Encodable, Identifiable {
        /// The existing line's id, or `nil` for one the user has just added.
        let id: String?
        let name: String
        let amount: MoneyAmount
    }
}
