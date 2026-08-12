import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// One month's report: what it maps, which sentence it chooses, and the copy behind every key it renders.
///
/// A whole-screen render is a smoke test here for the reason `CONTEXT.md` records: `ScreenChrome` supplies
/// `.task { load() }`, `load()` writes `.loading` first, and `ImageRenderer` yields to the main actor before it
/// captures — so the pixels are the spinner however loaded the view model was. The claims worth asserting are the
/// **mappings**, which are `static`, `nonisolated`, and total, plus the copy — and the page, which can be
/// photographed because it has no task of its own.
@Suite("ReportsMonthView")
@MainActor
struct ReportsMonthViewTests {
    private static func loaded(
        _ fixture: Fixture = .reportsMonthINR,
        monthKey: String = "2026-02"
    ) async throws -> ReportsMonthScreen {
        let viewModel = ReportsMonthViewModel(
            monthKey: monthKey,
            client: TestBench.client(
                FixtureTransport(stubs: [Endpoint.screenReportsMonth(monthKey: monthKey): try .ok(fixture)])
            )
        )
        try await viewModel.load()
        return try #require(viewModel.state.value)
    }

    private static func viewModel(
        _ fixture: Fixture,
        monthKey: String
    ) async throws -> ReportsMonthViewModel {
        let viewModel = ReportsMonthViewModel(
            monthKey: monthKey,
            client: TestBench.client(
                FixtureTransport(stubs: [Endpoint.screenReportsMonth(monthKey: monthKey): try .ok(fixture)])
            )
        )
        try await viewModel.load()
        return viewModel
    }

    // MARK: - The mapping into the design system

    /// §4.2's three verdicts onto the meter's three pill states — **one each**, which is what makes "the verdict the
    /// server sent is the verdict that is drawn" a property rather than a coincidence.
    @Test("the three verdicts map onto the meter's three states")
    func theVerdictsMapOneToOne() {
        let states = ReportsScreen.Verdict.allCases.map(ReportsMonthView.meterVerdict)

        #expect(states.count == 3)
        #expect(Set(states).count == 3)
        #expect(ReportsMonthView.meterVerdict(.hit) == .met)
        #expect(ReportsMonthView.meterVerdict(.near) == .onTrack)
        #expect(ReportsMonthView.meterVerdict(.miss) == .low)
    }

    /// And the four split portions onto the four the component draws, one each.
    @Test("the four portions map onto the four the design system has")
    func thePortionsMapOneToOne() {
        let portions = ReportsMonthScreen.Portion.allCases.map(ReportsMonthView.portion)

        #expect(portions == [.needs, .wants, .saved, .surplus])
        #expect(Set(portions) == Set(HWSplitPortion.allCases))
    }

    /// Each part is named by the app and no two share a key — a grid where two rows read "Needs" is the mistake this
    /// catches.
    @Test("every portion has its own name")
    func everyPortionIsNamedOnce() {
        let keys = ReportsMonthScreen.Portion.allCases.map { ReportsMonthView.portionName($0).key }

        #expect(Set(keys).count == 4)
    }

    /// **The split bar's four segments come out of the payload unchanged**, in the payload's order, with the aim
    /// beside three of them and absent from the surplus.
    @Test("the split bar is assembled from the payload, and only the surplus has no aim")
    func theSplitIsAssembledFromThePayload() async throws {
        let screen = try await Self.loaded()

        let segments = ReportsMonthView.splitSegments(screen.split)

        #expect(segments.count == 4)
        #expect(segments.map(\.portion) == [.needs, .wants, .saved, .surplus])
        #expect(segments.map(\.width) == screen.split.segments.map(\.share))
        #expect(segments.map(\.amount) == screen.split.segments.map { $0.amount.display })
        #expect(segments.filter { $0.target == nil }.map(\.portion) == [.surplus])
    }

