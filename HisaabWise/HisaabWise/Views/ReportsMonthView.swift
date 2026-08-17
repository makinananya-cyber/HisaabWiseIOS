import SwiftUI

/// Which closed month is being pushed.
///
/// A wrapper rather than a bare `String`, for ``ExpenseCategoryRoute``'s reason: `navigationDestination(for:)`
/// matches on **type**, so a stack that registered `String.self` would answer every future
/// `NavigationLink(value:)` carrying a string, whatever it meant.
struct ReportsMonthRoute: Hashable, Sendable {
    let monthKey: String
}

/// Reports, converted from the design's `reports` document — level two, **one closed month in full**.
///
/// Seven cards over one request (ADR-0020): the month's totals with the sentence that explains them, its own donut,
/// the savings meter, the wants allowance, the four-segment split bar, the accordion of every entry that was
/// logged, and the facts grid. Every figure arrived computed — the design worked all of it out in the browser from
/// a stored `saved` and a re-implemented 50/30/20 engine.
///
/// **This is the screen invariant 7 is about.** An archived month is immutable and carries the FX rate set pinned
/// at close, so a later currency change repaints the figures through *those* rates and never changes the story: a
/// met goal stays met. The client's half of that is that it holds no conversion, no arithmetic, and no threshold —
/// it draws the strings it was given, and `ReportsMonthViewModelTests` asserts the property against the corpus's
/// two reads of this same month.
///
/// **The split bar is where the Product Spec overrules the design** (§4.2 **[FIX]**): the prototype's fourth
/// segment, "left unspent", is identically zero once `saved` is the residual, and the surplus above goal takes its
/// place.
///
/// **The design's month scroller is not converted**, and that is a decision rather than an omission (ADR-0037):
/// the `.scroller` is a second way to reach a month the archive one screen back already lists, and converting it
/// would mean this payload carrying the whole archive's month list beside the month it is about. The back button
/// and the row are the path.
struct ReportsMonthView: BaseView {
    @Environment(ThemeManager.self) private var theme

    /// Held rather than read from `@Environment`, so a test or a preview can construct the screen over a fixture
    /// transport. Made per tap by ``ReportsViewModel/monthViewModel(monthKey:)``.
    let viewModel: ReportsMonthViewModel

    /// **Supplied because `StateCopy.empty` is the one string with no shared default, and nothing routes to it.**
    ///
    /// `isEmpty(_:)` is `false` here — a month with nothing logged is still a report — and a month key that no
    /// longer resolves is a `404`, which `BaseViewModel.load()` maps to `.failed`. So this sentence is the fallback
    /// a screen must name rather than a state it can reach, exactly as `HomeView`'s is: a screen that supplied none
    /// would fall back to copy that says nothing about a month.
    var stateCopy: StateCopy {
        StateCopy(empty: "reports.detail.empty")
    }

