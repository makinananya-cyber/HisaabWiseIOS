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