    /// The donut's slices cross unchanged — a mapping, not a calculation.
    @Test("the donut's slices are the payload's categories")
    func theSlicesAreThePayloads() async throws {
        let screen = try await Self.loaded()

        let slices = ReportsMonthView.slices(screen)

        #expect(slices.map(\.id) == screen.spending.categories.map(\.id))
        #expect(slices.map(\.share) == screen.spending.categories.map(\.share))
        #expect(slices.map(\.shareLabel) == screen.spending.categories.map(\.shareLabel))
        #expect(slices.map(\.amount) == screen.spending.categories.map { $0.amount.display })
        #expect(slices.map(\.slot) == screen.spending.categories.map(\.slot))
    }

    /// **A month with nothing logged draws no chart at all**, which is the criterion: a `SectorMark` over one
    /// nothing is a chart describing an absence, so the empty ring stands in and the card keeps its shape.
    @Test("a month with nothing logged has no slices to draw")
    func aQuietMonthHasNoSlices() async throws {
        let screen = try await Self.loaded(.reportsMonthQuiet, monthKey: "2025-11")

        #expect(ReportsMonthView.slices(screen).isEmpty)
        // And the figures around it are still there, which is what makes it a report rather than an empty state.
        #expect(!screen.totals.spent.display.isEmpty)
        #expect(ReportsMonthView.splitSegments(screen.split).count == 4)
        #expect(ReportsMonthView.facts(screen).count == screen.facts.count)
    }

    /// The facts grid: the app's label, the payload's figure and note, in the payload's order.
    @Test("the facts grid is the payload's facts, labelled by the app")
    func theFactsAreThePayloads() async throws {
        let screen = try await Self.loaded()

        let facts = ReportsMonthView.facts(screen)

        #expect(facts.count == 6)
        #expect(facts.map(\.id) == screen.facts.map { $0.kind.rawValue })
        #expect(facts.map(\.value) == screen.facts.map(\.value))
        #expect(facts.map(\.note) == screen.facts.map(\.note))
        // Six kinds, six labels, none shared.
        #expect(Set(ReportsMonthScreen.Kind.allCases.map { ReportsMonthView.factLabel($0).key }).count == 6)
    }

    /// One accordion group's entries, **identified by position** because an archived entry carries no id, and drawn
    /// with the category's own glyph.
    @Test("a group's entries are the payload's, in order, with the category's glyph")
    func theEntriesAreThePayloads() async throws {
        let screen = try await Self.loaded()
        let group = try #require(screen.group(id: "groceries"))

        let entries = ReportsMonthView.entries(group)

        #expect(entries.count == 3)
        #expect(entries.map(\.id) == [0, 1, 2])
        #expect(entries.map(\.label) == group.entries.map(\.label))
        #expect(entries.map(\.dateLabel) == group.entries.map(\.dateLabel))
        #expect(entries.map(\.amount) == group.entries.map { $0.amount.display })
        #expect(Set(entries.map(\.systemImage)) == [ExpensesView.symbol(group.icon)])
    }

    /// **Two empty notes, chosen by the group's flow**: a category with nothing in it and a month with no extra
    /// income are different facts, and the design says so in different words.
    @Test("an empty category and an empty income panel say different things")
    func theEmptyNotesDiffer() async throws {
        let screen = try await Self.loaded(.reportsMonthQuiet, monthKey: "2025-11")
        let category = try #require(screen.group(id: "entertainment"))
        let income = try #require(screen.group(id: "income"))

        #expect(income.flow == .incoming)
        #expect(ReportsMonthView.emptyNote(category).key == "reports.detail.entries.none %@")
        #expect(ReportsMonthView.emptyNote(income).key == "reports.detail.entries.noIncome")
        // The category's own name goes into the sentence rather than being lower-cased by the client, which is what
        // the design does and no other language survives.
        #expect(String(localized: ReportsMonthView.emptyNote(category)).contains(category.name))
    }

