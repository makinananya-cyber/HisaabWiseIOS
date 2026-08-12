import SwiftUI

/// Reports, converted from the design's `reports` document — level one, **the archive**.
///
/// The retrospective: which months are closed, what each cost, whether the goal was met, and the trend through
/// all of them against a dashed goal line. One request (ADR-0020), and every figure on the screen arrived
/// computed — the per-year savings totals, the average spend, each bar's height, each percentage, and every
/// verdict.
///
/// **The verdict is the point of this screen and the reason the payload looks the way it does.** Defect D11 is
/// two threshold tables for the same pill over the same number — Reports at 100/70, Home at 80/45 — and the
/// design ships both. Neither is converted. §4.2 keeps one table, server-side, and this screen's half of that is
/// having nothing to threshold: it never sees a `saved`, a `goal`, or a percentage as a number.
///
/// **The month detail is #22.** The design's row is a `<button>` that opens the month in full; until that screen
/// exists the rows are rows — no chevron and no tap — because a control that looks tappable and does nothing is
/// worse than a plain row (``HWMonthRow``). What #22 adds is a closure and a `navigationDestination`, which is
/// the shape `HomeView` already uses for an article.
struct ReportsView: BaseView {
    /// Held rather than read from `@Environment` so that a test can construct the screen over a fixture
    /// transport. The five-tab shell puts one per tab in the environment.
    let viewModel: ReportsViewModel

    /// **The one screen in the app whose empty state is the whole screen.** Home's first run keeps four of its
    /// five cards and puts the empty treatment inside the fifth; an archive with no closed months has no hero
    /// worth drawing — no mean of nothing, and no trend through no points — so `StateView` draws one sentence
    /// (``ReportsViewModel/isEmpty(_:)``).
    var stateCopy: StateCopy {
        StateCopy(empty: "reports.empty")
    }

    /// **The chrome, and the page is ``ReportsArchivePage``.**
    ///
    /// The split is ADR-0033's finding: `ImageRenderer` does not lay out the content of a `ScrollView`, so a
    /// render of the whole screen comes back as an empty ground — and a test asserting that it rendered passes
    /// on it. Everything the reader looks at is therefore in a view a test can photograph.
    @ViewBuilder
    func loadedContent(_ screen: ReportsScreen) -> some View {
        ScrollView {
            ReportsArchivePage(screen: screen)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Mapping

    /// The payload's verdict as the design system's. A mapping, not a calculation: the value crosses unchanged.
    ///
    /// Two enums rather than one shared, for the reason `HomeView` maps `HomeScreen.Savings.Verdict` onto the
    /// meter's: the payload's vocabulary and the palette's are allowed to move apart, and the place they meet
    /// should be one function a test can hand every case to. That the two happen to spell the three the same
    /// way is §4.2's table being the source of both, not a coincidence worth collapsing.
    nonisolated static func tint(_ verdict: ReportsScreen.Verdict) -> HWVerdictTint {
        switch verdict {
        case .hit: .hit
        case .near: .near
        case .miss: .miss
        }
    }

    /// One payload bar as the chart's own value.
    ///
    /// `static` and total, so the whole translation from payload to component is one function a test can call —
    /// and so a `body` does no mapping while it draws.
    nonisolated static func bar(_ bar: ReportsScreen.Bar) -> HWTrendChart.Bar {
        HWTrendChart.Bar(
            id: bar.monthKey,
            label: bar.label,
            height: bar.fill,
            verdict: tint(bar.verdict),
            percentageLabel: bar.percentageLabel,
            accessibilityLabel: bar.accessibilityLabel
        )
    }

    /// One payload month's stripes as the proportion bar's.
    nonisolated static func segments(_ month: ReportsScreen.Month) -> [HWProportionBar.Segment] {
        month.segments.map { HWProportionBar.Segment(slot: $0.slot, width: $0.share) }
    }

    /// The three `.hero-split` chips: a count and two figures, each with the caption that names it.
    ///
    /// The captions are app copy, because they name a rule rather than anything the server stores — the same
    /// split `HWSpendSummary`'s Fixed / Variable / Income chips are built on.
    nonisolated static func splits(_ summary: ReportsScreen.Summary) -> [HWFigureChips.Split] {
        [
            .init("reports.hero.months", summary.monthCount.display),
            .init("reports.hero.averageSpend", summary.averageSpend.display),
            .init("reports.hero.totalSaved", summary.totalSaved.display),
        ]
    }

    /// `#hero-sub` — the server's sentence, inside the app's explanation of the chart.
    ///
    /// **One catalogue entry with the sentence interpolated**, not two strings joined: the design writes
    /// `'Goal met in ' + hits + ' of ' + total + ' months · dashed line is the goal'`, which is a count, a plural,
    /// and an explanation concatenated. The count and the plural are the server's ("six forms in Arabic",
    /// ADR-0011); the explanation is copy, and the separator between them belongs to the translation.
    nonisolated static func subtitle(_ summary: ReportsScreen.Summary) -> LocalizedStringResource {
        "reports.hero.subtitle \(summary.goalsMetLabel)"
    }
}

/// Everything on the Reports archive the reader looks at: the hero with its trend chart, then the years and their
/// months.
///
/// **Separate from ``ReportsView`` because `ImageRenderer` does not lay out the content of a `ScrollView`** — see
/// the note on `loadedContent`. It holds no view model, deliberately: it takes the screen it draws. So it is a
/// *page* rather than a screen, nothing in it can fetch, and a test can render it without a transport.
struct ReportsArchivePage: View {
    // **No `@Environment(ThemeManager.self)`, deliberately.** Every colour on this page belongs to a component,
    // so the page names none — and an unused read of a non-optional observable object is not free: SwiftUI
    // resolves it when the view updates, so the page trapped in a render that had a theme *outside* it rather
    // than reading nothing.
    let screen: ReportsScreen

    /// What opening a month does. `nil` until #22 writes the month detail, which is what leaves the rows inert
    /// rather than promising a screen that is not there (``HWMonthRow``).
    var onOpenMonth: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HWTopBar(eyebrow: "reports.eyebrow", title: Text("reports.title"))

            hero

            ForEach(screen.years) { year in
                self.year(year)
            }
        }
    }