    /// **The chrome, and the page is ``ReportsMonthPage``.**
    ///
    /// The split is ADR-0033's finding, which ``ReportsView`` already applies: `ImageRenderer` does not lay out the
    /// content of a `ScrollView`, so a render of the whole screen comes back as an empty ground — and a test
    /// asserting that it rendered passes on it.
    @ViewBuilder
    func loadedContent(_ screen: ReportsMonthScreen) -> some View {
        ScrollView {
            ReportsMonthPage(screen: screen, viewModel: viewModel)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The pushed screen's own title, once the payload has one. The design's `.backbar` is not converted: the
        // stack's own back button is the affordance, which is the call `ArticleView` makes.
        .navigationTitle(Text(verbatim: screen.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Mapping

    /// The payload's categories as the donut's slices. A mapping, not a calculation: every number crosses
    /// unchanged.
    nonisolated static func slices(_ screen: ReportsMonthScreen) -> [HWDonut.Slice] {
        screen.spending.categories.map { category in
            HWDonut.Slice(
                id: category.id,
                name: category.name,
                share: category.share,
                shareLabel: category.shareLabel,
                amount: category.amount.display,
                slot: category.slot
            )
        }
    }

    /// §4.2's three verdicts as the meter's three pill states.
    ///
    /// **A translation, not a second rule** (ADR-0036): the archive names the threshold table's own words and the
    /// meter names the design's pill classes, both arrive computed, and neither screen can threshold anything.
    /// `total`, so a test can hand it every case.
    nonisolated static func meterVerdict(_ verdict: ReportsScreen.Verdict) -> HWSavingsMeter.Verdict {
        switch verdict {
        case .hit: .met
        case .near: .onTrack
        case .miss: .low
        }
    }

    /// The four parts of the month's income as the split bar's segments.
    ///
    /// The **names are the app's** and the figures are the server's, which is the split every verdict and every
    /// caption in this app is drawn with. The `aim` is one catalogue sentence with the server's figure in it, and
    /// it is absent for the surplus — which has no aim of its own.
    nonisolated static func splitSegments(_ split: ReportsMonthScreen.Split) -> [HWSplitBar.Segment] {
        split.segments.map { segment in
            HWSplitBar.Segment(
                portion: portion(segment.portion),
                name: portionName(segment.portion),
                amount: segment.amount.display,
                target: segment.target.map { Text("reports.detail.split.target \($0.display)") },
                width: segment.share
            )
        }
    }

    /// The payload's portion as the design system's. Two enums rather than one shared, for the reason
    /// ``ReportsView/tint(_:)`` gives: a component knows nothing about a screen payload (`LayeringTests`), and the
    /// place the two vocabularies meet should be one function a test can hand every case to.
    nonisolated static func portion(_ portion: ReportsMonthScreen.Portion) -> HWSplitPortion {
        switch portion {
        case .needs: .needs
        case .wants: .wants
        case .saved: .saved
        case .surplus: .surplus
        }
    }

    /// What each part of the split is called. **App copy**: it names a rule (§4.2) rather than reporting anything,
    /// exactly as the summary card's own chip captions do.
    nonisolated static func portionName(_ portion: ReportsMonthScreen.Portion) -> LocalizedStringResource {
        switch portion {
        case .needs: "reports.detail.split.needs"
        case .wants: "reports.detail.split.wants"
        case .saved: "reports.detail.split.saved"
        case .surplus: "reports.detail.split.surplus"
        }
    }

    /// The facts grid: the app's label, the server's figure, and the server's qualifying sentence.
    nonisolated static func facts(_ screen: ReportsMonthScreen) -> [HWFact.Item] {
        screen.facts.map { fact in
            HWFact.Item(
                id: fact.kind.rawValue,
                label: factLabel(fact.kind),
                value: fact.value,
                note: fact.note
            )
        }
    }

    /// The six fact labels. App copy chosen from a structural value, which is the split
    /// `ExpenseCategoryView.label(for:)` draws for the same reason: the payload says *which* fact it is and the
    /// words are the catalogue's.
    nonisolated static func factLabel(_ kind: ReportsMonthScreen.Kind) -> LocalizedStringResource {
        switch kind {
        case .salary: "reports.detail.fact.salary"
        case .goal: "reports.detail.fact.goal"
        case .saved: "reports.detail.fact.saved"
        case .biggestCost: "reports.detail.fact.biggestCost"
        case .needs: "reports.detail.fact.needs"
        case .leftOver: "reports.detail.fact.leftOver"
        }
    }

    /// One accordion group's entries as the row's own.
    ///
    /// **Identified by position**, because an archived entry carries no id — see
    /// ``ReportsMonthScreen/Entry``. The glyph is the group's, as the design draws every entry in a category with
    /// that category's own icon.
    nonisolated static func entries(_ group: ReportsMonthScreen.Group) -> [HWAccordionRow.Entry] {
        group.entries.enumerated().map { index, entry in
            HWAccordionRow.Entry(
                id: index,
                label: entry.label,
                dateLabel: entry.dateLabel,
                amount: entry.amount.display,
                systemImage: ExpensesView.symbol(group.icon)
            )
        }
    }

    /// What an empty panel says. **Two sentences, chosen by the group's flow**: a category with nothing in it and a
    /// month with no extra income are different facts, and the design says so in different words.
    nonisolated static func emptyNote(_ group: ReportsMonthScreen.Group) -> LocalizedStringResource {
        group.flow == .incoming
            ? "reports.detail.entries.noIncome"
            : "reports.detail.entries.none \(group.name)"
    }

    /// What VoiceOver says opening or closing a panel does. Two whole sentences rather than one with a clause,
    /// because a hint describing only one of them would be wrong half the time.
    nonisolated static func accordionHint(isExpanded: Bool) -> LocalizedStringResource {
        isExpanded ? "reports.detail.entries.collapse" : "reports.detail.entries.expand"
    }

    /// `#sum-note-txt` — which of the two sentences explains the month's split.
    ///
    /// **The choice is the engine's flag and the words are the catalogue's** (§4.2, ADR-0011). The adapted sentence
    /// names what needs came to and what came in; both figures are read out of the split, which is a lookup rather
    /// than a calculation (``ReportsMonthScreen/segment(_:)``).
    nonisolated static func note(_ screen: ReportsMonthScreen) -> LocalizedStringResource {
        guard screen.totals.isAdapted, let needs = screen.segment(.needs) else {
            return "reports.detail.note.plain"
        }
        let needsFigure = needs.amount.display
        let income = screen.split.income.display
        return "reports.detail.note.adapted \(needsFigure) \(income)"
    }

    /// `#goal-line` — which of the three sentences the meter's foot line shows.
    ///
    /// The same three-way split `HomeView.footLine(_:)` draws, and the third case is the one the design does not
    /// have: it writes "the whole goal, and `AED 0` over" for a month that landed exactly on its goal, because it
    /// keys on `short > 0` alone. A month that met its goal precisely gets a sentence of its own here — the payload
    /// sends `surplus` only when there was one.
    nonisolated static func meterFoot(_ savings: ReportsMonthScreen.Savings) -> LocalizedStringResource {
        let saved = savings.saved.display
        if let remaining = savings.remaining {
            return "reports.detail.savings.foot.short \(saved) \(remaining.display)"
        }
        if let surplus = savings.surplus {
            return "reports.detail.savings.foot.over \(saved) \(surplus.display)"
        }
        return "reports.detail.savings.foot.exact \(saved)"
    }

    /// `#bud-foot` — the sentence under the allowance bar, chosen by the **server's** over verdict.
    ///
    /// **`nil` where the payload has no figure for the sentence to name**, and that is the honest answer rather
    /// than a defensive one: both sentences are *about* an amount — what was left, or how far past — so
    /// substituting a different figure would print a number that is not the one the words describe. A payload
    /// that says `isOver` and sends no `excess` is server drift; drawing no line beats drawing a wrong one, and
    /// the bar above it still says the state in three ways.
    nonisolated static func wantsFoot(_ wants: ReportsMonthScreen.Wants) -> LocalizedStringResource? {
        if wants.isOver {
            return wants.excess.map { "reports.detail.wants.foot.over \($0.display)" }
        }
        return wants.remaining.map { "reports.detail.wants.foot.within \($0.display)" }
    }

    /// The sentence VoiceOver reads instead of the meter: saved, goal, and the percentage, all server-formatted.
    ///
    /// **A `LocalizedStringResource` rather than the `Text` `HomeView.meterDescription(_:)` returns**, and the reason
    /// is that a test can read one. Two `Text`s built from the same resource and the same arguments are **not**
    /// `==` — the storage is compared, not the sentence — so an assertion that two descriptions differ passes on
    /// any two of them, including two that are identical. Returning the resource means `String(localized:)` can
    /// resolve it and a test can say which figures are in it. The call site wraps it, which is one `Text(…)`.
    nonisolated static func meterDescription(_ screen: ReportsMonthScreen) -> LocalizedStringResource {
        let saved = screen.savings.saved.display
        let goal = screen.savings.goal.display
        let percentage = screen.percentageLabel
        return "reports.detail.savings.meter.accessibilityValue \(saved) \(goal) \(percentage)"
    }

    /// The sentence VoiceOver reads instead of the allowance track, **and the over state said in words** — a bar
    /// that only changed colour is a state a colour-blind reader and a screen-reader user both miss.
    ///
    /// A resource rather than a `Text`, for the reason above.
    nonisolated static func wantsDescription(_ wants: ReportsMonthScreen.Wants) -> LocalizedStringResource {
        let used = wants.used.display
        let allowance = wants.allowance.display
        let percentage = wants.percentageLabel
        return wants.isOver
            ? "reports.detail.wants.accessibilityValue.over \(used) \(allowance) \(percentage)"
            : "reports.detail.wants.accessibilityValue \(used) \(allowance) \(percentage)"
    }
}

/// Everything on one month's report that the reader looks at.
///
/// **Separate from ``ReportsMonthView`` because `ImageRenderer` does not lay out the content of a `ScrollView`** —
/// see the note on `loadedContent`. It takes the screen it draws *and* the view model, because two of its cards
/// are interactive: a slice can be isolated and a panel can be opened, and both are presentation state the view
/// model owns.
struct ReportsMonthPage: View {
    @Environment(ThemeManager.self) private var theme

    let screen: ReportsMonthScreen
    let viewModel: ReportsMonthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HWTopBar(eyebrow: "reports.detail.eyebrow", title: Text(verbatim: screen.title))

            summary

            spendingCard

            savingsCard

            wantsCard

            splitCard

            entriesCard

            factsCard
        }
    }

    // MARK: - The totals

    /// `.summary` — what the month cost, split three ways, over the sentence that explains the split.
    private var summary: some View {
        HWSpendSummary(
            caption: "reports.detail.summary.caption",
            total: screen.totals.spent.display,
            splits: [
                .init("reports.detail.summary.fixed", screen.totals.fixed.display),
                .init("reports.detail.summary.variable", screen.totals.variable.display),
                .init("reports.detail.summary.additionalIncome", screen.totals.additionalIncome.display),
            ]
        ) {
            HWSummaryNote(note: Text(ReportsMonthView.note(screen)))
        }
    }

    // MARK: - The donut

    private var spendingCard: some View {
        // Mapped **once** and handed to both the ring and the key: the same slices drawn two ways, so a second call
        // would be the same mapping run twice per render.
        let slices = ReportsMonthView.slices(screen)

        return HWCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTop("reports.detail.spending.caption", sub: Text(verbatim: screen.spending.categoryCountLabel))

                if slices.isEmpty {
                    nothingLogged
                } else {
                    // The ring, then the key — which the design draws at **every** size, and which is therefore the
                    // screen's rather than something `hwVisualisation` supplies. Above the accessibility threshold
                    // the ring goes and this list is what remains, so there is one list either way.
                    donut(slices)
                    // Isolating a slice is the **ring's** affordance and no longer the key's — see
                    // ``HWCategoryList``. The list still reads `isolated`, so a wedge tapped above is marked here.
                    HWCategoryList(slices: slices, isolated: viewModel.isolated)
                }
            }
        }
    }