    /// The hint says what the tap will do, and the two directions are different sentences.
    @Test("the accordion hint reads differently open and closed")
    func theAccordionHintFlips() {
        #expect(ReportsMonthView.accordionHint(isExpanded: false).key == "reports.detail.entries.expand")
        #expect(ReportsMonthView.accordionHint(isExpanded: true).key == "reports.detail.entries.collapse")
    }

    // MARK: - Which sentence

    /// **The `.sum-note` is the engine's flag choosing between two whole sentences**, and the adapted one carries
    /// the two figures it names (§4.2, ADR-0011).
    @Test("the summary note follows the engine's own flag")
    func theNoteFollowsTheEngine() async throws {
        let adapted = try await Self.loaded()
        #expect(adapted.totals.isAdapted)
        #expect(ReportsMonthView.note(adapted).key == "reports.detail.note.adapted %@ %@")
        let sentence = String(localized: ReportsMonthView.note(adapted))
        #expect(sentence.contains(try #require(adapted.segment(.needs)).amount.display))
        #expect(sentence.contains(adapted.split.income.display))

        let plain = try await Self.loaded(.reportsMonthQuiet, monthKey: "2025-11")
        #expect(!plain.totals.isAdapted)
        #expect(ReportsMonthView.note(plain).key == "reports.detail.note.plain")
    }

    /// **Three foot sentences under the meter, and the third is one the design does not have**: a month that landed
    /// exactly on its goal reads "exactly the goal" rather than "and 0 over".
    @Test("the meter's foot line has a sentence for short, over, and exact")
    func theMeterFootHasThreeCases() async throws {
        let short = try await Self.loaded()
        #expect(short.savings.remaining != nil)
        #expect(ReportsMonthView.meterFoot(short.savings).key == "reports.detail.savings.foot.short %@ %@")

        let over = try await Self.loaded(.reportsMonthQuiet, monthKey: "2025-11")
        #expect(over.savings.remaining == nil)
        #expect(over.savings.surplus != nil)
        #expect(ReportsMonthView.meterFoot(over.savings).key == "reports.detail.savings.foot.over %@ %@")

        // Met to the unit: neither a shortfall nor a surplus, which the payload says by sending neither.
        let exact = ReportsMonthScreen.Savings(
            saved: over.savings.goal,
            goal: over.savings.goal,
            zeroLabel: over.savings.zeroLabel,
            position: 1,
            shareOfIncomeLabel: over.savings.shareOfIncomeLabel,
            remaining: nil,
            surplus: nil
        )
        #expect(ReportsMonthView.meterFoot(exact).key == "reports.detail.savings.foot.exact %@")
    }

