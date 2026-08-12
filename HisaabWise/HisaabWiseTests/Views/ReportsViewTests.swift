import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// The Reports archive: what it maps, what it refuses to work out, and the copy behind every key it renders.
///
/// A whole-screen render is a smoke test here for the reason `CONTEXT.md` records: `ScreenChrome` supplies
/// `.task { load() }`, `load()` writes `.loading` first, and `ImageRenderer` yields to the main actor before it
/// captures — so the pixels are the spinner however loaded the view model was. The claims worth asserting are the
/// **mappings**, which are `static`, `nonisolated`, and total, plus the copy — and the page, which can be
/// photographed because it has no task of its own.
@Suite("ReportsView")
@MainActor
struct ReportsViewTests {
    private static func loaded(_ fixture: Fixture = .reportsINR) async throws -> ReportsScreen {
        let viewModel = ReportsViewModel(
            client: TestBench.client(FixtureTransport(stubs: [Endpoint.screenReports: try .ok(fixture)]))
        )
        try await viewModel.load()
        return try #require(viewModel.state.value)
    }

    // MARK: - The mapping into the design system

    /// The three verdicts, mapped onto the three palette tints — **one each**, which is what makes "the verdict
    /// the server sent is the verdict that is drawn" a property rather than a coincidence of two tables happening
    /// to line up.
    @Test("the three verdicts map onto three distinct tints")
    func theVerdictsMapOneToOne() {
        let tints = ReportsScreen.Verdict.allCases.map(ReportsView.tint)

        #expect(tints.count == 3)
        #expect(Set(tints).count == 3)
        #expect(Set(tints) == Set(HWVerdictTint.allCases))
        // And each one is itself rather than its neighbour, which a set comparison alone would not catch.
        #expect(ReportsView.tint(.hit) == .hit)
        #expect(ReportsView.tint(.near) == .near)
        #expect(ReportsView.tint(.miss) == .miss)
    }

    /// **The hit / near / miss trio, rendered verbatim** — the screen's own acceptance criterion, asserted through
    /// the mapping the chart actually uses rather than through the enum alone.
    ///
    /// Taken from the standing payload, which carries all three: a bar's tint is the payload's verdict at every
    /// position, in the payload's order.
    @Test("every bar is drawn in the verdict the payload sent")
    func everyBarKeepsItsVerdict() async throws {
        let screen = try await Self.loaded()
        let bars = screen.trend.bars.map(ReportsView.bar)

        #expect(bars.map(\.verdict) == [.near, .miss, .hit, .near, .hit, .miss])
        #expect(Set(bars.map(\.verdict)) == Set(HWVerdictTint.allCases), "the trio is not all three")
        for (bar, payload) in zip(bars, screen.trend.bars) {
            #expect(bar.verdict == ReportsView.tint(payload.verdict), "\(payload.monthKey)")
        }
    }

    /// One mapped bar carries everything the chart draws, **and nothing it worked out**: every field traces to the
    /// payload, including the height, the percentage, and the sentence VoiceOver reads.
    ///
    /// **The id is the month key rather than the label**, which is the one decision in this mapping. Two
    /// Februaries in two years share a label, and a chart keyed on the label would collapse them into one
    /// category — the `reports-two-years` payload is in the corpus partly so that this cannot pass by accident.
    @Test("a bar is assembled from the payload, keyed on the month rather than the label")
    func aBarIsAssembledFromThePayload() async throws {
        let screen = try await Self.loaded()
        let payload = try #require(screen.trend.bars.first)

        let bar = ReportsView.bar(payload)

        #expect(bar.id == payload.monthKey)
        #expect(bar.label == payload.label)
        #expect(bar.height == payload.fill)
        #expect(bar.percentageLabel == payload.percentageLabel)
        #expect(bar.accessibilityLabel == payload.accessibilityLabel)
        // The descriptor is a whole sentence rather than the label again — the design puts exactly this in a
        // `title` attribute, which touch never surfaces.
        #expect(bar.accessibilityLabel.contains(payload.percentageLabel))
        #expect(bar.accessibilityLabel != bar.label)
    }

    /// **Every bar carries a descriptor**, which is one of the screen's criteria and the reason the trend is Swift
    /// Charts rather than a hand-rolled row of rectangles (ADR-0016).
    @Test("no bar reaches the chart without a sentence to read", arguments: [
        Fixture.reportsINR, .reportsTwoYears,
    ])
    func everyBarCarriesADescriptor(_ fixture: Fixture) async throws {
        let screen = try await Self.loaded(fixture)

        for bar in screen.trend.bars.map(ReportsView.bar) {
            #expect(!bar.accessibilityLabel.isEmpty, "\(bar.id) has no descriptor")
            #expect(!bar.label.isEmpty, "\(bar.id) has no axis label")
        }
    }

    /// A month's stripes cross unchanged — a mapping, not a calculation.
    @Test("the proportion bar's stripes are the payload's slots and shares")
    func theSegmentsAreThePayloads() async throws {
        let screen = try await Self.loaded()
        let month = try #require(screen.allMonths.first)

        let segments = ReportsView.segments(month)

        #expect(segments.map(\.slot) == month.segments.map(\.slot))
        #expect(segments.map(\.width) == month.segments.map(\.share))
    }

