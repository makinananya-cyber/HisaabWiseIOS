import Foundation
import Observation

/// Expenses: **one read, four writes, and nothing derived from any of them** (ADR-0020, ADR-0033).
///
/// It is the first screen in the app that writes, so it is the first `BaseViewModel` that is also a form — and
/// that is what most of this object is. The read half is three lines; the rest is what the user is composing and
/// what the server said about it.
///
/// **What it owns is presentation state, and there is exactly this much of it:** the entry being typed, whether
/// a `lines` or `fixed` category is in edit mode and what its rows currently say, the last thing that happened
/// (for the toast), and a re-filing offer. Not one of those is a figure.
///
/// **It is the fourth owner of an error-to-presentation mapping**, alongside `BaseViewModel.load()` and the two
/// registration/sign-in forms, and `StateTaxonomyTests` names it. The reason is ADR-0019: a *write* that fails
/// offline has to become `LoadState.offline` rather than a field error, because there is nothing to correct — the
/// user has no connection — and a `MONTH_CLOSED` refusal has to become an offer rather than a sentence.
@MainActor
@Observable
final class ExpensesViewModel: BaseViewModel {
    /// Not `private(set)`: ``BaseViewModel`` requires a settable `state`, and the trade-off is recorded there.
    /// Mutation stays inside `load()` and ``write(_:)`` by convention.
    var state: LoadState<ExpensesScreen> = .loading

    // MARK: - What the user is composing

    /// The entry being typed, or an empty one.
    ///
    /// **It outlives the screen deliberately.** A write that fails offline replaces `state` with
    /// `LoadState.offline` (ADR-0019), and if the draft lived in the payload the user's typing would go with it.
    /// It does not, so the retry brings them back to the amount they had entered — which is the whole of what can
    /// be offered when there is no queue.
    private(set) var draft = EntryDraft()

    /// Whether the open `lines` or `fixed` category is in edit mode. The design's `.editbtn.on`.
    ///
    /// Reset by ``open(_:)``, as the design's `openCat` resets `editing`: arriving at a category should not find
    /// it mid-edit from the last visit.
    private(set) var isEditing = false

    /// The bills as they currently read in edit mode — **amounts in major units, as typed**.
    ///
    /// A separate array rather than edits applied to the payload, because the payload is server truth and these
    /// are unsaved keystrokes. They become one `PUT` that replaces the set (``BillLinesUpdate``).
    private(set) var billDrafts: [BillDraft] = []

    /// The `fixed` category's amount as it currently reads in edit mode, in major units.
    private(set) var fixedAmount = ""

    /// The last write that landed, for the toast. `nil` once it has been shown.
    ///
    /// A **value**, not a sentence: which words go with it is the screen's copy, so the choice is here and the
    /// wording is in the catalogue (ADR-0011). The design toasts on all four writes.
    private(set) var notice: Notice?

    /// The offer to file a refused write into the live month, or `nil`.
    private(set) var refileOffer: RefileOffer?

    /// Whether a write is in flight, so a control can say so rather than accepting a second tap.
    private(set) var isWriting = false

    // MARK: - Cacheable content

    /// The 42 pick-list options, once they have been fetched. Cacheable content, so a second launch revalidates
    /// with an ETag rather than downloading them again (ADR-0009).
    private var picklists: Picklists?

    /// What the user is authoring in, from the most recent payload.
    ///
    /// **Held rather than read from `state` at write time**, for the reason ``draft`` is: a write that failed
    /// offline has left `state` with no payload in it, and a retry still has to know which currency the figure in
    /// the box is in. Not a figure and not a total — a currency, a symbol, and an exponent, none of which a
    /// rollover or a refusal changes.
    private var authoring: ExpensesScreen.EntryCurrency?

    private let client: APIClient

    /// Where the pick lists come from. The **only** other thing this screen reads, and it is not part of the
    /// screen: ADR-0020 keeps cacheable content out of per-user payloads, so "one request per screen" and "the
    /// lists are a separate ETag'd resource" are the same decision rather than an exception to it.
    private let content: ContentLoader

    init(client: APIClient, content: ContentLoader) {
        self.client = client
        self.content = content
    }

