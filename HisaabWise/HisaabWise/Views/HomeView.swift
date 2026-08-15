import SwiftUI

/// Home, converted from the design's `home` document — and **the screen defect D1 lived on**.
///
/// Five cards over one response (ADR-0020): the spending donut with its centre readout and category key, the
/// savings meter, the tip of the day, the streak, and three article teasers. Every figure on it arrived computed.
/// The prototype hardcoded `salary: 8000` here and derived "% of pay" against it; there is no salary on this
/// screen to hardcode, because the readout arrives as a sentence.
///
/// **The first-run month keeps the screen.** The design puts the grey ring and its CTA *inside* the spending card
/// and leaves the savings meter, the tip, the streak, and the articles where they are — a new account still has a
/// goal to see and a lesson to start. So this is not `LoadState.empty`, which would replace all five cards with
/// one sentence; the empty *treatment* is reused in the one card that has nothing in it. Recorded in ADR-0032,
/// because the ticket asked for `StateView`'s `.empty` and this is a deliberate narrowing of it.
struct HomeView: BaseView {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Held rather than read from `@Environment` so that a test can construct the screen over a fixture
    /// transport. The five-tab shell puts one per tab in the environment.
    let viewModel: HomeViewModel

    /// Where **Add Expense** goes — the Expenses tab, which the shell owns the selection of. A closure for the
    /// reason Landing's routes are closures: the destination belongs to whoever owns the navigation, and a screen
    /// that reached for the tab selection would be a screen that could move the user anywhere.
    let onAddExpense: () -> Void

    /// Where **Continue** goes — the Learn tab.
    let onContinueLearning: () -> Void

    init(
        viewModel: HomeViewModel,
        onAddExpense: @escaping () -> Void = {},
        onContinueLearning: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onAddExpense = onAddExpense
        self.onContinueLearning = onContinueLearning
    }

    /// Home overrides only `empty`. Offline, loading, and retry read the same here as anywhere, and twenty
    /// rewordings of "you're offline" is the outcome ADR-0016 exists to prevent.
    ///
    /// It is still supplied even though `isEmpty` is `false`: the server can answer with no screen at all, and a
    /// screen that supplied no empty copy would fall back to a default that says nothing about Home.
    var stateCopy: StateCopy {
        StateCopy(empty: "home.empty")
    }

