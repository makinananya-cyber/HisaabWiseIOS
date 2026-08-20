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

    /// Read for the two places this screen lays out **two things side by side**: the ring and its key, and the
    /// streak panel and the reading list. The design pairs both and stacks them at its own narrow breakpoint;
    /// above the accessibility sizes neither half has the width to be worth reading, so the same thing happens
    /// here. Not a clamp — nothing on this screen caps how large text may get (ADR-0012).
    @Environment(\.dynamicTypeSize) private var typeSize

    /// How wide the `.duo` row turned out to be, so its two columns can take the design's ratio. See ``duo(_:)``.
    @State private var duoWidth: CGFloat = 0

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

    /// Whether the two paired layouts on this screen have to stack. See ``typeSize``.
    private var stacksPairs: Bool { typeSize.isAccessibilitySize }

    @ViewBuilder
    func loadedContent(_ screen: HomeScreen) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                greeting(screen)
                spendingCard(screen)
                savingsCard(screen)
                // **Not inside an `HWCard`.** The tip draws its own warm surface (see ``HWTipCard``); wrapping it
                // put the one coloured card on Home inside a white one.
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
            // The glyph and the accent travel with the teaser, so the article opens in the colour the row it was
            // tapped on was drawn in. Without them every article opened in the same default tint, and three
            // differently-coloured rows led to three identical screens.
            ArticleView(
                viewModel: viewModel.articleViewModel(for: teaser),
                title: teaser.short,
                systemImage: Self.symbol(teaser.icon),
                accent: teaser.accent
            )
            .hwHidesTabBar()
        }
    }

    // MARK: - The greeting

    /// `.hello` — "Good morning, Ananya" over the date. **Both are the server's** (invariant 6): the prototype
    /// read `new Date().getHours()`, which a device-clock change moves.
    private func greeting(_ screen: HomeScreen) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // `.hello-h span{color:var(--planetary)}` — **the name is a lighter blue than the greeting**, which is
            // the one piece of colour on this line and the whole reason it reads as addressed to somebody rather
            // than printed at them.
            Text(Self.tintedGreeting(screen, accent: theme.palette.accent.base))
                .font(.hw(.title))
                .foregroundStyle(theme.palette.surface.ink)
                // Pin the paragraph to the layout direction's leading edge. Without this, a `Text` aligns to
                // its *content's* natural direction, so a greeting whose words are still Latin (an untranslated
                // language, or the user's Latin-script name) stayed left-aligned under RTL while the rest of the
                // screen mirrored. `.leading` resolves against `\.layoutDirection`, so it is the right edge in
                // Arabic and the left edge otherwise.
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: screen.dateLabel)
                .font(.hw(.body))
                .foregroundStyle(theme.palette.surface.inkTertiary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The greeting sentence with the **name** in the accent, and the rest in ink.
    ///
    /// **One `Text`, tinted after resolution — not two `Text`s joined.** "Good evening, Ananya" is a sentence whose
    /// word order a translation may change, and `Text(greeting) + Text(name)` pins the name to the end, which is
    /// exactly the assembly ADR-0011 forbids. So the catalogue resolves the whole line with both arguments in its
    /// own order, and only then is the range the name occupies given a colour.
    ///
    /// Locating it by `range(of:)` is safe because the client passed the string in: it is looking for a value it
    /// supplied, not parsing prose. A name that cannot be found — a translation that transliterated it, a name that
    /// is empty — leaves the line entirely in ink, which is the greeting without its flourish rather than a wrong
    /// one. `static` and pure so that is a rule a test can hand every case to.
    static func tintedGreeting(_ screen: HomeScreen, accent: Color) -> AttributedString {
        var line = AttributedString(String(localized: "home.greeting \(screen.greeting) \(screen.name)"))
        guard !screen.name.isEmpty, let range = line.range(of: screen.name) else { return line }
        line[range].foregroundColor = accent
        return line
    }

    // MARK: - Spending

    private func spendingCard(_ screen: HomeScreen) -> some View {
        HWCard {
            VStack(alignment: .leading, spacing: 16) {
                cardTop("home.spending.caption", sub: screen.monthLabel)

                if screen.spending.isFirstRun {
                    firstRun(screen)
                } else {
                    // **The design's `.spend` row: the ring on the leading side, the key beside it.** This was a
                    // column — ring, then key, then button, each full width — which made the card twice as tall as
                    // the design's and left a 132pt ring centred in 320pt of white. The key is drawn at every
                    // size, which is why it is the screen's rather than something `hwVisualisation` supplies:
                    // above the accessibility threshold the ring is gone and this same list is what remains.
                    spendingSplit(screen)

                    // `.add-below` — **under** the ring and the key, so it is the last thing the eye reaches on
                    // the card rather than the thing between the figures and their labels.
                    HWButton("home.spending.addMore", systemImage: "plus", action: onAddExpense)
                }
            }
        }
    }

    /// The ring and its key, side by side or stacked. See ``stacksPairs``.
    @ViewBuilder
    private func spendingSplit(_ screen: HomeScreen) -> some View {
        let key = HWCategoryList(slices: Self.slices(screen), isolated: viewModel.isolated)

        if stacksPairs {
            // The ring has already stood aside for the list at these sizes (`HWDonut` returns nothing), so this
            // is the key on its own and there is no row left to make.
            key
        } else {
            HStack(alignment: .center, spacing: 14) {
                donut(screen)
                key.frame(maxWidth: .infinity, alignment: .leading)
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
                    // The `.mf-l` sentence, chosen by the **server's** verdict and interpolating the server's
                    // figures. Three whole sentences in the catalogue rather than one assembled from a verdict and
                    // a number: the prototype built it with string concatenation and `<b>` tags, which no
                    // translation can reorder (ADR-0011). It is passed *into* the meter because the design puts it
                    // on the same row as the percentage pill.
                    foot: Text(Self.footLine(screen.savings)),
                    accessibilityDescription: Self.meterDescription(screen.savings)
                )

                if let nudge = screen.savings.goalNudge {
                    goalNudgeNote(nudge)
                }
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

        // No `HWCard` around it: `HWTipCard` **is** a card, and the design's is the warm one (see its own note).
        return HWTipCard(text: tip.resolvedText) {
            Task { await viewModel.showAnotherTip(after: tip) }
        }
    }

    // MARK: - Streak and reading

    /// `.duo` — the streak panel on the leading side and the reading list beside it, at the design's
    /// `1fr 1.15fr` ratio.
    ///
    /// **A row, which it was not.** This drew as a column on the grounds that "at accessibility sizes two cards
    /// side by side leave neither enough width" — true, and an argument for stacking *at those sizes*, which is
    /// what ``stacksPairs`` now does. Stacking at every size gave up the design's whole bottom third: the two
    /// halves say different kinds of thing — one lesson to continue, three things to read — and side by side is
    /// what makes that legible as a choice rather than as a list.
    @ViewBuilder
    private func duo(_ screen: HomeScreen) -> some View {
        let streak = HWStreakCard(
            streak: screen.learning.streak,
            summary: screen.learning.summary,
            nextLesson: screen.learning.nextLesson,
            action: onContinueLearning
        )

        if stacksPairs {
            VStack(spacing: 14) {
                streak
                reads(screen)
            }
        } else {
            HStack(alignment: .top, spacing: Self.duoSpacing) {
                streak.frame(width: streakColumn)
                reads(screen).frame(maxWidth: .infinity)
            }
            // **`grid-template-columns:1fr 1.15fr`, measured rather than approximated.** Equal halves were the
            // first attempt and they cost the reading list a word: at 171pt the row hyphenated "Remittances" in
            // the middle. `onGeometryChange` rather than a `GeometryReader` — the reader would collapse this
            // row's height inside the screen's `VStack` and have to be undone with a fixed one, which is the
            // trade that made equal columns look like the cheaper option.
            //
            // **Measured once, and that guard is load-bearing.** `streakColumn` is derived from `duoWidth` and
            // applied back to a column *inside this same row*, so writing every measurement made a geometry
            // feedback loop: the column resizes, the row's measured width shifts, `duoWidth` updates, the column
            // resizes again — `body` re-evaluates without end. It spun so tightly that SwiftUI never committed
            // the loaded frame, so Home sat on its spinner forever with the network request already answered.
            // The row's width is the viewport's and does not change under us, so the first reading is the only
            // one needed; ignoring the rest is what closes the loop.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                if duoWidth == 0 { duoWidth = newWidth }
            }
        }
    }

    /// `.duo{gap:12px}`
    private static let duoSpacing: CGFloat = 12

    /// The streak column's share of the row.
    ///
    /// **`1 : 1.3`, where the design writes `1fr 1.15fr`** — and the extra tenth is the type scale's doing rather
    /// than a preference. The design sets `.read-t` at 11.5px; these titles are at the `body` step, which is 15pt
    /// (see `HWTextStyle`), and at the design's own ratio the word "Remittances" does not fit on one line of the
    /// narrower column and gets hyphenated mid-word. The streak card has room to give: it holds one number and two
    /// short lines. Bigger text was the change asked for, so the column that carries text is the one that grows.
    private static let streakShare = 1.0 / 2.3

    /// The streak column's width, or `nil` before the row has been measured — on the first pass the two cards take
    /// their natural widths, which is one frame nobody sees.
    private var streakColumn: CGFloat? {
        guard duoWidth > 0 else { return nil }
        return (duoWidth - Self.duoSpacing) * Self.streakShare
    }

    /// `.reads` — the "Read more about" card and its three rows.
    ///
    /// **Its own box rather than an ``HWCard``**, for one number: `HWCard` carries `.card{padding:18px 16px}` and
    /// the design gives this one `.reads{padding:14px 12px 12px}`. Eight points of horizontal padding is a word on
    /// a title in a column this narrow, and the design tightened it here for exactly that reason.
    private func reads(_ screen: HomeScreen) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("home.reads.caption")
                .hwEyebrow()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .hwBox(
            fill: theme.palette.surface.raised,
            radius: .extraLarge,
            border: theme.palette.surface.separator,
            elevation: .small
        )
        // One card, read as a card — the same thing `HWCard` does for the two above it.
        .accessibilityElement(children: .contain)
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