    /// **The single read.** No second call, no join, and no calendar.
    func fetch() async throws -> ExpensesScreen {
        let screen = try await client.get(Endpoint.screenExpenses, as: ExpensesScreen.self)
        authoring = screen.entry
        return screen
    }

    /// Whether a *loaded* Expenses has nothing to show.
    ///
    /// `false`, deliberately, and this is the second screen where that needs saying. A month with nothing logged
    /// is **not** `LoadState.empty`: the seven categories are structural, the summary reads zero, and the form
    /// works. Routing it through `.empty` would replace a working screen with one sentence — the design puts the
    /// dashed "Nothing logged yet this month" box *inside* the category that is empty and leaves everything else
    /// alone (``HWEmptyNote``).
    func isEmpty(_ screen: ExpensesScreen) -> Bool { false }

    // MARK: - What the screen reads back

    /// One category out of the **current** payload, or `nil`.
    ///
    /// This is the pushed detail page's whole relationship with the screen: it is opened with an id and re-reads
    /// the category every time it draws, so a write that answers with a new payload re-renders the open page from
    /// server truth (ADR-0020). Holding the category instead would leave the detail showing the totals it was
    /// pushed with while the list behind it showed the new ones.
    ///
    /// A method here rather than `state.value?.category(id:)` at the call site, because a view reading `state` is
    /// one step from switching on it — the taxonomy has one owner (`StateTaxonomyTests`).
    func category(id: String) -> ExpensesScreen.Category? {
        state.value?.category(id: id)
    }

    /// "August" — the month every figure on screen belongs to.
    var monthLabel: String { state.value?.monthLabel ?? "" }

    /// The symbol beside the amount field. Decoration around a number being typed, never formatting (ADR-0003).
    var entrySymbol: String { authoring?.symbol ?? "" }

    /// The ISO code after it.
    var entryCode: String { authoring?.displayCode ?? "" }

    // MARK: - Opening a category

    /// Arriving at a category's detail page: leaves edit mode, and starts a form if this is a different category.
    ///
    /// **Two different lifetimes, which is why one call does two things.** Edit mode is per *visit* — the design's
    /// `openCat` resets `editing`, so Utilities → Edit → back → Utilities must not still say **Done** over rows the
    /// user abandoned. The entry draft is per *category*, and outlives a visit on purpose: an offline write replaces
    /// the payload with `LoadState.offline`, and the user comes back through the retry to find their amount still in
    /// the box.
    ///
    /// **The draft snapshots the field shape** rather than looking it up in `state` when Add is pressed, so a write
    /// can be validated and re-sent when there is no payload in hand — which is exactly what an offline write
    /// leaves behind.
    func open(_ categoryID: String) {
        cancelEditing()
        guard draft.categoryID != categoryID else { return }
        draft = EntryDraft(categoryID: categoryID, field: state.value?.category(id: categoryID)?.field)
    }

    /// Turns edit mode on for a `lines` or `fixed` category, filling its rows from the payload.
    ///
    /// The amounts become **major-unit strings** here, in the view model, because this is the last layer allowed
    /// to name a minor unit: `AccessibilityTests` forbids a view from mentioning one, so a view cannot convert a
    /// figure into something editable even by accident.
    func beginEditing(_ categoryID: String) {
        guard let category = state.value?.category(id: categoryID) else { return }

        isEditing = true
        // **Each figure is read with its own exponent, not the one the form sends in.** They are the same currency
        // in every payload the server will send — money is stored as authored and the display currency is what it
        // was authored in — but `entry.exponent` describes the figure being *typed* and a `Money`'s own describes
        // the figure being *shown*. Reading one with the other is the 10× error `TypedAmount` exists to prevent, so
        // each direction uses the exponent that belongs to it.
        billDrafts = category.lines.map {
            BillDraft(
                id: $0.id,
                name: $0.name,
                amount: TypedAmount.major($0.amount.minor, exponent: $0.amount.exponent),
                icon: $0.icon
            )
        }
        fixedAmount = TypedAmount.major(category.total.minor, exponent: category.total.exponent)
    }

    /// Leaves edit mode without saving — the way back out that does not commit.
    func cancelEditing() {
        isEditing = false
        billDrafts = []
        fixedAmount = ""
    }

    // MARK: - The entry form

    func editAmount(_ text: String) {
        draft.amount = text
        draft.failure = nil
    }

