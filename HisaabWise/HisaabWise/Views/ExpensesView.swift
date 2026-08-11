import SwiftUI

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

    /// Held rather than read from `@Environment`, so a test or a preview can construct the screen over a fixture
    /// transport. The five-tab shell puts one per tab in the environment.
    let viewModel: ExpensesViewModel

    /// Overridden because the server can answer with no screen at all, and a screen that supplied no empty copy
    /// would fall back to a default that says nothing about Expenses. `isEmpty` is `false` — see the note above.
    var stateCopy: StateCopy {
        StateCopy(empty: "expenses.empty")
    }

    @ViewBuilder
    func loadedContent(_ screen: ExpensesScreen) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HWTopBar(eyebrow: "expenses.eyebrow", title: Text("expenses.title"))

                summary(screen)

                categories(screen)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        // One destination, pushed onto the stack the shell wraps this tab in. It carries the **id** and the page
        // re-reads the category from the view model, so a write that returns a new payload re-renders the page
        // that is open rather than leaving it showing what it was pushed with.
        .navigationDestination(for: ExpenseCategoryRoute.self) { route in
            ExpenseCategoryView(viewModel: viewModel, categoryID: route.id)
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

    // MARK: - The monthly summary

    /// `.summary` — the total, the three-way split, and the wants bar under a rule.
    private func summary(_ screen: ExpensesScreen) -> some View {
        HWSpendSummary(
            caption: "expenses.summary.caption",
            total: screen.summary.total.display,
            splits: [
                .init("expenses.summary.fixed", screen.summary.fixed.display),
                .init("expenses.summary.variable", screen.summary.variable.display),
                .init("expenses.summary.income", screen.summary.income.display),
            ]
        ) {
            HWBudgetBar(
                caption: "expenses.wants.caption",
                amount: Self.wantsAmount(screen.wants),
                percentageLabel: screen.wants.percentageLabel,
                fill: screen.wants.fill,
                isOver: screen.wants.isOver,
                accessibilityDescription: Self.wantsDescription(screen.wants)
            )
        }
    }

    // MARK: - The seven categories

    /// `.bubble` — the tinted panel the rows sit in, with its caption and hint.
    private func categories(_ screen: ExpensesScreen) -> some View {
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

            ForEach(screen.categories) { category in
                // A `NavigationLink` rather than a button plus a path append: the row *is* the destination, and
                // the shell already wraps this tab in a stack.
                NavigationLink(value: ExpenseCategoryRoute(id: category.id)) {
                    HWCategoryRowLabel(
                        name: category.name,
                        hint: category.hint,
                        total: category.total.display,
                        systemImage: Self.symbol(category.icon),
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
            fill: theme.palette.accent.tintSecondary,
            radius: .extraLarge,
            border: theme.palette.surface.separator
        )
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
        case nil: nil
        }
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
