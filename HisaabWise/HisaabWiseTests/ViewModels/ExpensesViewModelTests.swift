import Foundation
@testable import HisaabWise
import Testing

/// Expenses reads **one endpoint**, writes through four, and derives nothing from any of them (ADR-0020,
/// ADR-0033).
///
/// The four claims the ticket asks for are each a section below: the three structural kinds behave differently,
/// a per-category total is *read* rather than computed, a create attempted with no connection surfaces offline
/// and stores nothing, and a `MONTH_CLOSED` create is offered for re-filing into the live month.
///
/// **The `LoadState` mapping for a read is not asserted here.** It lives in ``BaseViewModel/load()`` and is
/// asserted in `BaseViewModelTests` — one owner, one suite. What *is* asserted here is the mapping for a
/// **write**, because that is this view model's own (`StateTaxonomyTests` names it).
@Suite("ExpensesViewModel")
@MainActor
struct ExpensesViewModelTests {
    private static func makeViewModel(
        _ transport: FixtureTransport,
        store: any ContentStore = InMemoryContentStore()
    ) -> ExpensesViewModel {
        let client = TestBench.client(transport)
        return ExpensesViewModel(client: client, content: ContentLoader(client: client, store: store))
    }

    /// The screen, the pick lists, and **every write answering with the screen again** (ADR-0020).
    ///
    /// The instance routes are spelled out rather than claimed by the fixture, because a fixture claims a *route*
    /// and these are addresses inside one: `/v1/expenses/t2` and `/v1/expenses/fixed/rent` exist because this
    /// month's payload has a `t2` and a `rent` in it, and a corpus that named them would be a corpus asserting
    /// which ids the server hands out.
    private static func stubs(
        _ screen: Fixture = .expensesINR
    ) throws -> [String: FixtureTransport.Outcome] {
        [
            Endpoint.screenExpenses: try .ok(screen),
            Endpoint.contentPicklists: try .ok(.picklists),
            Endpoint.expenses: try .ok(screen),
            Endpoint.expense(id: "t2"): try .ok(screen),
            Endpoint.fixedCost(categoryID: "rent"): try .ok(screen),
            Endpoint.billLines(categoryID: "utilities"): try .ok(screen),
        ]
    }

    private static func loaded(
        _ transport: FixtureTransport
    ) async throws -> (ExpensesViewModel, ExpensesScreen) {
        let viewModel = makeViewModel(transport)
        try await viewModel.load()
        return (viewModel, try #require(viewModel.state.value))
    }

    /// A screen payload with a different `monthLabel` — **the month after a rollover**.
    ///
    /// Built by patching rather than by keeping a fourth fixture, because what makes the re-filing tests below
    /// mean anything is that the two labels *differ*: an offer naming the month the write was refused from would
    /// pass against two payloads that agree, and it is exactly the mistake §4.5 says not to make.
    private static func rolledOver(_ fixture: Fixture, into month: String) throws -> Data {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(fixture)) as? [String: Any]
        )
        payload["monthLabel"] = month
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// The last request of one verb to reach the transport.
    private static func last(
        _ method: String,
        to transport: FixtureTransport
    ) async throws -> FixtureTransport.RecordedRequest {
        try #require(await transport.recordedRequests.last { $0.method == method })
    }

    /// A request's body as JSON. A helper rather than a nested `#require` at each call site, because the macro
    /// cannot expand inside itself.
    private static func body(of request: FixtureTransport.RecordedRequest) throws -> [String: Any] {
        let data = try #require(request.body)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// `409 MONTH_CLOSED` — a write that crossed a rollover boundary in flight.
    private static let monthClosed = FixtureTransport.Outcome.response(
        status: 409,
        body: Data(#"{"error":{"code":"MONTH_CLOSED","message":"that month is closed"}}"#.utf8)
    )

    @Test("starts loading, before anything has been asked for")
    func startsLoading() {
        #expect(Self.makeViewModel(FixtureTransport()).state == .loading)
    }

    // MARK: - One read

    /// **The single request, asserted as a request count.** The design fetched nothing and computed everything;
    /// the failure mode this replaces is a screen that reads the budget, the categories, and the entries
    /// separately and joins them, because the join is a calculation (ADR-0020).
    @Test("asks for the screen once, and asks for nothing else")
    func asksForTheScreenOnce() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let viewModel = Self.makeViewModel(transport)

        try await viewModel.load()

        let requests = await transport.recordedRequests
        #expect(requests.map(\.path) == [Endpoint.screenExpenses])
        #expect(requests.map(\.method) == ["GET"])
        // And specifically not the budget engine's own endpoint, which no screen reads (ADR-0020).
        #expect(await transport.requestCount(for: Endpoint.budget) == 0)
    }

    @Test("decodes the summary, the wants bar, and all seven categories")
    func decodesTheScreen() async throws {
        let (_, screen) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        #expect(screen.monthLabel == "August")
        #expect(screen.summary.total.display == "₹5,539")
        #expect(screen.summary.fixed.display == "₹3,529")
        #expect(screen.summary.variable.display == "₹2,010")
        #expect(screen.summary.income.display == "₹900")

        #expect(screen.wants.percentageLabel == "6%")
        #expect(!screen.wants.isOver)

        #expect(screen.categories.count == 7)
        #expect(screen.entry.code.rawValue == "INR")
        #expect(screen.entry.exponent == 2)
    }

    /// **Seven categories in three kinds, and the kinds are the interesting part.** Getting the split wrong
    /// means rewriting the screen, so it is asserted as a partition rather than category by category.
    @Test("the seven categories fall into the three kinds the spec names")
    func theThreeKinds() async throws {
        let (_, screen) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        let byKind = Dictionary(grouping: screen.categories, by: \.kind).mapValues { $0.map(\.id) }

        #expect(byKind[.log] == ["groceries", "transport", "entertainment", "other", "income"])
        #expect(byKind[.lines] == ["utilities"])
        #expect(byKind[.fixed] == ["rent"])
    }

    /// `log` — append-only entries, each individually deletable, and each carrying a **server-computed** date
    /// label. There is no timestamp in the payload at all, which is the stronger form of invariant 6: the client
    /// could not derive the label if it wanted to.
    @Test("the log kind carries deletable entries with server-computed date labels")
    func theLogKind() async throws {
        let (_, screen) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))
        let transport = try #require(screen.category(id: "transport"))