    func editLabel(_ text: String) {
        draft.label = text
        draft.failure = nil
    }

    /// A pick-list choice. **The id crosses, never the name** — the server resolves it into whichever language
    /// the reader asks for (§4.3 **[FIX]**, applied to a pick list).
    ///
    /// Whether the choice opens a free-text box is read from the option's own flag, not from its text. The design
    /// tests `/something else/i` against the English name, which stops working the moment the list is translated
    /// — the one option whose behaviour differs would become an ordinary option for every Arabic reader.
    func choose(option id: String) {
        draft.optionID = id
        draft.needsFreeText = option(id)?.opensFreeText ?? false
        if !draft.needsFreeText { draft.label = "" }
        draft.failure = nil
    }

    /// **Add expense** / **Add income** — `POST /v1/expenses`.
    ///
    /// The key is minted once per *intent* and reused across attempts, which is the caller-supplied form
    /// `APIClient.post` was written for: a write that reached the server and lost its response must not be filed
    /// twice when the user presses Add again.
    func addEntry() async {
        guard let request = validatedEntry() else { return }
        if draft.idempotencyKey == nil { draft.idempotencyKey = UUID().uuidString }
        guard let key = draft.idempotencyKey else { return }

        await write(.entry(categoryID: request.categoryID), notice: .entryAdded) {
            try await self.client.post(
                Endpoint.expenses,
                body: request,
                idempotencyKey: key,
                as: ExpensesScreen.self
            )
        }
    }

    /// Removes one entry — `DELETE /v1/expenses/:id`.
    ///
    /// No confirmation, as the design has it: the row goes and the totals move, which is visible and reversible
    /// by adding it again. A confirmation on every deletion of a ₹120 metro fare is friction on the core loop.
    func deleteEntry(id: String) async {
        // **An id that is not one the server issued is not sent at all.** `Endpoint.expense(id:)` reduces an id to
        // what a path segment may contain, and a *dropped* character would leave a request addressed to a
        // different, perfectly valid resource — `../me` becoming `/v1/expenses/me`. So the mangling is detected
        // rather than relied on. (`ContentResource.forArticle(id:)` drops for the same reason and can afford to:
        // the worst it produces is a cache-key collision, not a request somewhere else.)
        guard Endpoint.expense(id: id) == "\(Endpoint.expenses)/\(id)" else { return }

        await write(.other, notice: .entryRemoved) {
            try await self.client.delete(Endpoint.expense(id: id), as: ExpensesScreen.self)
        }
    }

    /// **Update rent** — `PUT /v1/expenses/fixed/{categoryId}`.
    func saveFixedAmount(categoryID: String) async {
        guard let currency = authoring,
              let minor = TypedAmount.minor(from: fixedAmount, exponent: currency.exponent)
        else { return }

        let body = FixedCostUpdate(amount: MoneyAmount(minor: minor, currency: currency.code.rawValue))
        await write(.other, notice: .fixedUpdated) {
            try await self.client.put(
                Endpoint.fixedCost(categoryID: categoryID),
                body: body,
                as: ExpensesScreen.self
            )
        }
        if state.value != nil { cancelEditing() }
    }

    /// **Update bills** — `PUT /v1/expenses/lines/{categoryId}`, replacing the whole set.
    ///
    /// A row with a blank name is dropped, which is where this departs from the design: `harvest()` renames one
    /// to `"Untitled bill"` and keeps it if the amount is positive, and that puts an English string the *client*
    /// invented into stored data an Arabic reader will see. A bill with no name is not a bill.
    func saveBills(categoryID: String) async {
        guard let currency = authoring else { return }

        let lines = billDrafts.compactMap { draft -> BillLinesUpdate.BillLine? in
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return BillLinesUpdate.BillLine(
                id: draft.id,
                name: name,
                // A named bill with nothing typed against it is zero rather than refused: a standing bill the
                // user has not been charged for this month is a real thing to record.
                amount: MoneyAmount(
                    minor: TypedAmount.minor(from: draft.amount, exponent: currency.exponent) ?? 0,
                    currency: currency.code.rawValue
                )
            )
        }

        let body = BillLinesUpdate(lines: lines)
        await write(.other, notice: .billsUpdated) {
            try await self.client.put(
                Endpoint.billLines(categoryID: categoryID),
                body: body,
                as: ExpensesScreen.self
            )
        }
        if state.value != nil { cancelEditing() }
    }

