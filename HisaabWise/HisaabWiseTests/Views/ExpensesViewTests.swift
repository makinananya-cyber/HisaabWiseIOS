import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// The Expenses screen: what it draws, what it refuses to work out, and the copy behind every key it renders.
///
/// A whole-screen render is a smoke test here for the reason `CONTEXT.md` records: `ScreenChrome` supplies
/// `.task { load() }`, `load()` writes `.loading` first, and `ImageRenderer` yields to the main actor before it
/// captures — so the pixels are the spinner however loaded the view model was. The claims worth asserting are
/// therefore the **mappings**, which are `static` and pure, plus the copy.
@Suite("ExpensesView")
@MainActor
struct ExpensesViewTests {
    private static func loaded(_ fixture: Fixture = .expensesINR) async throws -> ExpensesScreen {
        let viewModel = ExpensesViewModel(
            client: TestBench.client(FixtureTransport(stubs: [Endpoint.screenExpenses: try .ok(fixture)])),
            content: ContentLoader(
                client: TestBench.client(FixtureTransport()),
                store: InMemoryContentStore()
            )
        )
        try await viewModel.load()
        return try #require(viewModel.state.value)
    }

    // MARK: - Glyphs

    /// **Every icon the payload can carry has a glyph**, which is what stops a row drawing a hole in itself. A
    /// name the client does not recognise falls back to `tag` in the payload's own decoder, so the mapping only
    /// has to be total over the cases that exist.
    @Test("every category icon maps to a symbol, and no two share a meaning")
    func everyIconHasAGlyph() {
        for icon in ExpensesScreen.Icon.allCases {
            #expect(!ExpensesView.symbol(icon).isEmpty, "\(icon)")
        }
        // `utilities` and `bolt` are deliberately the same drawing — a category and one of its bills — so the
        // count is one short of the case count rather than equal to it. Stated, so a *second* collision has to be
        // added on purpose.
        #expect(Set(ExpensesScreen.Icon.allCases.map(ExpensesView.symbol)).count
            == ExpensesScreen.Icon.allCases.count - 1)
    }

    /// No glyph encodes a direction that would point the wrong way in Arabic. `LocalisationTests` scans the whole
    /// app for the banned names; this asserts it of the *values*, which is the half a scan of the source cannot
    /// see once a name is returned from a `switch`.
    @Test("no glyph on this screen points left or right")
    func noGlyphEncodesDirection() {
        let banned = ["chevron.left", "chevron.right", "arrow.left", "arrow.right"]
        let glyphs = ExpensesScreen.Icon.allCases.map(ExpensesView.symbol)
            + ExpensesScreen.Field.allCases.map(ExpenseCategoryView.glyph)

        for glyph in glyphs {
            #expect(!banned.contains { glyph.hasPrefix($0) }, "\(glyph)")
        }
    }

    // MARK: - The wants bar

    /// **The over state is said in words as well as in colour.** A bar that only changed tint is a state a
    /// colour-blind reader and a screen-reader user both miss, so the two payloads produce two different
    /// sentences.
    @Test("the wants description says whether the budget has been passed")
    func theWantsDescriptionCarriesTheVerdict() async throws {
        let under = try await Self.loaded().wants
        let over = try await Self.loaded(.expensesOverBudget).wants

        #expect(!under.isOver)
        #expect(over.isOver)
        #expect(ExpensesView.wantsDescription(under) != ExpensesView.wantsDescription(over))
    }

    /// Both sentences, and the "of" between the two figures, are catalogue entries with **numbered** arguments —
    /// a language that wants the allowance first has to be able to ask (ADR-0011).
    @Test("the wants copy is in the catalogue and numbers its arguments")
    func theWantsCopyIsPositional() throws {
        try CatalogueCopy.expectEnglishCopy(forKeys: [
            "expenses.wants.amount %@ %@",
            "expenses.wants.accessibilityValue %@ %@ %@",
            "expenses.wants.accessibilityValue.over %@ %@ %@",
        ])
    }

    // MARK: - The toast

    /// Four writes, four sentences, and **the choice is the view model's while the words are the catalogue's** —
    /// the split `HomeView.footLine` draws for the same reason.
    @Test("every notice has its own sentence, and every sentence has copy")
    func everyNoticeHasCopy() throws {
        var keys: [String] = []
        for notice in ExpensesViewModel.Notice.allCases {
            let copy = try #require(ExpensesView.copy(for: notice), "\(notice) has no sentence")
            keys.append(copy.key)
        }

        #expect(Set(keys).count == ExpensesViewModel.Notice.allCases.count, "two notices share a sentence")
        #expect(ExpensesView.copy(for: nil) == nil)
        try CatalogueCopy.expectEnglishCopy(forKeys: keys)
    }

    // MARK: - The four field shapes

    /// Each of the design's four field configurations has a label, a placeholder, and a glyph — and the two
    /// picked ones have a sheet title and a search prompt as well. A shape with no copy is a form with a blank
    /// label above it.
    @Test("every field shape has its own label and placeholder")
    func everyFieldShapeHasCopy() throws {
        var keys: [String] = []
        for field in ExpensesScreen.Field.allCases {
            keys.append(ExpenseCategoryView.label(for: field).key)
            keys.append(ExpenseCategoryView.placeholder(for: field).key)
            #expect(!ExpenseCategoryView.glyph(for: field).isEmpty, "\(field)")
        }
        for picklist in ExpensesScreen.Picklist.allCases {
            keys.append(ExpenseCategoryView.title(for: picklist).key)
            keys.append(ExpenseCategoryView.searchPrompt(for: picklist).key)
        }

        #expect(Set(keys).count == keys.count, "two field shapes share a label")
        try CatalogueCopy.expectEnglishCopy(forKeys: keys)
    }

    /// **The picker's message is only ever its own.** A missing free-text label belongs beside the text box below
    /// the picker, not beside the picker that is filled in — which is the mistake registration made and review
    /// caught, recorded at `RegistrationFailure.field`.
    @Test("the combo shows only the failure that belongs to it")
    func theComboShowsOnlyItsOwnFailure() {
        #expect(ExpenseCategoryView.comboError(.optionMissing) != nil)
        #expect(ExpenseCategoryView.comboError(.labelMissing) == nil)
        #expect(ExpenseCategoryView.comboError(.amountMissing) == nil)
        #expect(ExpenseCategoryView.comboError(nil) == nil)
    }

    /// The two pick lists clear ``HWOptionList``'s twelve-row threshold, so both sheets get a search box — which
    /// is why both need a search prompt above.
    @Test("both pick lists are long enough to want a search box")
    func bothSheetsHaveSearch() throws {
        let picklists = try Fixture.picklists.decode(Picklists.self)

        #expect(picklists.transport.count > HWOptionList.searchThreshold)
        #expect(picklists.other.count > HWOptionList.searchThreshold)
    }

    // MARK: - The wants share

    /// **Every share on offer has its own sentence**, and no two rows share one. Seven whole catalogue entries
    /// rather than one with the number interpolated, because the digits belong to the translation — and because a
    /// key derived as `%@` while SwiftUI looked up `%lld` is how a row comes to read its own key aloud (see
    /// ``WantsShare``).
    @Test("every wants share has its own row copy")
    func everyShareHasCopy() throws {
        var keys: [String] = []
        for share in WantsShare.allCases {
            keys.append(share.label.key)
        }

        #expect(Set(keys).count == WantsShare.allCases.count, "two shares share a row")
        try CatalogueCopy.expectEnglishCopy(forKeys: keys + [
            "expenses.wants.edit",
            "expenses.wants.edit.hint",
            "expenses.wants.edit.title",
            "expenses.wants.edit.explain",
            "expenses.wants.edit.default",
        ])
    }

    /// The bounds come from §4.2 rather than from taste: the rule is 50 needs / 30 wants / 20 savings, and moving
    /// the middle figure moves it at the expense of savings — so the ceiling has to leave a savings share standing,
    /// and the default has to be on the list to be findable again.
    @Test("the shares on offer are ordered, bounded, and include the rule of thumb")
    func theSharesAreBounded() throws {
        let percentages = WantsShare.allCases.map(\.percent)

        #expect(percentages == percentages.sorted(), "the sheet's rows are not in ascending order")
        #expect(Set(percentages).count == percentages.count)
        let lowest = try #require(percentages.first)
        let highest = try #require(percentages.last)
        #expect(lowest >= 10)
        // 40% wants against 50% needs still leaves a tenth to save; 45 would not.
        #expect(highest <= 40)
        #expect(percentages.contains(WantsShare.ruleOfThumb.percent))
        #expect(WantsShare.ruleOfThumb.percent == 30, "the 30 in 50/30/20 moved")
    }

    /// **The Edit budget control is always offered — the payload's share is what the sheet opens *at*, not
    /// whether it opens at all.** `sharePercent` is `nil` while §4.2's adaptive branch is in force, and choosing a
    /// share is how a reader states the split they want when needs have outgrown half of pay, so the control is
    /// shown regardless (``ExpensesPage``). These two fixtures carry a share; the adaptive `nil` case is a corpus
    /// gap the view model suite covers directly (`ExpensesViewModelTests`).
    @Test("the standing and over-budget months both carry a wants share to open the sheet at")
    func theEditControlFollowsThePayload() async throws {
        let standing = try await Self.loaded().wants
        let over = try await Self.loaded(.expensesOverBudget).wants
        #expect(standing.sharePercent != nil)
        #expect(over.sharePercent != nil)
    }

    // MARK: - Figures that count up

    /// **The parked position substitutes digits and moves nothing else.** That is the whole of what makes
    /// ``HWCountingFigure`` compatible with ADR-0003: the symbol, the grouping separators, the decimal mark and
    /// any sign stay exactly where the server put them, and the digit *count* is unchanged — which is what lets
    /// `numericText` pair the glyphs positionally instead of cross-fading two strings of different lengths.
    @Test(
        "the zeroed figure keeps every non-digit and every position",
        arguments: [
            (figure: "₹5,539", zeroed: "₹0,000"),
            (figure: "AED 12,340.50", zeroed: "AED 00,000.00"),
            (figure: "+AED 900", zeroed: "+AED 000"),
            (figure: "¥1,200", zeroed: "¥0,000"),
            (figure: "-₹45", zeroed: "-₹00"),
            // Nothing to count: a figure with no digits in it comes back untouched rather than blank.
            (figure: "—", zeroed: "—"),
        ]
    )
    func theZeroedFigureKeepsItsShape(_ testCase: (figure: String, zeroed: String)) {
        let zeroed = HWCountingFigure.zeroed(testCase.figure)

        #expect(zeroed == testCase.zeroed)
        #expect(zeroed.count == testCase.figure.count, "the parked figure is a different length")
        #expect(
            zeroed.filter { !$0.isWholeNumber } == testCase.figure.filter { !$0.isWholeNumber },
            "a character that is not a digit was changed"
        )
    }

    /// And the property that matters most, over every figure the corpus actually contains: **a counted figure can
    /// never be mistaken for a different amount**. A substitution that dropped a separator or a symbol would turn
    /// `₹5,539` into a plausible-looking wrong number for the length of the roll.
    @Test("no figure in the payload parks as something that reads as a different amount")
    func parkingNeverInventsAFigure() async throws {
        let screen = try await Self.loaded()
        let figures = [
            screen.summary.total.display,
            screen.summary.fixed.display,
            screen.summary.variable.display,
            screen.summary.income.display,
        ] + screen.categories.map(\.total.display)

        for figure in figures {
            let zeroed = HWCountingFigure.zeroed(figure)
            #expect(zeroed != figure || !figure.contains(where: \.isWholeNumber), "\(figure) did not park")
            #expect(!zeroed.contains { $0.isWholeNumber && $0 != "0" }, "\(zeroed) still carries a real digit")
        }
    }

    // MARK: - It renders

    @Test("the screen renders through the real environment in each of its months")
    func theScreenRenders() async throws {
        for viewModel in [
            ExpensesViewModel.previewINR,
            .previewOverBudget,
            .previewFirstRun,
            .previewOffline,
        ] {
            try? await viewModel.load()
            #expect(TestBench.render(ExpensesView(viewModel: viewModel)) != nil)
        }
    }

    /// The detail page in all three kinds. It is not a `BaseView` — there is no second request behind it — so a
    /// render here genuinely draws the page rather than a spinner.
    @Test("the detail page renders in each of the three kinds", arguments: ["transport", "utilities", "rent"])
    func theDetailRenders(_ categoryID: String) async throws {
        let viewModel = ExpensesViewModel.previewINR
        try await viewModel.load()

        let page = ExpenseCategoryView(viewModel: viewModel, categoryID: categoryID)
        #expect(TestBench.render(page) != nil, "\(categoryID)")
    }

    /// A category id the payload does not contain draws nothing rather than a page about nothing.
    @Test("the detail page for an unknown category draws nothing and does not trap")
    func anUnknownCategoryDrawsNothing() async throws {
        let viewModel = ExpensesViewModel.previewINR
        try await viewModel.load()

        #expect(viewModel.category(id: "nonesuch") == nil)
        #expect(TestBench.render(ExpenseCategoryView(viewModel: viewModel, categoryID: "nonesuch")) != nil)
    }

    /// **Doubled copy grows the screen rather than being cut off** — the pseudolanguage property, measured. A
    /// label that came back the same height under twice the text has truncated.
    @Test("the category row grows when its copy doubles")
    func doubledCopyGrows() throws {
        let short = HWCategoryRowLabel(
            name: "Groceries",
            hint: "Add each shop as you go",
            total: "₹860",
            systemImage: "basket"
        )
        let doubled = HWCategoryRowLabel(
            name: "Groceries Groceries",
            hint: "Add each shop as you go Add each shop as you go",
            total: "₹860",
            systemImage: "basket"
        )

        let shortSize = try #require(TestBench.measure(short))
        let doubledSize = try #require(TestBench.measure(doubled))
        #expect(doubledSize.height > shortSize.height, "the row did not grow — the copy was truncated")
    }
}