    @ViewBuilder
    func loadedContent(_ screen: HomeScreen) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                greeting(screen)
                spendingCard(screen)
                savingsCard(screen)
                tipCard(screen)
                duo(screen)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        // One destination, pushed onto the stack the shell wraps this tab in. The teaser carries the id and the
        // title; the body is fetched by the screen it opens (ADR-0020).
        .navigationDestination(for: HomeScreen.ArticleTeaser.self) { teaser in
            ArticleView(viewModel: viewModel.articleViewModel(for: teaser), title: teaser.short)
        }
    }

    // MARK: - The greeting

    /// `.hello` — "Good morning, Ananya" over the date. **Both are the server's** (invariant 6): the prototype
    /// read `new Date().getHours()`, which a device-clock change moves.
    private func greeting(_ screen: HomeScreen) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("home.greeting \(screen.greeting) \(screen.name)")
                .font(.hw(.title))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: screen.dateLabel)
                .font(.hw(.body))
                .foregroundStyle(theme.palette.surface.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Spending

    private func spendingCard(_ screen: HomeScreen) -> some View {
        HWCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTop("home.spending.caption", sub: screen.monthLabel)

                if screen.spending.isFirstRun {
                    firstRun(screen)
                } else {
                    // The ring, then the key — which the design draws at **every** size, and which is therefore
                    // the screen's rather than something `hwVisualisation` supplies. Above the accessibility
                    // threshold the ring goes and this list is what remains, so there is one list either way.
                    donut(screen)
                    HWCategoryList(
                        slices: Self.slices(screen),
                        isolated: viewModel.isolated,
                        onIsolate: { viewModel.isolate($0) }
                    )
                    HWButton("home.spending.addMore", systemImage: "plus", action: onAddExpense)
                }
            }
        }
    }

    private func donut(_ screen: HomeScreen) -> some View {
        HWDonut(
            slices: Self.slices(screen),
            isolated: viewModel.isolated,
            onIsolate: { viewModel.isolate($0) }
        ) {
            centreReadout(screen)
        }
        .frame(maxWidth: .infinity)
    }

    /// `.donut-mid` — a caption, a figure, and a share. It says either the total and its **% of pay** or one
    /// category and its **% of spend**, and both sentences arrive formatted.
    private func centreReadout(_ screen: HomeScreen) -> some View {
        let category = viewModel.isolatedCategory(in: screen)
        // Pulled out as locals so the key below is **one literal**. Assembling it with `+` — which this did
        // until the scan caught it — is the sentence assembly ADR-0011 forbids, and it also makes the key
        // unreadable to `LocalisationTests`, so the copy goes missing silently.
        let figure = category?.amount.display ?? screen.spending.total.display
        let share = category?.shareLabel ?? screen.spending.shareOfPayLabel

        return VStack(spacing: 1) {
            (category.map { Text(verbatim: $0.name) } ?? Text("home.spending.total"))
                .hwLabel()
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: category?.amount.display ?? screen.spending.total.display)
                .font(.hw(.subheading))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)

            // "9% of pay" for the whole ring, "54%" for one slice — the server's strings, either way.
            Text(verbatim: category?.shareLabel ?? screen.spending.shareOfPayLabel)
                .font(.hw(.caption))
                .foregroundStyle(theme.palette.surface.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        // Read as one sentence, and **as a value** so that isolating a slice re-announces the figure rather than
        // the caption (ADR-0012).
        .accessibilityElement(children: .ignore)
        // The **isolated category's** name, not "Total spent": VoiceOver was announcing the caption for the
        // whole ring while the visible caption read "Rent".
        .accessibilityLabel(category.map { Text(verbatim: $0.name) } ?? Text("home.spending.total"))
        .accessibilityValue(Text("home.spending.readout.accessibilityValue \(figure) \(share)"))
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.quick), value: viewModel.isolated)
    }

    /// `#firstrun` — the grey ring's card: a sentence and the one action worth offering.
    ///
    /// The **empty treatment, in one card** rather than `StateView`'s whole-screen state. `StateView`'s own note
    /// says the CTA belonging to an empty screen is that screen's own and arrives with the first screen that has
    /// one; this is that screen, and the CTA is here.
    private func firstRun(_ screen: HomeScreen) -> some View {
        VStack(spacing: 12) {
            // **The real ring, in the empty-track colour**, with the readout zeroed — as the design's
            // `drawEmptyDonut()` draws it. A glyph stood here until review: it made the first day's card a
            // different card from every day after it.
            HWEmptyRing {
                VStack(spacing: 1) {
                    Text("home.spending.total")
                        .hwLabel()
                        .fixedSize(horizontal: false, vertical: true)

                    Text(verbatim: screen.spending.total.display)
                        .font(.hw(.subheading))
                        .foregroundStyle(theme.palette.surface.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("home.spending.nothingYet")
                        .font(.hw(.caption))
                        .foregroundStyle(theme.palette.surface.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("home.spending.total"))
                .accessibilityValue(Text("home.spending.nothingYet"))
            }
            .frame(maxWidth: .infinity)

            Text("home.spending.firstRun")
                .font(.hw(.body))
                .foregroundStyle(theme.palette.surface.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HWButton("home.spending.addFirst", systemImage: "plus", action: onAddExpense)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Savings

    private func savingsCard(_ screen: HomeScreen) -> some View {
        HWCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTop("home.savings.caption", sub: screen.monthLabel)

                HWSavingsMeter(
                    position: screen.savings.position,
                    savedLabel: screen.savings.saved.display,
                    zeroLabel: screen.savings.zeroLabel,
                    goalLabel: screen.savings.goal.display,
                    percentageLabel: screen.savings.percentageLabel,
                    verdict: Self.verdict(screen.savings.verdict),
                    accessibilityDescription: Self.meterDescription(screen.savings)
                )

                // The `.mf-l` sentence, chosen by the **server's** verdict and interpolating the server's figures.
                // Three whole sentences in the catalogue rather than one assembled from a verdict and a number:
                // the prototype built it with string concatenation and `<b>` tags, which no translation can
                // reorder (ADR-0011).
                if let nudge = screen.savings.goalNudge {
                    goalNudgeNote(nudge)
                }

                Text(Self.footLine(screen.savings))
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.surface.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The nudge that appears when a rise in pay has left the savings goal behind.
    ///
    /// **A suggestion with a way to take it, and a way not to.** The goal is the reader's to choose — somebody
    /// deliberately saving less than a fifth of their pay is not making a mistake — so this offers the figure the
    /// app would pick and leaves the decision with them. "Not now" dismisses it for this reading of the screen; the
    /// server will suggest it again next time, because the drift is still there.
    ///
    /// Both amounts are the **server's display strings** (ADR-0003): the client does not format money and has no
    /// formatter to do it with.
    @ViewBuilder
    private func goalNudgeNote(_ nudge: HomeScreen.GoalNudge) -> some View {
        if !viewModel.hasDismissedGoalNudge {
            VStack(alignment: .leading, spacing: 8) {
                Text("home.goalNudge.title")
                    .hwLabel()
                    .fixedSize(horizontal: false, vertical: true)

                Text("home.goalNudge.body \(nudge.suggested.display) \(nudge.current.display)")
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.surface.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    HWButton(
                        "home.goalNudge.action",
                        variant: .soft,
                        systemImage: "arrow.up",
                        state: viewModel.isRaisingGoal ? .inFlight : .ready
                    ) {
                        Task { await viewModel.raiseGoal(to: nudge.suggested) }
                    }

                    HWButton("home.goalNudge.dismiss", variant: .ghost) {
                        viewModel.dismissGoalNudge()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .hwBox(
                fill: theme.palette.surface.backgroundSecondary,
                radius: .medium,
                border: theme.palette.surface.separator
            )
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - The tip

    private func tipCard(_ screen: HomeScreen) -> some View {
        let tip = viewModel.tip(in: screen)

        return HWCard {
            HWTipCard(text: tip.resolvedText) {
                Task { await viewModel.showAnotherTip(after: tip) }
            }
        }
    }

    // MARK: - Streak and reading

    /// `.duo` — the streak card and the reading list. A column rather than the design's two-up grid: at
    /// accessibility sizes two cards side by side leave neither enough width, and the design's own breakpoint
    /// stacks them.
    private func duo(_ screen: HomeScreen) -> some View {
        VStack(spacing: 16) {
            HWStreakCard(
                streak: screen.learning.streak,
                summary: screen.learning.summary,
                nextLesson: screen.learning.nextLesson,
                action: onContinueLearning
            )

            HWCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("home.reads.caption")
                        .hwEyebrow()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(screen.articles) { teaser in
                        // A `NavigationLink` rather than a button plus a path append: the row *is* the
                        // destination, and the shell already wraps this tab in a stack.
                        NavigationLink(value: teaser) {
                            HWReadRowLabel(
                                title: teaser.short,
                                systemImage: Self.symbol(teaser.icon),
                                accent: teaser.accent
                            )
                        }
                        .buttonStyle(HWPressStyle.compact)
                        .accessibilityLabel(Text(verbatim: teaser.short))
                        .accessibilityHint(Text("home.reads.hint"))
                    }
                }
            }
        }
    }

    // MARK: - Card chrome

    /// `.card-top` — the caption and the month beside it.
    private func cardTop(_ caption: LocalizedStringResource, sub: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(caption)
                .hwEyebrow()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: sub)
                .hwLabel()
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Mapping

    /// The payload's categories as the donut's slices. A mapping, not a calculation: every number crosses
    /// unchanged.
    static func slices(_ screen: HomeScreen) -> [HWDonut.Slice] {
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

    /// The payload's verdict as the meter's. Two enums rather than one shared: the meter is a component and knows
    /// nothing about a screen payload (`LayeringTests`), and the payload knows nothing about a pill's colour.
    static func verdict(_ verdict: HomeScreen.Verdict) -> HWSavingsMeter.Verdict {
        switch verdict {
        case .low: .low
        case .onTrack: .onTrack
        case .met: .met
        }
    }

    /// The design's five article glyphs, as SF Symbols.
    ///
    /// `nonisolated` because `LocalisationTests` subtracts these from the localisation keys it finds in the source
    /// — the same trick it uses for `AppTab.systemImage` — and a scan is not on the main actor.
    nonisolated static func symbol(_ icon: HomeScreen.Icon) -> String {
        switch icon {
        case .shield: "checkmark.shield"
        case .globe: "globe"
        case .steps: "stairs"
        case .lightbulb: "lightbulb"
        case .alert: "exclamationmark.triangle"
        }
    }

    /// The sentence VoiceOver reads instead of the bar: saved, goal, and the percentage, all server-formatted.
    ///
    /// A function rather than an expression at the call site, so the key is **one literal** — see the note in
    /// `centreReadout`.
    static func meterDescription(_ savings: HomeScreen.Savings) -> Text {
        let saved = savings.saved.display
        let goal = savings.goal.display
        let percentage = savings.percentageLabel
        return Text("home.savings.meter.accessibilityValue \(saved) \(goal) \(percentage)")
    }

    /// `.mf-l` — which of the three sentences the foot line shows.
    ///
    /// **The choice is the server's verdict and the words are the catalogue's.** That split is the whole of it: a
    /// verdict about money is a calculation (defect D11 computed it two ways), and a sentence is copy.
    static func footLine(_ savings: HomeScreen.Savings) -> LocalizedStringResource {
        switch savings.verdict {
        case .met:
            "home.savings.foot.met \(savings.saved.display)"
        case _ where savings.saved.minor == 0:
            // The design keys this on `saved <= 0` alone rather than on the verdict, and so does this: a month
            // with nothing saved reads the same whatever the server calls it.
            "home.savings.foot.nothing"
        case .low, .onTrack:
            // **`remaining` or nothing.** Substituting the goal for it — which this did until review — tells a
            // user who has passed their goal that they still owe the whole of it, and `Verdict` degrades an
            // unknown value to `onTrack`, so that was reachable from a server change alone.
            savings.remaining.map { "home.savings.foot.remaining \(savings.saved.display) \($0.display)" }
                ?? "home.savings.foot.met \(savings.saved.display)"
        }
    }
}

#if DEBUG
#Preview("Home — a month with spending in it") {
    NavigationStack { HomeView(viewModel: .previewINRSalary) }.hwTheme()
}

#Preview("Home — a brand-new account") {
    NavigationStack { HomeView(viewModel: .previewFirstRun) }.hwTheme()
}

#Preview("Home — offline") {
    NavigationStack { HomeView(viewModel: .previewOffline) }.hwTheme()
}

#Preview("Home — the endpoint is not written yet (501)") {
    NavigationStack { HomeView(viewModel: .previewNotImplemented) }.hwTheme()
}

#Preview("Home — Arabic, right to left") {
    NavigationStack { HomeView(viewModel: .previewINRSalary) }
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

/// Where the two visualisations stand aside for their lists (ADR-0012).
#Preview("Home — AX5") {
    NavigationStack { HomeView(viewModel: .previewINRSalary) }
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