    func editFixedAmount(_ text: String) { fixedAmount = text }

    func addBill() {
        billDrafts.append(BillDraft(id: nil, name: "", amount: "", icon: .bolt))
    }

    func removeBill(at index: Int) {
        guard billDrafts.indices.contains(index) else { return }
        billDrafts.remove(at: index)
    }

    /// Edits one row. Both arguments are optional so a name change and an amount change are the same call —
    /// there are two fields in a row and each writes only its own half.
    func editBill(at index: Int, name: String? = nil, amount: String? = nil) {
        guard billDrafts.indices.contains(index) else { return }
        if let name { billDrafts[index].name = name }
        if let amount { billDrafts[index].amount = amount }
    }

    // MARK: - Re-filing across a rollover

    /// **Files the refused entry into the live month** (§4.5).
    ///
    /// A plain re-send, not a request carrying a corrected month: the server derives `monthKey` from the entry
    /// date in the user's stored timezone at write time and never trusts a client-supplied one, and the live
    /// month only ever moves forward. So the same body, sent now, lands in the month the offer named — and the
    /// entry comes back carrying the server's own date label, which is the "showing the true date" half of the
    /// rule.
    ///
    /// **A new key**, because this is a new intent. The first attempt was *refused*, so there is nothing on the
    /// server to deduplicate against, and filing into a different month is a different decision from the one the
    /// user originally made.
    func refile() async {
        guard refileOffer != nil else { return }
        draft.idempotencyKey = UUID().uuidString
        refileOffer = nil
        await addEntry()
    }

    /// Declines the offer. The draft goes with it: the user has said they do not want this filed, and leaving it
    /// in the box would offer them the same refusal on the next tap.
    func dismissRefileOffer() {
        refileOffer = nil
        draft.reset()
    }

    func dismissNotice() { notice = nil }

    // MARK: - The pick lists

    /// Fetches the two lists, once.
    ///
    /// On demand rather than with the screen, for the reason Home fetches its tip pool on the first press: the
    /// screen paints from one request, and 42 options nobody may ask for are not worth a second one at load time.
    /// Afterwards every sheet is local.
    ///
    /// A list that will not load leaves the screen alone and reports nothing — a picker with no options is a
    /// worse screen, not a broken one, and a failed *ancillary* fetch must not replace a screen that is fine
    /// (which is why this does not go through `load()`).
    func loadPicklists() async {
        guard picklists == nil else { return }
        picklists = try? await content.load(.picklists, as: Picklists.self)
    }

    /// The options for one list, or none if they have not arrived.
    func options(for picklist: ExpensesScreen.Picklist) -> [Picklists.Option] {
        picklists?.options(for: picklist) ?? []
    }

    /// One option by id, across both lists. Used to answer "does this choice open a text box".
    func option(_ id: String) -> Picklists.Option? {
        guard let picklists else { return nil }
        return (picklists.transport + picklists.other).first { $0.id == id }
    }

    /// The name of the chosen option, for the combo to show. `nil` while nothing is chosen.
    var chosenOptionName: String? {
        draft.optionID.flatMap { option($0)?.name }
    }

    // MARK: - Validation

    /// The body to send, or `nil` — in which case ``EntryDraft/failure`` says what is missing.
    ///
    /// **Local input validation, which is not a calculation** (ADR-0020): it decides whether there is something
    /// to send, not what any figure is. Every rule here is the design's own, and each refuses rather than guesses
    /// — the design's `?demo` auto-fill block is not extracted and nothing here fills a field for the user.
    private func validatedEntry() -> NewExpense? {
        guard let categoryID = draft.categoryID, let currency = authoring else { return nil }

        guard let minor = TypedAmount.minor(from: draft.amount, exponent: currency.exponent) else {
            draft.failure = .amountMissing
            return nil
        }

        let label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)

        if draft.field?.picklist != nil {
            guard draft.optionID != nil else {
                draft.failure = .optionMissing
                return nil
            }
            // The one option that asks what it actually was. Blank is refused, because "Something else" on its
            // own tells the user nothing next month.
            if draft.needsFreeText, label.isEmpty {
                draft.failure = .labelMissing
                return nil
            }
        } else if let field = draft.field, !field.isOptional, label.isEmpty {
            draft.failure = .labelMissing
            return nil
        }

