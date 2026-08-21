import SwiftUI

/// The shares of pay the wants budget may be taken from — **10% to 40% in fives**.
///
/// **A closed vocabulary rather than a range**, and the bounds come from §4.2 rather than from taste. The rule is
/// 50 needs / 30 wants / 20 savings, and moving the middle figure moves it at the expense of savings — so the
/// ceiling is what leaves a savings share standing at all (40% wants against 50% needs still leaves a tenth), and
/// the floor is low enough for a reader remitting most of their pay home to say so. Fives, because the reader is
/// choosing a policy for their month rather than tuning a number.
///
/// **An enum rather than `[10, 15, …]`, because of the copy.** A row reading `"…option \(percent)"` would put the
/// client in the business of rendering a number into a sentence, and it would derive the catalogue key `%@` in the
/// localisation scan while SwiftUI looked up `%lld` — one of those keys orphaned and the other missing, which is
/// how a row comes to read its own key aloud. Seven whole sentences in the catalogue instead: the digits belong to
/// the translation, exactly as they do for every other closed vocabulary in the app (``ExpensesScreen/Field``),
/// and ``label`` is total over the cases so a share cannot exist without words.
///
/// **The server enforces the same bounds.** What is listed here is what the reader can tap, not what the rule is;
/// a share outside it comes back as a refused write like any other bad body.
enum WantsShare: Int, Sendable, Hashable, CaseIterable, Identifiable {
    case tenth = 10
    case fifteen = 15
    case fifth = 20
    case quarter = 25
    /// The 30 in 50/30/20 — marked on its row, so a reader who has moved the share can find the way back.
    case ruleOfThumb = 30
    case thirtyFive = 35
    case twoFifths = 40

    var id: Int { rawValue }

    /// Whole percent, which is what crosses the wire (``WantsShareUpdate``).
    var percent: Int { rawValue }

    /// `.opt-name` — the row's sentence. App copy: it names a rule, not anything the server stores.
    var label: LocalizedStringResource {
        switch self {
        case .tenth: "expenses.wants.edit.option.10"
        case .fifteen: "expenses.wants.edit.option.15"
        case .fifth: "expenses.wants.edit.option.20"
        case .quarter: "expenses.wants.edit.option.25"
        case .ruleOfThumb: "expenses.wants.edit.option.30"
        case .thirtyFive: "expenses.wants.edit.option.35"
        case .twoFifths: "expenses.wants.edit.option.40"
        }
    }
}

/// Which category's detail page is being pushed.
///
/// A wrapper rather than a bare `String`, because `navigationDestination(for:)` matches on **type**: a stack that
/// registered `String.self` would answer every future `NavigationLink(value:)` carrying a string, whatever it
/// meant. One type per destination is what keeps that unambiguous as the app grows.
struct ExpenseCategoryRoute: Hashable, Sendable {
    let id: String
}

/// Expenses, converted from the design's `expenses` document — **the core loop, and the only screen that writes**.
///
/// Two levels over one response (ADR-0020): the monthly summary with its wants bar and the seven category rows,
/// and behind each row a detail page drawing whichever of the three structural kinds that category is. Every
/// figure arrived computed — the totals, the split, the wants percentage, and each entry's date label — so there
/// is nothing on this screen the client added up.
///
/// **The kinds are the interesting part.** `log` appends deletable entries; `lines` holds a set of named monthly
/// bills edited and saved together; `fixed` holds one editable amount. Which one a category is decides which
/// write the page offers, and that is why the payload's `kind` refuses to be guessed at (``ExpensesScreen/Kind``).
///
/// **A month with nothing logged keeps the screen.** The design puts "Nothing logged yet this month" *inside* the
/// category that is empty, and the summary, the bar, and the other six rows stay where they are — so this is not
/// `LoadState.empty`, which would replace all of it with one sentence. The same narrowing `HomeView` records for
/// its first-run donut, and the reason ``HWEmptyNote`` exists.
struct ExpensesView: BaseView {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Held rather than read from `@Environment`, so a test or a preview can construct the screen over a fixture
    /// transport. The five-tab shell puts one per tab in the environment.
    let viewModel: ExpensesViewModel