    /// `.hero` — the caption, the sentence, the trend, and the three figures.
    private var hero: some View {
        HWArchiveHero(
            caption: "reports.hero.caption",
            subtitle: Text(ReportsView.subtitle(screen.summary)),
            splits: ReportsView.splits(screen.summary)
        ) {
            HWTrendChart(
                bars: screen.trend.bars.map(ReportsView.bar),
                goalHeight: screen.trend.goalPosition,
                accessibilityLabel: "reports.trend.accessibilityLabel"
            )
        }
    }

    /// `.yr` plus the `.month` rows under it. **The grouping is the payload's**: the design kept a running year
    /// and filtered the whole archive to total each group as it rendered, which is the client both ordering and
    /// summing (ADR-0020).
    private func year(_ year: ReportsScreen.Year) -> some View {
        VStack(spacing: 10) {
            HWYearHeader(
                year: year.label,
                saved: Text("reports.year.saved \(year.totalSaved.display)")
            )

            ForEach(year.months) { month in
                HWMonthRow(
                    name: month.label,
                    // The year beside the month name is the **group's**, read from the header it sits under
                    // rather than repeated in every row's payload.
                    year: year.label,
                    spent: Text("reports.month.spent \(month.spent.display)"),
                    verdict: ReportsView.tint(month.verdict),
                    percentageLabel: month.percentageLabel,
                    segments: ReportsView.segments(month),
                    // **No hint, because there is no action** — the two arrive together with #22, and a hint
                    // saying "opens the month" on an inert row is copy promising a screen that is not there.
                    action: onOpenMonth.map { open in { open(month.monthKey) } }
                )
            }
        }
        // One container per year, so VoiceOver's container gestures move between years rather than through
        // every month in the archive.
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Reports — the design's six closed months") {
    NavigationStack { ReportsView(viewModel: .previewArchive) }.hwTheme()
}

#Preview("Reports — two years, with a total each") {
    NavigationStack { ReportsView(viewModel: .previewTwoYears) }.hwTheme()
}

#Preview("Reports — no month has closed yet") {
    NavigationStack { ReportsView(viewModel: .previewEmpty) }.hwTheme()
}

#Preview("Reports — offline") {
    NavigationStack { ReportsView(viewModel: .previewOffline) }.hwTheme()
}

#Preview("Reports — the endpoint is not written yet (501)") {
    NavigationStack { ReportsView(viewModel: .previewNotImplemented) }.hwTheme()
}

#Preview("Reports — Arabic, right to left") {
    NavigationStack { ReportsView(viewModel: .previewArchive) }
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

/// Where the trend chart stands aside and the same months become rows (ADR-0012).
#Preview("Reports — AX5") {
    NavigationStack { ReportsView(viewModel: .previewArchive) }
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