    /// The ring, with the share **under** it rather than inside it — see ``shareLine``.
    private func donut(_ slices: [HWDonut.Slice]) -> some View {
        VStack(spacing: 6) {
            HWDonut(
                slices: slices,
                isolated: viewModel.isolated,
                onIsolate: { viewModel.isolate($0) }
            ) {
                centreReadout
            }

            shareLine
        }
        .frame(maxWidth: .infinity)
    }

    /// `.donut-mid` — a caption over a figure. It says either the total or the isolated category, and both arrive
    /// formatted.
    private var centreReadout: some View {
        let category = viewModel.isolatedCategory(in: screen)
        // Pulled out as locals so the accessibility key below is **one literal** — assembling it with `+` is the
        // sentence assembly ADR-0011 forbids, and it also makes the key unreadable to `LocalisationTests`.
        let figure = category?.amount.display ?? screen.totals.spent.display
        let share = category?.shareLabel ?? screen.spending.shareOfIncomeLabel

        return VStack(spacing: 1) {
            (category.map { Text(verbatim: $0.name) } ?? Text("reports.detail.spending.total"))
                .hwLabel()
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: figure)
                .font(.hw(.subheading))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        // Read as one sentence — the caption, the figure, **and the share**, which is drawn below the ring but
        // belongs to the same fact. A *value*, so isolating a slice re-announces the figure rather than the
        // caption (ADR-0012).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.map { Text(verbatim: $0.name) } ?? Text("reports.detail.spending.total"))
        .accessibilityValue(Text("reports.detail.spending.readout.accessibilityValue \(figure) \(share)"))
    }