        draft.failure = nil
        return NewExpense(
            categoryID: categoryID,
            // Exactly as authored, in the currency it was typed in — there is no storage base (§4.1 **[FIX]**).
            amount: MoneyAmount(minor: minor, currency: currency.code.rawValue),
            optionID: draft.optionID,
            label: label.isEmpty ? nil : label
        )
    }

    // MARK: - One write

    /// What a write **is**, for the two things that depend on it.
    ///
    /// Both were wrong when this took a bare category id, and review caught both. A `MONTH_CLOSED` refusal was
    /// offered for re-filing whatever had been refused, and accepting the offer always re-sent the *create* — so a
    /// deletion refused across a rollover boundary offered "add it to September" and then filed a new expense. And
    /// every write cleared the entry form on success, so deleting an old row wiped a half-typed new one, which the
    /// design's own `bindDelete` never does.
    private enum WriteKind {
        /// The entry form's own create — **the only write with something to re-file**, and the only one whose
        /// success empties the form.
        case entry(categoryID: String)

        /// A deletion, or a replacement of a fixed amount or a set of bills. None of these has a body to re-file:
        /// a deletion in a month that has closed is a deletion of something an archive now holds, and archives are
        /// immutable with no exceptions (§4.5, defect D6). A replacement can simply be tried again against the
        /// month that is now live, which is what the failed state's own retry does.
        case other
    }

    /// Sends a write and re-renders from whatever it answers with.
    ///
    /// **Every write returns the updated screen payload** (ADR-0020), so the totals, the summary split, and the
    /// wants bar all come back computed rather than being patched here. Patching is how a per-category total and
    /// a monthly summary come to disagree.
    private func write(
        _ kind: WriteKind,
        notice: Notice,
        _ send: @escaping () async throws -> ExpensesScreen
    ) async {
        guard !isWriting else { return }
        isWriting = true
        defer { isWriting = false }

        do {
            let screen = try await send()
            authoring = screen.entry
            state = .loaded(screen)
            // Only the form's own write empties the form.
            if case .entry = kind { draft.reset() }
            refileOffer = nil
            self.notice = notice
        } catch is CancellationError {
            // The screen is going away. Nobody to tell, and no state to set.
            return
        } catch {
            await apply(error, kind: kind)
        }
    }

    /// **The write half of the error mapping** — this object's own, and the reason it is named in
    /// `StateTaxonomyTests`.
    ///
    /// Three outcomes, and each is a decision rather than a default:
    ///
    /// - **Offline is `LoadState.offline`, not a field error** (ADR-0019). There is no queue and nothing to
    ///   correct; the screen says so and offers its own reload. What survives is ``draft``, so the retry does not
    ///   cost the user their typing.
    /// - **`MONTH_CLOSED` is an offer, not a sentence.** The month the write was addressed to has been archived
    ///   mid-request, archives are immutable with no exceptions (§4.5, defect D6), and the client offers to file
    ///   it into the live month instead.
    /// - **Everything else is a failed screen carrying its code**, exactly as a read's would be.
    private func apply(_ error: any Error, kind: WriteKind) async {
        guard let apiError = error as? APIError else {
            state = .failed(.unknown)
            return
        }

        // **Only a create is offered for re-filing**, because only a create has a body to re-file. Everything else
        // reads as a failed screen carrying the code, whose copy — "That month has closed. Reload to see the
        // current one." — is already in `ErrorCopy` and is exactly the right thing to say.
        if apiError.errorCode == .monthClosed, case .entry(let categoryID) = kind {
            await offerRefiling(categoryID: categoryID)
            return
        }

        switch apiError {
        case .offline:
            state = .offline
        case .server, .malformedResponse, .unauthenticated:
            state = .failed(apiError.errorCode ?? .unknown)
        }
    }

    /// Reloads, then offers the write to the month that is now live.
    ///
    /// **The reload is what makes the offer honest.** The label this screen was holding names the month that has
    /// just closed, so offering "add it to August instead" while the live month is September would be the app
    /// lying about the date — which is precisely what §4.5 says not to do. The live month's name is the server's
    /// to give, and one request is what it costs.
    ///
    /// A reload that itself fails leaves whatever state it produced and no offer: there is nothing to name.
    private func offerRefiling(categoryID: String) async {
        try? await load()
        guard let screen = state.value else { return }
        refileOffer = RefileOffer(categoryID: categoryID, monthLabel: screen.monthLabel)
    }
}