    /// The three hero chips read the payload's own strings, in the order the design draws them.
    @Test("the hero's chips are the summary's three figures")
    func theChipsAreTheSummarys() async throws {
        let summary = try await Self.loaded().summary
        let splits = ReportsView.splits(summary)

        #expect(splits.count == 3)
        #expect(splits.map(\.value) == [
            summary.monthCount.display,
            summary.averageSpend.display,
            summary.totalSaved.display,
        ])
        // The count is drawn from its `display`, not from its `value` — the client has no thousands separator
        // (ADR-0003), so an archive of 1,200 months would read "1200" if this reached for the number.
        #expect(splits.first?.value == summary.monthCount.display)
    }

    /// **The hero's sub-line is one catalogue entry with the server's sentence inside it**, not two strings joined.
    ///
    /// The design writes `'Goal met in ' + hits + ' of ' + total + ' months · dashed line is the goal'`. The count
    /// and its plural are the server's; the explanation is copy; and the separator belongs to the translation
    /// (ADR-0011).
    @Test("the hero subtitle interpolates the server's sentence rather than appending to it")
    func theSubtitleInterpolates() async throws {
        let summary = try await Self.loaded().summary
        let subtitle = ReportsView.subtitle(summary)

        #expect(subtitle.key == "reports.hero.subtitle %@")
        #expect(summary.goalsMetLabel == "Goal met in 2 of 6 months")
        // The resolved sentence carries the server's words — asserted through the resource so a catalogue entry
        // that stopped taking an argument fails here rather than printing "%@" to a reader.
        #expect(String(localized: subtitle).contains(summary.goalsMetLabel))
    }

    // MARK: - Copy

    /// Every key this screen renders has English copy. The app-wide scan in `LocalisationTests` finds them by
    /// reading the source; this names them, so a key deleted from the catalogue fails a suite that says which
    /// screen it belonged to.
    @Test("every key the screen renders has copy behind it")
    func theScreenCopyExists() throws {
        try CatalogueCopy.expectEnglishCopy(forKeys: [
            "reports.eyebrow",
            "reports.title",
            "reports.empty",
            "reports.hero.caption",
            "reports.hero.months",
            "reports.hero.averageSpend",
            "reports.hero.totalSaved",
            "reports.trend.accessibilityLabel",
            // One argument each, so no numbering is needed — there is no order to swap (ADR-0011).
            "reports.hero.subtitle %@",
            "reports.year.saved %@",
            "reports.month.spent %@",
        ])
    }

    /// The empty state is **this screen's own sentence**, not the shared default: an empty archive and an empty
    /// expense list are different facts, which is why `StateCopy.empty` is the one string with no default.
    @Test("the screen supplies its own empty copy")
    func theEmptyCopyIsThisScreens() {
        #expect(ReportsView(viewModel: .previewEmpty).stateCopy.empty.key == "reports.empty")
    }

    // MARK: - It renders

    /// A smoke test: the screen's `body` evaluates with the environment it was given. It captures the spinner (see
    /// the note above), so what it proves is that nothing traps.
    @Test("the screen renders")
    func theScreenRenders() {
        #expect(TestBench.render(ReportsView(viewModel: .previewArchive)) != nil)
    }

    /// The **page** is what can be photographed, and two different archives have to come out as two different
    /// pictures — the technique `SnapshotSuiteTests` uses to prove its empty case is not photographing a spinner.
    ///
    /// **At the height the page asks for**: a `VStack` given less compresses its children rather than overflowing,
    /// and two payloads squashed into 300pt would come back as one picture (`LearnViewTests` records the same
    /// lesson).
    @Test("the page draws a different picture for each archive the corpus carries")
    func thePageDrawsTheArchive() async throws {
        var pictures: [Fixture: Data] = [:]

        for fixture in [Fixture.reportsINR, .reportsTwoYears] {
            let screen = try await Self.loaded(fixture)
            pictures[fixture] = try #require(
                TestBench.render(ReportsArchivePage(screen: screen), height: nil)?.pngData(),
                "\(fixture.rawValue) drew nothing"
            )
        }

        #expect(Set(pictures.values).count == pictures.count, "two archives drew the same picture")
    }

    /// **The month rows are inert until #22 writes the month detail**, which is a decision rather than an
    /// omission: a chevron and a button trait on a row that opens nothing is a promise the app does not keep
    /// (ADR-0036).
    ///
    /// Asserted as the property that will change when the destination arrives — the page's own closure is absent,
    /// and the row it builds therefore has no action. A render with a closure supplied is drawn too, so the shape
    /// #22 needs is exercised now rather than discovered then.
    @Test("the archive page passes no action while there is nowhere to open")
    func theRowsAreInertUntilTheDetailExists() async throws {
        let screen = try await Self.loaded()

        #expect(ReportsArchivePage(screen: screen).onOpenMonth == nil)

        var opened: [String] = []
        let wired = ReportsArchivePage(screen: screen, onOpenMonth: { opened.append($0) })
        #expect(TestBench.render(wired, height: nil) != nil)
        #expect(opened.isEmpty, "rendering a row is not pressing it")
    }
}