    /// `.dm-sub` — "82% of income", or one category's "% of spend" while a slice is isolated.
    ///
    /// **Under the ring rather than inside it, which is this screen's one departure from the design's layout**, and
    /// it was found by looking. The design draws this line at 9px inside a 90px hole, where "82% of income" fits;
    /// the app's smallest step is `micro`, and at that size the sentence runs out of the hole and over the ring's
    /// stroke — grey tertiary ink on whichever category colour happens to be behind it. Shrinking it further is
    /// what ADR-0012 forbids, so it moves instead. It is `accessibilityHidden` because the readout above already
    /// reads it as part of one value.
    ///
    /// `HomeView` keeps its own share inside the hole and is right to: "9% of pay" and "54%" both fit.
    private var shareLine: some View {
        let category = viewModel.isolatedCategory(in: screen)

        return Text(verbatim: category?.shareLabel ?? screen.spending.shareOfIncomeLabel)
            .font(.hw(.caption))
            .foregroundStyle(theme.palette.surface.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    /// **A month with nothing logged keeps the ring**, in the empty-track colour with the readout zeroed — the
    /// treatment `HomeView` gives a first-run month, and for the same reason: the card a reader meets here should
    /// be the card they know rather than a different one.
    ///
    /// It is drawn from the **absence of categories** rather than from a flag. Home needs `isFirstRun` to tell a
    /// new account from an empty month; a month that has closed with no categories is a month nothing was logged
    /// in, and there is no second reading of it.
    private var nothingLogged: some View {
        VStack(spacing: 12) {
            HWEmptyRing {
                VStack(spacing: 1) {
                    Text("reports.detail.spending.total")
                        .hwLabel()
                        .fixedSize(horizontal: false, vertical: true)

                    Text(verbatim: screen.totals.spent.display)
                        .font(.hw(.subheading))
                        .foregroundStyle(theme.palette.surface.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("reports.detail.spending.total"))
                .accessibilityValue(Text(verbatim: screen.totals.spent.display))
            }
            .frame(maxWidth: .infinity)

            Text("reports.detail.spending.nothingLogged")
                .font(.hw(.body))
                .foregroundStyle(theme.palette.surface.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    // MARK: - The savings meter

    private var savingsCard: some View {
        HWCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTop("reports.detail.savings.caption", sub: Text(verbatim: screen.savings.shareOfIncomeLabel))

                HWSavingsMeter(
                    position: screen.savings.position,
                    savedLabel: screen.savings.saved.display,
                    zeroLabel: screen.savings.zeroLabel,
                    goalLabel: screen.savings.goal.display,
                    percentageLabel: screen.percentageLabel,
                    verdict: ReportsMonthView.meterVerdict(screen.verdict),
                    // Passed *into* the meter rather than drawn beneath it, so the sentence and the percentage
                    // pill share one row — the design's `.meter-foot`. Home does the same with its own three
                    // sentences; a screen drawing this underneath left the pill on a line of its own.
                    foot: Text(ReportsMonthView.meterFoot(screen.savings)),
                    accessibilityDescription: Text(ReportsMonthView.meterDescription(screen))
                )
            }
        }
    }

    // MARK: - The wants allowance

    private var wantsCard: some View {
        HWCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTop("reports.detail.wants.caption", sub: Text("reports.detail.wants.hint"))

                HWAllowanceBar(
                    amount: screen.wants.used.display,
                    allowance: Text("reports.detail.wants.allowance \(screen.wants.allowance.display)"),
                    percentageLabel: screen.wants.percentageLabel,
                    fill: screen.wants.fill,
                    isOver: screen.wants.isOver,
                    accessibilityDescription: Text(ReportsMonthView.wantsDescription(screen.wants))
                )

                if let foot = ReportsMonthView.wantsFoot(screen.wants) {
                    footLine(foot)
                }
            }
        }
    }

    // MARK: - The split

    private var splitCard: some View {
        HWCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTop(
                    "reports.detail.split.caption",
                    sub: Text("reports.detail.split.sub \(screen.split.income.display)")
                )

                HWSplitBar(
                    segments: ReportsMonthView.splitSegments(screen.split),
                    accessibilityLabel: "reports.detail.split.accessibilityLabel"
                )
            }
        }
    }