    /// Whether the wants-share sheet is open. The screen's, not the view model's: which sheet is on screen is
    /// presentation with no bearing on a write, exactly as ``ExpenseCategoryView``'s `picker` is.
    @State private var isEditingWantsShare = false

    /// Overridden because the server can answer with no screen at all, and a screen that supplied no empty copy
    /// would fall back to a default that says nothing about Expenses. `isEmpty` is `false` — see the note above.
    var stateCopy: StateCopy {
        StateCopy(empty: "expenses.empty")
    }

    /// **The scroll, the sheet, the destination, the toast, and the alert** — and the content is
    /// ``ExpensesPage``.
    ///
    /// Split at the scroll for the reason ``ExpenseCategoryView`` records for its own split, which was found by
    /// looking rather than designed: an `ImageRenderer` does not lay out the content of a `ScrollView`, so a render
    /// of this whole screen comes back as an empty ground — and "the screen renders" passes on it. With the content
    /// in a view of its own, a test can render the three bands and see them.
    @ViewBuilder
    func loadedContent(_ screen: ExpensesScreen) -> some View {
        ScrollView {
            ExpensesPage(viewModel: viewModel, screen: screen, isEditingWantsShare: $isEditingWantsShare)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The wants-share sheet, presented from the top bar's Edit control. `HWSheetChrome` supplies the panel,
        // so what this screen owns is the rows and the sentence above them.
        .sheet(isPresented: $isEditingWantsShare) {
            wantsShareSheet(screen)
        }
        // One destination, pushed onto the stack the shell wraps this tab in. It carries the **id** and the page
        // re-reads the category from the view model, so a write that returns a new payload re-renders the page
        // that is open rather than leaving it showing what it was pushed with.
        .navigationDestination(for: ExpenseCategoryRoute.self) { route in
            ExpenseCategoryView(viewModel: viewModel, categoryID: route.id)
                .hwHidesTabBar()
        }
        .hwToast(Self.copy(for: viewModel.notice), isPresented: viewModel.notice != nil)
        // The toast's lifetime is the screen's, not the component's (``HWToast``): it confirms something the user
        // just did, so it goes after a moment rather than waiting to be dismissed.
        .task(id: viewModel.notice) {
            guard viewModel.notice != nil else { return }
            try? await Task.sleep(for: .seconds(2.4))
            viewModel.dismissNotice()
        }
        // The offer to file a refused write into the live month (§4.5). A system dialog rather than the design's
        // own modal, for the reason `LogoutControl` gives: the platform's semantics, an alert to VoiceOver, and
        // no accidental dismissal of a decision about the user's money.
        .alert(
            Text("expenses.refile.title"),
            isPresented: Binding(
                get: { viewModel.refileOffer != nil },
                set: { if !$0 { viewModel.dismissRefileOffer() } }
            ),
            presenting: viewModel.refileOffer
        ) { offer in
            Button {
                Task { await viewModel.refile() }
            } label: {
                Text("expenses.refile.confirm \(offer.monthLabel)")
            }

            Button(role: .cancel) {
                viewModel.dismissRefileOffer()
            } label: {
                Text("expenses.refile.cancel")
            }
        } message: { offer in
            // **The live month, named.** The label comes from the payload reloaded *after* the refusal, so the
            // offer says where the entry would actually go rather than where the user thought it was going.
            Text("expenses.refile.message \(offer.monthLabel)")
        }
    }

    /// The sheet behind **Edit** — one row per share the reader may choose, with a tick on the one in force.
    ///
    /// **Rows rather than a slider**, and the design's own vocabulary rather than a new one: `HWSheetChrome`,
    /// `HWSheetList`, and `HWSheetRow` are what every other choice in the app is made from — a currency, a
    /// country, a mode of transport — so this reads as the same kind of decision. A slider would also invite a
    /// figure to be shown against each position, and the only figure worth showing is the resulting allowance,
    /// which the engine computes and the client may not (invariant 3): the honest sequence is choose, send, and
    /// read the allowance the server sends back.
    private func wantsShareSheet(_ screen: ExpensesScreen) -> some View {
        HWSheetChrome(title: "expenses.wants.edit.title", onClose: { isEditingWantsShare = false }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("expenses.wants.edit.explain")
                    .font(.hw(.body))
                    .foregroundStyle(theme.palette.surface.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)

                HWSheetList {
                    ForEach(WantsShare.allCases) { share in
                        HWSheetRow(
                            name: Text(share.label),
                            meta: share == .ruleOfThumb ? Text("expenses.wants.edit.default") : nil,
                            isSelected: share.percent == screen.wants.sharePercent
                        ) {
                            isEditingWantsShare = false
                            Task { await viewModel.setWantsShare(share.percent) }
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
        // Tall enough for seven rows and the sentence above them, and short enough that the summary card stays
        // visible behind it — the figure the choice is about is on that card.
        .presentationDetents([.medium, .large])
    }

    // MARK: - Mapping

    /// The design's category and bill glyphs, as SF Symbols.
    ///
    /// `nonisolated` because `LocalisationTests` subtracts these from the localisation keys it finds in the source
    /// — the same trick it uses for `AppTab.systemImage` and `HomeView.symbol(_:)`. Two of them are dotted names
    /// and would otherwise read as catalogue keys with nothing behind them.
    nonisolated static func symbol(_ icon: ExpensesScreen.Icon) -> String {
        switch icon {
        case .groceries: "basket"
        case .transport: "bus"
        case .entertainment: "film"
        case .other: "questionmark.circle"
        // Money coming in, pointing the way it moves. Not `arrow.left`/`arrow.right`, which would not mirror
        // (ADR-0011) — down carries no direction to reverse.
        case .income: "arrow.down.to.line"
        case .utilities, .bolt: "bolt"
        case .rent: "house"
        case .drop: "drop"
        case .signal: "iphone"
        case .tag: "tag"
        }
    }

    /// `.budget-amt` — "₹1,150 of ₹19,770".
    ///
    /// One catalogue entry with **numbered** arguments rather than two figures joined here: a language that wants
    /// them the other way round has to be able to ask, and the word between them belongs to the translation
    /// (ADR-0011).
    static func wantsAmount(_ wants: ExpensesScreen.Wants) -> Text {
        Text("expenses.wants.amount \(wants.used.display) \(wants.allowance.display)")
    }

    /// The sentence VoiceOver reads instead of the bar, and **the over state said in words**.
    ///
    /// A bar that only changed colour would be a state a colour-blind reader and a screen-reader user both miss,
    /// so the verdict is copy as well as a tint. Two whole sentences rather than one with a clause appended,
    /// because a clause cannot be reordered by a translation (ADR-0011).
    static func wantsDescription(_ wants: ExpensesScreen.Wants) -> Text {
        let used = wants.used.display
        let allowance = wants.allowance.display
        let percentage = wants.percentageLabel
        return wants.isOver
            ? Text("expenses.wants.accessibilityValue.over \(used) \(allowance) \(percentage)")
            : Text("expenses.wants.accessibilityValue \(used) \(allowance) \(percentage)")
    }

    /// Which sentence the toast shows. **The choice is the view model's and the words are the catalogue's**, which
    /// is the split `HomeView.footLine` draws for the same reason: a value translates by being looked up, and a
    /// sentence assembled from one does not.
    static func copy(for notice: ExpensesViewModel.Notice?) -> LocalizedStringResource? {
        switch notice {
        case .entryAdded: "expenses.notice.entryAdded"
        case .entryRemoved: "expenses.notice.entryRemoved"
        case .fixedUpdated: "expenses.notice.fixedUpdated"
        case .billsUpdated: "expenses.notice.billsUpdated"
        case .wantsShareUpdated: "expenses.notice.wantsShareUpdated"
        case nil: nil
        }
    }
}


/// The screen's **content** — the top bar, the summary card, and the panel of seven category rows.
///
/// Split from ``ExpensesView`` at the scroll, which is the split ``ExpenseCategoryPage`` already makes one level
/// down and for the same reason: an `ImageRenderer` does not lay out the content of a `ScrollView`, so a render of
/// the whole screen came back as an empty ground and the test asserting that it "renders" was passing on it.
/// Chrome outside, content inside.
///
/// It takes the payload rather than reading it back out of the view model, because the chrome has already unwrapped
/// it — `loadedContent(_:)` is handed a loaded screen, and a second `state` read here would be a second place that
/// could disagree about which state the screen is in (`StateTaxonomyTests`). The view model is still held, for the
/// two things the bands genuinely ask it: whether a write is in flight, and where a chosen share is sent.
struct ExpensesPage: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let viewModel: ExpensesViewModel

    /// The payload as the chrome has it — see the note above.
    let screen: ExpensesScreen

    /// Owned by the chrome, because the chrome is what presents the sheet. The same arrangement
    /// ``ExpenseCategoryPage`` has with its `picker`.
    @Binding var isEditingWantsShare: Bool

    var body: some View {
        // `.rise` with the design's own `animation-delay` per band — `.topbar` at .02s, `.summary` at .08s,
        // `.bubble` at .14s. The stagger is `hwEnters(step:)`'s, whose six delays are the design's; the three
        // bands here take its first three. Suppressed under Reduce Motion, where the content has simply already
        // arrived (ADR-0012, and see `HWStaggeredEntrance`).
        VStack(alignment: .leading, spacing: 18) {
            topBar
                .hwEnters(step: 0, suppressed: reduceMotion)

            summary
                .hwEnters(step: 1, suppressed: reduceMotion)

            categories
                .hwEnters(step: 2, suppressed: reduceMotion)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The top bar and its Edit control

    /// `.topbar` — the logo and the eyebrow over the title, with an **empty trailing slot**, as the design draws
    /// it. The control for changing the wants share used to sit here; it now sits in the summary card beside the
    /// wants budget it edits (see ``summary``), which is where a reader looking at that bar reaches for it.
    private var topBar: some View {
        HWTopBar(eyebrow: "expenses.eyebrow", title: Text("expenses.title")) {
            EmptyView()
        }
    }

    // MARK: - The monthly summary

    /// `.summary` — the total, the three-way split, and the wants bar under a rule.
    private var summary: some View {
        HWSpendSummary(
            caption: "expenses.summary.caption",
            total: screen.summary.total.display,
            splits: [
                .init("expenses.summary.fixed", screen.summary.fixed.display),
                .init("expenses.summary.variable", screen.summary.variable.display),
                .init("expenses.summary.income", screen.summary.income.display),
            ]
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HWBudgetBar(
                    caption: "expenses.wants.caption",
                    amount: ExpensesView.wantsAmount(screen.wants),
                    percentageLabel: screen.wants.percentageLabel,
                    fill: screen.wants.fill,
                    isOver: screen.wants.isOver,
                    accessibilityDescription: ExpensesView.wantsDescription(screen.wants)
                )

                // **The control that changes the wants share, beside the bar it changes** — a reader looking at
                // "₹4,815 of ₹56,400" reaches for it here rather than at the far corner of the screen. It opens
                // the same sheet the top bar used to, and the server recomputes the allowance and the savings
                // that follow from it (invariant 3). A separate element from the bar above, which is one
                // read-only accessibility element, so the button is its own VoiceOver stop rather than being
                // swallowed by it.
                //
                // **Always offered**, including while §4.2's adaptive branch is in force — when needs have
                // outgrown half of income, choosing a wants share is *how* a reader states the split they want,
                // so hiding the one control that sets it is exactly backwards. The sheet opens with no row ticked
                // (`sharePercent` is `nil`), the reader picks one, and the server recomputes the allowance and
                // the savings that follow — the client asserts nothing about what the figure becomes.
                HWButton(
                    "expenses.wants.edit",
                    variant: .ghost,
                    appearance: .brand,
                    systemImage: "slider.horizontal.3",
                    state: viewModel.isWriting ? .inFlight : .ready
                ) {
                    isEditingWantsShare = true
                }
                .accessibilityHint(Text("expenses.wants.edit.hint"))
            }
        }
    }

    // MARK: - The seven categories

    /// `.bubble` — the tinted panel the rows sit in, with its caption and hint.
    private var categories: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("expenses.categories.caption")
                    .hwEyebrow()
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Text("expenses.categories.hint")
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.accent.base)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(orderedCategories) { category in
                // A `NavigationLink` rather than a button plus a path append: the row *is* the destination, and
                // the shell already wraps this tab in a stack.
                NavigationLink(value: ExpenseCategoryRoute(id: category.id)) {
                    HWCategoryRowLabel(
                        name: category.name,
                        hint: category.hint,
                        total: category.total.display,
                        systemImage: ExpensesView.symbol(category.icon),
                        isIncoming: category.flow == .incoming
                    )
                }
                .buttonStyle(HWPressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: category.name))
                .accessibilityValue(Text(verbatim: category.total.display))
                .accessibilityHint(Text(verbatim: category.hint))
            }
        }
        .padding(8)
        .hwBox(
            fill: bubbleGround,
            radius: .extraLarge,
            border: theme.palette.surface.separator
        )
    }

    /// The categories with **income first**, then the outgoing categories in the server's order.
    ///
    /// Money coming in is the row a reader reaches for after payday, so it leads the list rather than sitting
    /// wherever the payload happened to place it. A stable partition rather than a `sorted` — `Array.sorted` is
    /// not guaranteed stable, and the outgoing rows must keep the order the server sent them in.
    private var orderedCategories: [ExpensesScreen.Category] {
        screen.categories.filter { $0.flow == .incoming }
            + screen.categories.filter { $0.flow != .incoming }
    }

    /// `.bubble{background:linear-gradient(180deg,rgba(208,227,255,.62),rgba(186,214,235,.34))}`.
    ///
    /// **A translucent sky→venus fade, where this was drawing flat opaque venus** — which is why the panel came
    /// back a solid grey-blue slab instead of the pale wash in the design. Two things were wrong and each mattered:
    /// the design fades *between* the two tints rather than using one of them, and it does so at 62% and 34%
    /// opacity, so the warm `.wash` behind the screen shows through the panel and the seven white rows sit on
    /// something lighter than themselves at the top and cooler at the foot.
    ///
    /// `accent.tint` is `--sky` and `accent.tintSecondary` is `--venus`, so both stops are roles and the later
    /// palette swap reaches both (ADR-0001).
    private var bubbleGround: LinearGradient {
        LinearGradient(
            colors: [
                theme.palette.accent.tint.opacity(0.62),
                theme.palette.accent.tintSecondary.opacity(0.34),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

}

#if DEBUG
#Preview("Expenses — a month with everything logged") {
    NavigationStack { ExpensesView(viewModel: .previewINR) }.hwTheme()
}

#Preview("Expenses — the wants budget passed") {
    NavigationStack { ExpensesView(viewModel: .previewOverBudget) }.hwTheme()
}

#Preview("Expenses — a brand-new month") {
    NavigationStack { ExpensesView(viewModel: .previewFirstRun) }.hwTheme()
}

#Preview("Expenses — offline") {
    NavigationStack { ExpensesView(viewModel: .previewOffline) }.hwTheme()
}

#Preview("Expenses — the endpoint is not written yet (501)") {
    NavigationStack { ExpensesView(viewModel: .previewNotImplemented) }.hwTheme()
}

#Preview("Expenses — Arabic, right to left") {
    NavigationStack { ExpensesView(viewModel: .previewINR) }
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

/// Where the wants bar stands aside and its figures remain (ADR-0012).
#Preview("Expenses — AX5") {
    NavigationStack { ExpensesView(viewModel: .previewINR) }
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