// MARK: - The values it owns

extension ExpensesViewModel {
    /// The entry being typed.
    ///
    /// A value rather than five loose properties, so "the form is empty" and "the form has this much of an
    /// entry in it" are things a test states about one thing.
    struct EntryDraft: Sendable, Equatable {
        /// Which category the form belongs to, from ``ExpensesViewModel/open(_:)``.
        var categoryID: String?

        /// The field shape this category's entries carry, **snapshotted** when the category was opened rather
        /// than looked up at send time — see `open(_:)` for why that matters after an offline write.
        var field: ExpensesScreen.Field?

        /// As typed, in major units. Parsed once, at the boundary (``TypedAmount``).
        var amount = ""

        /// The chosen pick-list option's id, or `nil`.
        var optionID: String?

        /// What the user typed into the free-text or "where was it" box.
        var label = ""

        /// Whether the chosen option asks for free text — from the option's own flag, never from its name.
        var needsFreeText = false

        /// What is missing, or `nil`.
        var failure: Failure?

        /// **One key per user intent**, minted on the first attempt and reused across retries so that a write
        /// which reached the server and lost its response is not filed twice (ADR-0022).
        var idempotencyKey: String?

        /// Whether there is anything in the form.
        ///
        /// The category is not part of the answer: the user is still standing on that page after a successful
        /// create, and the form being ready for the next entry is the design's own behaviour.
        var isEmpty: Bool {
            amount.isEmpty && optionID == nil && label.isEmpty
        }

        /// Empties the form, keeping the category and its field shape — which is what the design does after a
        /// successful add: `amount.value = ''; picked = null; custom = ''`.
        mutating func reset() {
            amount = ""
            optionID = nil
            label = ""
            needsFreeText = false
            failure = nil
            idempotencyKey = nil
        }

        /// What is wrong with the form, as a value — the same shape `SignInFailure` and `RegistrationFailure`
        /// have, and for the same reason: a rule worth writing is worth asserting, and a rendered sentence
        /// cannot be asserted about.
        enum Failure: Sendable, Equatable {
            /// The design's "Enter an amount greater than zero."
            case amountMissing
            /// Nothing chosen from the pick list.
            case optionMissing
            /// A required label left blank — either "Please fill this in." or, for the free-text option, "Tell us
            /// what it was."
            case labelMissing
        }
    }

    /// One bill as it currently reads in edit mode.
    ///
    /// **Not `Identifiable`, deliberately.** Its `id` is the *server's* line id and is `nil` for a row the user
    /// has just added, so two new rows would share one identity and `ForEach` would draw one of them. ``key`` is
    /// what a list is keyed on instead.
    struct BillDraft: Sendable, Equatable {
        /// The existing line's id, or `nil` for a row the user has just added — which is how the server tells a
        /// rename from a new bill.
        var id: String?
        var name: String
        /// As typed, in major units.
        var amount: String
        var icon: ExpensesScreen.Icon

        /// A stable identity for `ForEach`, including for the rows that have no server id yet.
        ///
        /// **A fresh `UUID` rather than the index**, because a row identified by its position loses the keyboard
        /// every time a row above it is deleted: the field the user was typing in becomes a different row's field.
        let key = UUID()
    }

    /// What just happened, for the toast. The words are the screen's; the choice is this object's.
    enum Notice: Sendable, Equatable, CaseIterable {
        case entryAdded
        case entryRemoved
        case fixedUpdated
        case billsUpdated
    }

    /// The offer to file a refused write into the live month (§4.5).
    struct RefileOffer: Sendable, Equatable {
        let categoryID: String

        /// **The live month's name, from the payload reloaded after the refusal** — not the label the screen was
        /// holding when the write went out, which names the month that has just closed. Offering to file into a
        /// month that is no longer live is the app lying about the date.
        let monthLabel: String
    }
}