    /// And two under the allowance bar, chosen by the **server's** over verdict.
    @Test("the allowance foot line follows the server's over verdict")
    func theAllowanceFootFollowsTheVerdict() async throws {
        let within = try await Self.loaded()
        #expect(!within.wants.isOver)
        #expect(ReportsMonthView.wantsFoot(within.wants)?.key == "reports.detail.wants.foot.within %@")

        let over = ReportsMonthScreen.Wants(
            used: within.wants.allowance,
            allowance: within.wants.allowance,
            percentageLabel: "248%",
            fill: 1,
            isOver: true,
            remaining: nil,
            excess: within.wants.used
        )
        #expect(ReportsMonthView.wantsFoot(over)?.key == "reports.detail.wants.foot.over %@")
        // The accessibility sentence changes with it, because a bar that only changed colour is a state a
        // colour-blind reader and a screen-reader user both miss. Asserted on the **key**, so it is the other
        // sentence rather than the same one with other figures in it.
        #expect(ReportsMonthView.wantsDescription(over).key == "reports.detail.wants.accessibilityValue.over %@ %@ %@")
        #expect(
            ReportsMonthView.wantsDescription(within.wants).key
                == "reports.detail.wants.accessibilityValue %@ %@ %@"
        )
        #expect(String(localized: ReportsMonthView.wantsDescription(over)).contains(over.percentageLabel))
    }

    /// **No foot line where the payload has no figure for it to name**, which is the honest answer rather than a
    /// defensive one: both sentences are *about* an amount, so substituting a different figure would print a number
    /// the words do not describe (invariant 10 — the client renders, the server decides).
    @Test("a payload with no figure for the sentence draws no sentence")
    func aMissingFigureDrawsNoFootLine() async throws {
        let wants = try await Self.loaded().wants

        let overWithNothingToName = ReportsMonthScreen.Wants(
            used: wants.used,
            allowance: wants.allowance,
            percentageLabel: wants.percentageLabel,
            fill: 1,
            isOver: true,
            remaining: nil,
            excess: nil
        )
        #expect(ReportsMonthView.wantsFoot(overWithNothingToName) == nil)

        let withinWithNothingToName = ReportsMonthScreen.Wants(
            used: wants.used,
            allowance: wants.allowance,
            percentageLabel: wants.percentageLabel,
            fill: wants.fill,
            isOver: false,
            remaining: nil,
            excess: nil
        )
        #expect(ReportsMonthView.wantsFoot(withinWithNothingToName) == nil)
    }

    /// **The meter's spoken value is this month's own figures**, which is what makes a currency change audible: the
    /// same month in two currencies must not read the same sentence aloud.
    ///
    /// A gradient with a pin on it has nothing a screen reader can do with it, so this sentence is the whole of what
    /// a VoiceOver user gets from the meter (ADR-0012).
    ///
    /// **Asserted on the resolved sentence, not on a `Text`**, which is why the mapping returns a resource: two
    /// `Text`s built from one resource and one set of arguments are not `==` — the storage is compared, not the
    /// words — so a `!=` between two of them passes on any two, including two that are identical.
    @Test("the meter's accessibility value is composed from this month's figures")
    func theMeterDescriptionIsTheMonths() async throws {
        let rupees = try await Self.loaded()
        let dirhams = try await Self.loaded(.reportsMonthAED)

        let spoken = String(localized: ReportsMonthView.meterDescription(rupees))
        #expect(spoken.contains(rupees.savings.saved.display))
        #expect(spoken.contains(rupees.savings.goal.display))
        #expect(spoken.contains(rupees.percentageLabel))

        // The same month read in dirhams says the same thing about different figures.
        let converted = String(localized: ReportsMonthView.meterDescription(dirhams))
        #expect(converted != spoken)
        #expect(converted.contains(dirhams.savings.saved.display))
        #expect(converted.contains(dirhams.percentageLabel), "the verdict's percentage moved with the currency")
    }

    // MARK: - Copy

    /// Every key this screen renders has English copy. The app-wide scan in `LocalisationTests` finds them by
    /// reading the source; this names them, so a key deleted from the catalogue fails a suite that says which screen
    /// it belonged to.
    @Test("every key the screen renders has copy behind it")
    func theScreenCopyExists() throws {
        try CatalogueCopy.expectEnglishCopy(forKeys: [
            "reports.detail.eyebrow",
            "reports.detail.empty",
            "reports.detail.summary.caption",
            "reports.detail.summary.fixed",
            "reports.detail.summary.variable",
            "reports.detail.summary.additionalIncome",
            "reports.detail.note.plain",
            "reports.detail.spending.caption",
            "reports.detail.spending.total",
            "reports.detail.spending.nothingLogged",
            "reports.detail.savings.caption",
            "reports.detail.wants.caption",
            "reports.detail.wants.hint",
            "reports.detail.split.caption",
            "reports.detail.split.accessibilityLabel",
            "reports.detail.split.needs",
            "reports.detail.split.wants",
            "reports.detail.split.saved",
            "reports.detail.split.surplus",
            "reports.detail.entries.caption",
            "reports.detail.entries.hint",
            "reports.detail.entries.expand",
            "reports.detail.entries.collapse",
            "reports.detail.entries.noIncome",
            "reports.detail.facts.caption",
            "reports.detail.fact.salary",
            "reports.detail.fact.goal",
            "reports.detail.fact.saved",
            "reports.detail.fact.biggestCost",
            "reports.detail.fact.needs",
            "reports.detail.fact.leftOver",
            // The archive row's hint, which arrives with the destination it describes (#22).
            "reports.month.hint",
            // The interpolated ones, spelled the way the lookup spells them.
            "reports.detail.note.adapted %@ %@",
            "reports.detail.spending.readout.accessibilityValue %@ %@",
            "reports.detail.savings.meter.accessibilityValue %@ %@ %@",
            "reports.detail.savings.foot.short %@ %@",
            "reports.detail.savings.foot.over %@ %@",
            "reports.detail.savings.foot.exact %@",
            "reports.detail.wants.allowance %@",
            "reports.detail.wants.accessibilityValue %@ %@ %@",
            "reports.detail.wants.accessibilityValue.over %@ %@ %@",
            "reports.detail.wants.foot.within %@",
            "reports.detail.wants.foot.over %@",
            "reports.detail.split.sub %@",
            "reports.detail.split.target %@",
            "reports.detail.entries.none %@",
        ])
    }

    /// The empty state is **this screen's own sentence**: a month whose key no longer resolves is not an empty
    /// archive.
    @Test("the screen supplies its own empty copy")
    func theEmptyCopyIsThisScreens() {
        #expect(ReportsMonthView(viewModel: .previewFebruary).stateCopy.empty.key == "reports.detail.empty")
    }

    // MARK: - It renders

    /// A smoke test: the screen's `body` evaluates with the environment it was given. It captures the spinner (see
    /// the note above), so what it proves is that nothing traps.
    @Test("the screen renders")
    func theScreenRenders() {
        #expect(TestBench.render(ReportsMonthView(viewModel: .previewFebruary)) != nil)
    }

    /// **The page is what can be photographed**, and the three payloads have to come out as three different
    /// pictures — which is also how "an empty month renders without a degenerate chart" is checked: the quiet
    /// month draws, and it does not draw February.
    ///
    /// At the height the page asks for: a `VStack` given less compresses its children rather than overflowing, and
    /// two payloads squashed into 300pt come back as one picture.
    @Test("the page draws a different picture for each month the corpus carries")
    func thePageDrawsEachMonth() async throws {
        var pictures: [Fixture: Data] = [:]

        for (fixture, monthKey) in [
            (Fixture.reportsMonthINR, "2026-02"),
            (.reportsMonthAED, "2026-02"),
            (.reportsMonthQuiet, "2025-11"),
        ] {
            let viewModel = try await Self.viewModel(fixture, monthKey: monthKey)
            let screen = try #require(viewModel.state.value)
            pictures[fixture] = try #require(
                TestBench.render(
                    ReportsMonthPage(screen: screen, viewModel: viewModel),
                    height: nil
                )?.pngData(),
                "\(fixture.rawValue) drew nothing"
            )
        }

        #expect(Set(pictures.values).count == pictures.count, "two months drew the same picture")
    }

    /// The page draws with a panel open and a slice isolated, which is the state a test cannot see from the
    /// mappings: two of its cards read the view model rather than the payload.
    @Test("the page draws with a slice isolated and a panel open")
    func thePageDrawsItsPresentationState() async throws {
        let viewModel = try await Self.viewModel(.reportsMonthINR, monthKey: "2026-02")
        let screen = try #require(viewModel.state.value)
        let closed = try #require(
            TestBench.render(ReportsMonthPage(screen: screen, viewModel: viewModel), height: nil)?.pngData()
        )

        viewModel.isolate("rent")
        viewModel.toggle("groceries")
        let open = try #require(
            TestBench.render(ReportsMonthPage(screen: screen, viewModel: viewModel), height: nil)?.pngData()
        )

        #expect(closed != open, "isolating a slice and opening a panel changed nothing on the page")
    }
}