    // MARK: - Everything logged

    private var entriesCard: some View {
        HWCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTop("reports.detail.entries.caption", sub: Text("reports.detail.entries.hint"))

                VStack(spacing: 8) {
                    ForEach(screen.groups) { group in
                        HWAccordionRow(
                            name: group.name,
                            summaryLabel: group.summaryLabel,
                            amount: group.total.display,
                            systemImage: ExpensesView.symbol(group.icon),
                            slot: group.slot,
                            isIncoming: group.flow == .incoming,
                            isExpanded: viewModel.isExpanded(group.id),
                            entries: ReportsMonthView.entries(group),
                            emptyNote: ReportsMonthView.emptyNote(group),
                            hint: ReportsMonthView.accordionHint(isExpanded: viewModel.isExpanded(group.id)),
                            onToggle: { viewModel.toggle(group.id) }
                        )
                    }
                }
                // One container for the accordion, so VoiceOver's container gestures move between categories
                // rather than through every entry in the month.
                .accessibilityElement(children: .contain)
            }
        }
    }

    // MARK: - For the record

    private var factsCard: some View {
        HWCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTop("reports.detail.facts.caption", sub: nil)

                HWFactGrid(facts: ReportsMonthView.facts(screen))
            }
        }
    }

    // MARK: - Card chrome

    /// `.mf-l` / `.bud-foot` — the sentence under a bar. One helper because the two are the same line: the
    /// *choice* of sentence is the payload's and the words are the catalogue's, and the treatment is identical.
    private func footLine(_ sentence: LocalizedStringResource) -> some View {
        Text(sentence)
            .font(.hw(.caption))
            .foregroundStyle(theme.palette.surface.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `.card-top` — the caption, and whatever sits beside it.
    ///
    /// A `Text?` rather than Home's `String`, because half of these subtitles are the **server's** ("6
    /// categories", "18% of income saved") and half are the **app's** ("Transport · fun · other"). One slot that
    /// takes either is what keeps the card top one thing rather than two.
    private func cardTop(_ caption: LocalizedStringResource, sub: Text?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(caption)
                .hwEyebrow()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let sub {
                sub
                    .hwLabel()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview("A month — February 2026, the archive's own first bar") {
    NavigationStack { ReportsMonthView(viewModel: .previewFebruary) }.hwTheme()
}

/// The same month through the pinned rate set: every figure converted, the verdict untouched (invariant 7).
#Preview("A month — the same February, read in dirhams") {
    NavigationStack { ReportsMonthView(viewModel: .previewDirhams) }.hwTheme()
}

#Preview("A month — nothing was logged in it") {
    NavigationStack { ReportsMonthView(viewModel: .previewQuiet) }.hwTheme()
}

#Preview("A month — offline") {
    NavigationStack { ReportsMonthView(viewModel: .previewOffline) }.hwTheme()
}

#Preview("A month — the endpoint is not written yet (501)") {
    NavigationStack { ReportsMonthView(viewModel: .previewNotImplemented) }.hwTheme()
}

#Preview("A month — Arabic, right to left") {
    NavigationStack { ReportsMonthView(viewModel: .previewFebruary) }
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

/// Where the donut, the meter, the allowance track, and the split bar all stand aside for their lists
/// (ADR-0012).
#Preview("A month — AX5") {
    NavigationStack { ReportsMonthView(viewModel: .previewFebruary) }
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