        #expect(transport.kind == .log)
        #expect(transport.entries.map(\.id) == ["t1", "t2"])
        #expect(transport.entries.map(\.dateLabel) == ["Today", "Yesterday"])
        #expect(transport.entries.first?.label == "Metro / subway")
        // A count *and* a plural, so the server says it.
        #expect(transport.entryCountLabel == "2 entries")
        #expect(try #require(screen.category(id: "entertainment")).entryCountLabel == "1 entry")
        // And the field a transport entry is labelled with is a pick from a server-served list.
        #expect(transport.field == .transportMode)
        #expect(transport.field?.picklist == .transport)
    }

    /// `lines` — several named monthly bills, each addable, editable, and removable. No entries and no date
    /// labels: a bill is a standing amount rather than something that happened on a day.
    @Test("the lines kind carries named bills and no entries")
    func theLinesKind() async throws {
        let (_, screen) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))
        let utilities = try #require(screen.category(id: "utilities"))

        #expect(utilities.kind == .lines)
        #expect(utilities.lines.map(\.name) == ["Electricity", "Water", "Phone / data"])
        #expect(utilities.lines.map(\.icon) == [.bolt, .drop, .signal])
        #expect(utilities.entries.isEmpty)
        // No entry list, so no count — the label is absent rather than "0 entries".
        #expect(utilities.entryCountLabel == nil)
    }

    /// `fixed` — one editable monthly amount, and nothing else.
    @Test("the fixed kind carries one amount, with no entries and no lines")
    func theFixedKind() async throws {
        let (_, screen) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))
        let rent = try #require(screen.category(id: "rent"))

        #expect(rent.kind == .fixed)
        #expect(rent.total.display == "₹3,000")
        #expect(rent.entries.isEmpty)
        #expect(rent.lines.isEmpty)
        #expect(rent.field == nil)
    }

    /// **Additional Income is money in**, and the payload says so structurally rather than by the client
    /// recognising an id. Its display string is already signed, because a client-side `+` would land on the
    /// wrong side of an Arabic figure (ADR-0003).
    @Test("Additional Income is the one incoming category, and its figure arrives signed")
    func additionalIncomeIsMoneyIn() async throws {
        let (_, screen) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        #expect(screen.categories.filter { $0.flow == .incoming }.map(\.id) == ["income"])
        let income = try #require(screen.category(id: "income"))
        #expect(income.total.display == "+₹900")
        #expect(income.entries.first?.amount.display == "+₹900")
        // And it is **not** in the spend total: ₹5,539 is fixed plus variable and nothing else.
        #expect(screen.summary.total.display == "₹5,539")
        #expect(screen.summary.income.display == "₹900")
    }

    /// **The per-category total is read, not computed** (ADR-0020) — asserted by making the payload disagree
    /// with itself. A screen that summed the entries would show ₹440; one that reads the total shows what the
    /// server sent.
    ///
    /// This is the whole of the criterion, and it cannot be tested against a *consistent* payload: a client that
    /// sums and a client that reads look identical there.
    @Test("a category total that disagrees with its own entries is drawn as the total says")
    func theTotalIsReadRatherThanComputed() async throws {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.expensesINR)) as? [String: Any]
        )
        var categories = try #require(payload["categories"] as? [[String: Any]])
        let index = try #require(categories.firstIndex { $0["id"] as? String == "transport" })
        categories[index]["total"] = [
            "minor": 999_900, "currency": "INR", "exponent": 2, "display": "₹9,999",
        ]
        payload["categories"] = categories

        let viewModel = Self.makeViewModel(
            FixtureTransport(stubs: [
                Endpoint.screenExpenses: .response(
                    status: 200,
                    body: try JSONSerialization.data(withJSONObject: payload)
                ),
            ])
        )
        try await viewModel.load()
        let screen = try #require(viewModel.state.value)
        let transport = try #require(screen.category(id: "transport"))

        #expect(transport.total.display == "₹9,999", "the total was recomputed from the entries")
        // The entries are untouched, so the two genuinely disagree and the test is not vacuous.
        #expect(transport.entries.map(\.amount.display) == ["₹120", "₹320"])
    }

    /// An unrecognised `kind` **fails the screen** rather than degrading, because a kind decides which write the
    /// detail page offers and guessing offers the wrong shape of write (ADR-0033).
    @Test("a category kind this build does not know fails the screen")
    func anUnknownKindFailsTheScreen() async throws {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.expensesINR)) as? [String: Any]
        )
        var categories = try #require(payload["categories"] as? [[String: Any]])
        categories[0]["kind"] = "ledger"
        payload["categories"] = categories

        let viewModel = Self.makeViewModel(
            FixtureTransport(stubs: [
                Endpoint.screenExpenses: .response(
                    status: 200,
                    body: try JSONSerialization.data(withJSONObject: payload)
                ),
            ])
        )
        try await viewModel.load()

        #expect(viewModel.state == .failed(.malformedResponse))
    }

    /// A field shape this build does not know reads as **no field**, which is the Groceries case: an amount, and
    /// the category's own name as the label. The opposite choice from `kind`, and for the opposite reason —
    /// nothing about it can file the wrong thing.
    @Test("a field shape this build does not know degrades to no field")
    func anUnknownFieldDegrades() async throws {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.expensesINR)) as? [String: Any]
        )
        var categories = try #require(payload["categories"] as? [[String: Any]])
        let index = try #require(categories.firstIndex { $0["id"] as? String == "transport" })
        categories[index]["field"] = "hovercraft"
        payload["categories"] = categories

        let viewModel = Self.makeViewModel(
            FixtureTransport(stubs: [
                Endpoint.screenExpenses: .response(
                    status: 200,
                    body: try JSONSerialization.data(withJSONObject: payload)
                ),
            ])
        )
        try await viewModel.load()
        let screen = try #require(viewModel.state.value)

        #expect(screen.category(id: "transport")?.field == nil)
    }

    /// A month with nothing logged is **not** `LoadState.empty`: the seven categories are still there, the form
    /// still works, and the summary still says zero. The same narrowing `HomeViewModel.isEmpty` records.
    @Test("a first-run month loads as a screen with seven empty categories")
    func firstRunIsALoadedScreen() async throws {
        let (viewModel, screen) = try await Self.loaded(
            FixtureTransport(stubs: try Self.stubs(.expensesFirstRun))
        )

        #expect(!viewModel.state.isFailed)
        #expect(screen.categories.count == 7)
        #expect(screen.categories.allSatisfy { $0.entries.isEmpty && $0.lines.isEmpty })
        #expect(screen.summary.total.display == "₹0")
    }

    @Test("the over-budget payload carries the verdict rather than a comparison the client makes")
    func theOverBudgetState() async throws {
        let (_, screen) = try await Self.loaded(
            FixtureTransport(stubs: try Self.stubs(.expensesOverBudget))
        )

        #expect(screen.wants.isOver)
        #expect(screen.wants.percentageLabel == "108%")
        // The fill has clamped while the percentage has not, which is why the two are separate fields: a client
        // deriving one from the other would have to pick which.
        #expect(screen.wants.fill == 1)
    }

    // MARK: - Creating an entry

    @Test("a create posts the typed amount in the display currency and re-renders from the response")
    func creatingAnEntry() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.open("transport")
        viewModel.editAmount("120.50")
        viewModel.choose(option: "metro")
        await viewModel.addEntry()

        let post = try await Self.last("POST", to: transport)
        #expect(post.path == Endpoint.expenses)
        // Every `POST` carries one, and this route is the reason the header exists (ADR-0022).
        #expect(post.headers["Idempotency-Key"] != nil)

        let body = try Self.body(of: post)
        #expect(body["categoryId"] as? String == "transport")
        // **The id, not the displayed name**: the server resolves it into whichever language the reader asks for.
        #expect(body["optionId"] as? String == "metro")
        let amount = try #require(body["amount"] as? [String: Any])
        // Stored exactly as authored, in the currency the user typed in — no storage base (§4.1 [FIX]).
        #expect(amount["minor"] as? Int == 12_050)
        #expect(amount["currency"] as? String == "INR")

        // And the screen re-rendered from the response rather than from a patch of its own.
        #expect(viewModel.state.value?.summary.total.display == "₹5,539")
        #expect(viewModel.draft.isEmpty, "the form was not reset after a successful create")
    }

    /// The free-text option sends **both** the option and the words: the option says which kind of thing it was
    /// and the text says what.
    @Test("the free-text option sends the option id and the typed label together")
    func theFreeTextOption() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)
        await viewModel.loadPicklists()

        viewModel.open("other")
        viewModel.editAmount("410")
        viewModel.choose(option: "something-else")
        #expect(viewModel.draft.needsFreeText, "the option that opens a text box did not open one")
        viewModel.editLabel("Physio")
        await viewModel.addEntry()

        let body = try Self.body(of: try await Self.last("POST", to: transport))
        #expect(body["optionId"] as? String == "something-else")
        #expect(body["label"] as? String == "Physio")
    }

    /// **The option that opens free text is flagged by the server, not matched by its English name.** The design
    /// tests `/something else/i`, which stops working the moment the list is translated.
    @Test("the free-text option is recognised by its flag rather than by its name")
    func freeTextIsAFlagNotAName() async throws {
        let picklists = try Fixture.picklists.decode(Picklists.self)

        #expect(picklists.other.count == 20)
        #expect(picklists.transport.count == 22)
        #expect(picklists.other.filter(\.opensFreeText).map(\.id) == ["something-else"])
        #expect(picklists.transport.allSatisfy { !$0.opensFreeText })
    }

    @Test("a create with no amount is refused locally and sends nothing")
    func anEmptyAmountIsRefused() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.open("groceries")
        await viewModel.addEntry()

        #expect(viewModel.draft.failure == .amountMissing)
        #expect(await transport.requestCount(for: Endpoint.expenses) == 0)
    }

    /// A required label left blank is refused, and an **optional** one is not: money arriving without a story is
    /// still money arriving.
    @Test("a required label is refused blank and an optional one is not")
    func labelValidationFollowsTheField() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.open("entertainment")
        viewModel.editAmount("300")
        await viewModel.addEntry()
        #expect(viewModel.draft.failure == .labelMissing)
        #expect(await transport.requestCount(for: Endpoint.expenses) == 0)

        viewModel.open("income")
        viewModel.editAmount("900")
        await viewModel.addEntry()
        #expect(viewModel.draft.failure == nil)
        #expect(await transport.requestCount(for: Endpoint.expenses) == 1)
    }

    @Test("a delete addresses the entry and re-renders from the response")
    func deletingAnEntry() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        await viewModel.deleteEntry(id: "t2")

        let request = try await Self.last("DELETE", to: transport)
        #expect(request.path == Endpoint.expense(id: "t2"))
        #expect(viewModel.state.value != nil)
    }

    /// An id from a payload becomes **one path segment**, so an id carrying a slash cannot address a different
    /// resource. The lesson `ContentResource.forArticle(id:)` recorded, applied to a route.
    @Test("an entry id cannot travel up the path")
    func anEntryIdIsSanitised() {
        #expect(Endpoint.expense(id: "../me") == "/v1/expenses/me")
        #expect(Endpoint.expense(id: "t2") == "/v1/expenses/t2")
    }

    // MARK: - Rent and the bills

    @Test("updating rent replaces one amount and carries no idempotency key")
    func updatingRent() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.beginEditing("rent")
        viewModel.editFixedAmount("3500")
        await viewModel.saveFixedAmount(categoryID: "rent")

        let request = try await Self.last("PUT", to: transport)
        #expect(request.path == Endpoint.fixedCost(categoryID: "rent"))
        // A `PUT` replaces a value, so sending it twice lands where sending it once did (ADR-0022).
        #expect(request.headers["Idempotency-Key"] == nil)

        let body = try Self.body(of: request)
        #expect((body["amount"] as? [String: Any])?["minor"] as? Int == 350_000)
        #expect(!viewModel.isEditing, "edit mode survived a successful save")
    }

    /// **The whole set of bills, in one request.** The design's edit mode renames one, changes two amounts,
    /// deletes a third, and adds a fourth, then commits all of it with one button — so the write replaces the
    /// set rather than issuing four requests of which only the last tells the truth.
    @Test("saving the bills replaces the whole set in one request")
    func savingTheBills() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.beginEditing("utilities")
        // The three that are there, pre-filled from the payload in major units.
        #expect(viewModel.billDrafts.map(\.name) == ["Electricity", "Water", "Phone / data"])
        #expect(viewModel.billDrafts.map(\.amount) == ["340", "48", "141"])

        viewModel.editBill(at: 0, name: "Electricity & cooling")
        viewModel.editBill(at: 1, amount: "52")
        viewModel.removeBill(at: 2)
        viewModel.addBill()
        viewModel.editBill(at: 2, name: "Internet")
        viewModel.editBill(at: 2, amount: "199")

        await viewModel.saveBills(categoryID: "utilities")

        let request = try await Self.last("PUT", to: transport)
        #expect(request.path == Endpoint.billLines(categoryID: "utilities"))

        let lines = try #require(Self.body(of: request)["lines"] as? [[String: Any]])
        #expect(lines.count == 3)
        #expect(lines.map { $0["name"] as? String } == ["Electricity & cooling", "Water", "Internet"])
        // The existing lines keep their ids; the new one has none, which is how the server tells them apart.
        #expect(lines.map { $0["id"] as? String } == ["u1", "u2", nil])
        #expect(lines.map { ($0["amount"] as? [String: Any])?["minor"] as? Int } == [34_000, 5_200, 19_900])
    }

    /// A bill with no name and no amount is dropped rather than saved, which is the design's own `harvest()`
    /// filter: pressing "Add another bill" and then Save must not leave an untitled zero in the list.
    @Test("an empty bill row is dropped rather than saved")
    func anEmptyBillRowIsDropped() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.beginEditing("utilities")
        viewModel.addBill()
        await viewModel.saveBills(categoryID: "utilities")

        let body = try Self.body(of: try await Self.last("PUT", to: transport))
        #expect(try #require(body["lines"] as? [[String: Any]]).count == 3, "the empty row was saved")
    }

    // MARK: - Online only

    /// **A write attempted offline surfaces `LoadState.offline` and stores nothing** (ADR-0019). There is no
    /// queue, no pending badge, and no local copy of the attempt — the user retries when they have a connection.
    @Test("a create with no connection surfaces offline and files nothing")
    func anOfflineCreateStoresNothing() async throws {
        let store = InMemoryContentStore()
        let transport = FixtureTransport(
            sequences: [Endpoint.screenExpenses: [try .ok(.expensesINR)]],
            stubs: [Endpoint.expenses: .notConnected, Endpoint.screenExpenses: .notConnected]
        )
        let viewModel = Self.makeViewModel(transport, store: store)
        try await viewModel.load()

        viewModel.open("groceries")
        viewModel.editAmount("520")
        await viewModel.addEntry()

        // Offline is a supported mode, not a fault.
        #expect(viewModel.state.isOffline)
        #expect(!viewModel.state.isFailed)
        // Exactly one attempt reached the transport, and nothing is queued to try again.
        #expect(await transport.requestCount(for: Endpoint.expenses) == 1)
        // Nothing was written anywhere on the device: the content store is the only store this screen has, and
        // an expense is per-user data that may never be in it (invariant 8).
        #expect(try await store.data(for: .picklists) == nil)

        // **The typing survives**, which is what makes the retry bearable: the draft is the view model's and the
        // state is the screen's, so losing one does not lose the other.
        #expect(viewModel.draft.amount == "520")
    }

    /// And the retry re-sends **the same** `Idempotency-Key`, because it is the same user intent: a write that
    /// reached the server and lost its response must not be filed twice.
    ///
    /// Driven through the whole path the user takes rather than by calling the write twice — offline, the screen's
    /// own reload, then Add again — because that path is the reason the key has to survive at all. What carries it
    /// across is the draft, which lives in the view model and not in the payload the offline state replaced.
    @Test("retrying a create after reloading re-sends the same idempotency key")
    func aRetryKeepsTheKey() async throws {
        let transport = FixtureTransport(
            sequences: [
                Endpoint.screenExpenses: [try .ok(.expensesINR), try .ok(.expensesINR)],
                Endpoint.expenses: [.notConnected, try .ok(.expensesINR)],
            ]
        )
        let viewModel = Self.makeViewModel(transport)
        try await viewModel.load()

        viewModel.open("groceries")
        viewModel.editAmount("520")
        await viewModel.addEntry()
        #expect(viewModel.state.isOffline)

        // The retry `StateView` offers is the screen's own load, and the typing is still in the box afterwards.
        try await viewModel.load()
        #expect(viewModel.draft.amount == "520")
        await viewModel.addEntry()

        let keys = await transport.recordedRequests
            .filter { $0.path == Endpoint.expenses }
            .compactMap { $0.headers["Idempotency-Key"] }
        #expect(keys.count == 2)
        #expect(keys[0] == keys[1], "the retry minted a new key, so the server cannot dedupe it")
    }

    /// A *different* entry gets a different key: one key per intent, not one per session.
    @Test("a second entry mints a new idempotency key")
    func asecondEntryMintsANewKey() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.open("groceries")
        viewModel.editAmount("520")
        await viewModel.addEntry()
        viewModel.editAmount("340")
        await viewModel.addEntry()

        let keys = await transport.recordedRequests
            .filter { $0.path == Endpoint.expenses }
            .compactMap { $0.headers["Idempotency-Key"] }
        #expect(keys.count == 2)
        #expect(keys[0] != keys[1], "two separate entries shared one key, so the second was deduped away")
    }

    /// Nothing in the app can hold a write for later — the whole of ADR-0019, as a scan. The terms it names are
    /// the retired vocabulary from ADR-0004 and ADR-0005.
    @Test("nothing in the app queues a write")
    func thereIsNoWriteQueue() throws {
        try SourceTree.expectAbsent(
            ["PendingWrite", "SwiftData", "ModelContainer", "pendingWrites", "writeQueue", "drain("],
            from: SourceTree.layers,
            includingRoot: true,
            because: "every write needs a connection; there is no queue and no local copy (ADR-0019)"
        )
    }

    // MARK: - MONTH_CLOSED

    /// **A request can cross a rollover boundary in flight** (§4.5). The month it was addressed to has been
    /// archived, archives are immutable, and the client offers to file it into the live month — naming that
    /// month, which it learns by reloading rather than by guessing that the label it holds is still current.
    @Test("a MONTH_CLOSED create offers to re-file into the live month")
    func monthClosedOffersToRefile() async throws {
        let september = FixtureTransport.Outcome.response(
            status: 200,
            body: try Self.rolledOver(.expensesFirstRun, into: "September")
        )
        let transport = FixtureTransport(
            sequences: [
                // The screen as it was, then the screen after the rollover — a new month, and the entries gone.
                Endpoint.screenExpenses: [try .ok(.expensesINR), september],
                Endpoint.expenses: [Self.monthClosed],
            ]
        )
        let viewModel = Self.makeViewModel(transport)
        try await viewModel.load()
        #expect(viewModel.state.value?.monthLabel == "August")

        viewModel.open("groceries")
        viewModel.editAmount("520")
        await viewModel.addEntry()

        // Not a failed screen: the user has something to decide, and the screen behind the offer is the live
        // month, reloaded.
        let offer = try #require(viewModel.refileOffer)
        #expect(!viewModel.state.isFailed)
        #expect(offer.categoryID == "groceries")
        // **The live month, not the one the write was refused from.** The screen was holding "August"; the offer
        // names what the reload found, which is the whole point of reloading before offering (§4.5).
        #expect(offer.monthLabel == "September")
        #expect(viewModel.state.value?.monthLabel == "September")
        // The draft is still there, so accepting the offer files what the user typed rather than an empty form.
        #expect(viewModel.draft.amount == "520")
    }

    @Test("accepting the offer re-sends the write with a new key and clears the offer")
    func acceptingTheRefileOffer() async throws {
        let transport = FixtureTransport(
            sequences: [
                Endpoint.screenExpenses: [
                    try .ok(.expensesINR),
                    .response(status: 200, body: try Self.rolledOver(.expensesFirstRun, into: "September")),
                ],
                Endpoint.expenses: [Self.monthClosed, try .ok(.expensesINR)],
            ]
        )
        let viewModel = Self.makeViewModel(transport)
        try await viewModel.load()

        viewModel.open("groceries")
        viewModel.editAmount("520")
        await viewModel.addEntry()
        try #require(viewModel.refileOffer != nil)

        await viewModel.refile()

        #expect(viewModel.refileOffer == nil)
        #expect(viewModel.draft.isEmpty, "the form was not reset after the re-file landed")

        let keys = await transport.recordedRequests
            .filter { $0.path == Endpoint.expenses }
            .compactMap { $0.headers["Idempotency-Key"] }
        #expect(keys.count == 2)
        // **A new key**, because it is a new intent: the first write was refused, so there is nothing to dedupe
        // against, and filing into a different month is a different decision.
        #expect(keys[0] != keys[1])
    }

    /// **Only a create is offered for re-filing**, because only a create has a body to re-file. Review found this:
    /// every write routed a `MONTH_CLOSED` to the offer while `refile()` only ever re-sent the *create*, so a
    /// deletion refused across a rollover boundary offered "add it to September" and then filed a new expense.
    ///
    /// All three paths are stubbed and each write is asserted in turn, because an *unstubbed* path answers as
    /// offline — which would have let this pass while asserting nothing about the write it names.
    @Test("a MONTH_CLOSED on anything but a create is a failed screen rather than an offer")
    func monthClosedOnAnotherWriteIsAFailure() async throws {
        func viewModel() async throws -> ExpensesViewModel {
            let model = Self.makeViewModel(
                FixtureTransport(
                    sequences: [Endpoint.screenExpenses: [try .ok(.expensesINR)]],
                    stubs: [
                        Endpoint.expense(id: "t2"): Self.monthClosed,
                        Endpoint.fixedCost(categoryID: "rent"): Self.monthClosed,
                        Endpoint.billLines(categoryID: "utilities"): Self.monthClosed,
                    ]
                )
            )
            try await model.load()
            return model
        }

        // The code, with the copy `ErrorCopy` already carries — "That month has closed. Reload to see the current
        // one." — and **no offer**, because there is nothing to re-file: a deletion in a closed month is a deletion
        // of something an archive holds, and archives are immutable with no exceptions (§4.5). A replacement can
        // simply be tried again against the month that is now live, which the failed state's own retry does.
        let deleting = try await viewModel()
        await deleting.deleteEntry(id: "t2")
        #expect(deleting.state == .failed(.monthClosed))
        #expect(deleting.refileOffer == nil)

        let rent = try await viewModel()
        rent.open("rent")
        rent.beginEditing("rent")
        rent.editFixedAmount("3500")
        await rent.saveFixedAmount(categoryID: "rent")
        #expect(rent.state == .failed(.monthClosed))
        #expect(rent.refileOffer == nil)
        // And the rows the user was editing survive, because there is no payload to re-render them from.
        #expect(rent.fixedAmount == "3500")

        let bills = try await viewModel()
        bills.open("utilities")
        bills.beginEditing("utilities")
        await bills.saveBills(categoryID: "utilities")
        #expect(bills.state == .failed(.monthClosed))
        #expect(bills.refileOffer == nil)
        #expect(bills.billDrafts.count == 3)
    }

    /// **A delete does not empty the entry form.** Every write cleared the draft on success until review, so
    /// deleting last week's row wiped a half-typed new one — which the design's own `bindDelete` never does.
    @Test("deleting an entry leaves a half-typed entry alone")
    func aDeleteLeavesTheFormAlone() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.open("transport")
        viewModel.editAmount("250")
        viewModel.choose(option: "taxi")

        await viewModel.deleteEntry(id: "t2")

        #expect(viewModel.draft.amount == "250", "the delete wiped the form")
        #expect(viewModel.draft.optionID == "taxi")
    }

    /// **Arriving at a category leaves edit mode, even the same category twice.** The guard used to sit outside
    /// `open(_:)` and skipped the whole reset when the id had not changed, so Utilities → Edit → back → Utilities
    /// still said **Done** over rows the user had abandoned.
    @Test("re-opening the same category leaves edit mode but keeps the typing")
    func reopeningACategoryLeavesEditMode() async throws {
        let (viewModel, _) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        viewModel.open("utilities")
        viewModel.beginEditing("utilities")
        viewModel.editBill(at: 0, name: "Abandoned")
        #expect(viewModel.isEditing)

        viewModel.open("utilities")

        #expect(!viewModel.isEditing, "edit mode survived leaving and coming back")
        #expect(viewModel.billDrafts.isEmpty, "abandoned bill edits survived")

        // But the entry form is per *category* and outlives a visit, which is what makes the offline retry bearable.
        viewModel.open("groceries")
        viewModel.editAmount("520")
        viewModel.open("groceries")
        #expect(viewModel.draft.amount == "520", "re-opening the same category wiped the typing")
    }

    /// A figure is read with **its own** exponent and sent with the display currency's. Reading one with the other
    /// is the 10× error `TypedAmount` exists to prevent, and the two are only ever the same currency in practice —
    /// which is exactly why picking the wrong one would go unnoticed.
    @Test("edit mode fills its fields from each figure's own exponent")
    func editModeReadsEachFiguresOwnExponent() async throws {
        let (viewModel, _) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        viewModel.beginEditing("rent")
        #expect(viewModel.fixedAmount == "3000")

        viewModel.beginEditing("utilities")
        #expect(viewModel.billDrafts.map(\.amount) == ["340", "48", "141"])
    }

    /// **An id the server did not issue is not sent.** `Endpoint.expense(id:)` reduces an id to what a path segment
    /// may contain, and a *dropped* character leaves a request addressed to a different, perfectly valid resource.
    @Test("a delete for a mangled id sends nothing")
    func aMangledIdIsNotSent() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        await viewModel.deleteEntry(id: "../me")

        #expect(await transport.recordedRequests.filter { $0.method == "DELETE" }.isEmpty)
    }

    @Test("declining the offer clears it and files nothing")
    func decliningTheRefileOffer() async throws {
        let transport = FixtureTransport(
            sequences: [
                Endpoint.screenExpenses: [
                    try .ok(.expensesINR),
                    .response(status: 200, body: try Self.rolledOver(.expensesFirstRun, into: "September")),
                ],
                Endpoint.expenses: [Self.monthClosed],
            ]
        )
        let viewModel = Self.makeViewModel(transport)
        try await viewModel.load()

        viewModel.open("groceries")
        viewModel.editAmount("520")
        await viewModel.addEntry()
        viewModel.dismissRefileOffer()

        #expect(viewModel.refileOffer == nil)
        #expect(await transport.requestCount(for: Endpoint.expenses) == 1)
        // The draft is cleared too: the user said no to filing it, and leaving it in the box would offer the
        // same refusal again on the next tap.
        #expect(viewModel.draft.isEmpty)
    }

    /// Every other definitive refusal is a **failed** screen with a code, exactly as a read's would be. It is
    /// this view model that maps a *write*'s error, and `StateTaxonomyTests` names it for that.
    @Test("any other server refusal is a failed screen carrying its code")
    func anotherRefusalIsAFailure() async throws {
        let transport = FixtureTransport(
            sequences: [Endpoint.screenExpenses: [try .ok(.expensesINR)]],
            stubs: [
                Endpoint.expenses: .response(
                    status: 429,
                    body: Data(#"{"error":{"code":"RATE_LIMITED"}}"#.utf8)
                ),
            ]
        )
        let viewModel = Self.makeViewModel(transport)
        try await viewModel.load()

        viewModel.open("groceries")
        viewModel.editAmount("520")
        await viewModel.addEntry()

        #expect(viewModel.state == .failed(.rateLimited))
        #expect(viewModel.refileOffer == nil)
    }

    // MARK: - The pick lists

    /// The lists are **server-served and cacheable** (ADR-0009): one request the first time and a `304` after,
    /// and the same 42 options for everybody. Never the design's `?demo` auto-fill block, which nothing here
    /// carries.
    @Test("the pick lists are fetched once and cached")
    func picklistsAreCachedContent() async throws {
        let store = InMemoryContentStore()
        let transport = FixtureTransport(stubs: [
            Endpoint.screenExpenses: try .ok(.expensesINR),
            Endpoint.contentPicklists: try .ok(.picklists, etag: "v1"),
        ])
        let viewModel = Self.makeViewModel(transport, store: store)
        try await viewModel.load()

        await viewModel.loadPicklists()
        await viewModel.loadPicklists()

        #expect(viewModel.options(for: .transport).count == 22)
        #expect(viewModel.options(for: .other).count == 20)
        // Once, however many times it is asked for: the pool is held in memory after the first fetch.
        #expect(await transport.requestCount(for: Endpoint.contentPicklists) == 1)
        // And the bytes are on the ETag'd store, so the next launch revalidates rather than downloading.
        #expect(try await store.etag(for: .picklists) == "v1")
    }

    @Test("a pick list that will not load leaves the screen alone")
    func aFailedPicklistLeavesTheScreen() async throws {
        let transport = FixtureTransport(stubs: [
            Endpoint.screenExpenses: try .ok(.expensesINR),
            Endpoint.contentPicklists: .notConnected,
        ])
        let viewModel = Self.makeViewModel(transport)
        try await viewModel.load()

        await viewModel.loadPicklists()

        #expect(viewModel.options(for: .transport).isEmpty)
        #expect(viewModel.state.value != nil, "a failed pick list replaced a screen that had loaded")
        #expect(!viewModel.state.isOffline)
    }

    // MARK: - The wants share

    /// **A percentage crosses and an allowance comes back** — the fifth write, and the one that must not turn into
    /// a second owner of §4.2 (invariant 3, defect D11).
    ///
    /// Asserted on the **bytes on the wire**, because that is the half a value assertion cannot see: a client that
    /// helpfully sent the allowance it had worked out would still set `percent` correctly and still pass a test
    /// written against `WantsShareUpdate`.
    @Test("the chosen share is sent as a percentage, and nothing else is")
    func theShareIsSentAsAPercentage() async throws {
        let transport = FixtureTransport(stubs: [
            Endpoint.screenExpenses: try .ok(.expensesINR),
            Endpoint.wantsShare: try .ok(.expensesINR),
        ])
        let (viewModel, screen) = try await Self.loaded(transport)
        #expect(screen.wants.sharePercent == 30, "the standing fixture no longer carries the plain-rule share")

        await viewModel.setWantsShare(15)

        let write = try #require(
            await transport.recordedRequests.first { $0.path == Endpoint.wantsShare },
            "no request reached the wants-share route"
        )
        #expect(write.method == "PUT", "a replacement of a value is a PUT and carries no idempotency key")
        #expect(write.headers["Idempotency-Key"] == nil)

        let sent = try #require(write.body, "the write went out with no body")
        let body = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(body["percent"] as? Int == 15)
        // The whole body, so an amount smuggled alongside the percentage fails here rather than being reviewed for.
        #expect(body.keys.sorted() == ["percent"], "the body carries more than the chosen share: \(body.keys)")
        #expect(viewModel.notice == .wantsShareUpdated)
    }

    /// Tapping the row that already has a tick beside it costs no round trip — and, more to the point, produces no
    /// toast claiming something changed.
    @Test("choosing the share already in force sends nothing")
    func anUnchangedShareSendsNothing() async throws {
        let transport = FixtureTransport(stubs: [
            Endpoint.screenExpenses: try .ok(.expensesINR),
            Endpoint.wantsShare: try .ok(.expensesINR),
        ])
        let (viewModel, screen) = try await Self.loaded(transport)

        let inForce = try #require(screen.wants.sharePercent)
        await viewModel.setWantsShare(inForce)

        #expect(await transport.requestCount(for: Endpoint.wantsShare) == 0)
        #expect(viewModel.notice == nil)
    }

    /// **A refused share leaves the screen able to say so**, through the same write mapping every other write goes
    /// through — there is no bespoke handling for this one, which is the point of asserting it.
    @Test("a refused share is a failed screen, not a silent no-op")
    func aRefusedShareFails() async throws {
        let transport = FixtureTransport(stubs: [
            Endpoint.screenExpenses: try .ok(.expensesINR),
            Endpoint.wantsShare: .response(
                status: 422,
                body: Data(#"{"error":{"code":"VALIDATION_FAILED","message":"out of range"}}"#.utf8)
            ),
        ])
        let (viewModel, _) = try await Self.loaded(transport)

        await viewModel.setWantsShare(40)

        #expect(viewModel.state.isFailed)
        #expect(viewModel.notice == nil, "a refused write toasted as though it had landed")
    }

    /// A payload from before the setting existed still decodes, and reads as **no choice on offer** rather than as
    /// a default the client invented — which is what the screen's Edit control keys on.
    @Test("a payload with no share decodes, and offers no share")
    func anAbsentShareDecodes() throws {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.expensesINR)) as? [String: Any]
        )
        var wants = try #require(payload["wants"] as? [String: Any])
        wants.removeValue(forKey: "sharePercent")
        payload["wants"] = wants

        let data = try JSONSerialization.data(withJSONObject: payload)
        let screen = try JSONDecoder().decode(ExpensesScreen.self, from: data)

        #expect(screen.wants.sharePercent == nil)
        #expect(screen.wants.allowance.display == "₹19,770", "the rest of the payload stopped decoding")
    }
}
