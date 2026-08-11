import SwiftUI

/// One category's detail page — the design's `page-detail`, in whichever of the three structural kinds the
/// category is.
///
/// **It re-reads the category from the view model on every draw**, rather than being handed one. That is what
/// makes ADR-0020's write rule visible here: every write answers with the updated screen payload, so the hero's
/// running total, the entry list, and the bills all re-render from server truth while the page stays open. A page
/// holding the category it was pushed with would show the old totals under a list that had changed.
///
/// **Not a `BaseView`.** There is no second request behind it and therefore no second `LoadState`: it is a
/// projection of the screen payload that ``ExpensesView`` already loaded. The four empty-handed states belong to
/// that screen, and a write that fails offline replaces it — which pops this page, because the destination is
/// registered inside its `loadedContent`. The user's typing survives in the draft, so reopening the category finds
/// the amount still in the box.
/// **Two views, split at the navigation chrome**, and the split was found by looking rather than designed: an
/// `ImageRenderer` does not lay out the content of a `ScrollView`, so a render of the whole page came back as an
/// empty ground — and the test asserting that the page "renders" was passing on it. `ExpenseCategoryPage` is the
/// content, so a render draws something and a test can say so; this is the scroll, the title, the toolbar, and the
/// sheet. Chrome outside, content inside, which is the arrangement `ScreenChrome` and `BaseView` already have.
struct ExpenseCategoryView: View {
    let viewModel: ExpensesViewModel

    /// Which category. An id rather than the value, for the reason above.
    let categoryID: String

    /// Which pick list is open, or `nil`. One value rather than a boolean per field: two sheets open at once is a
    /// state that cannot happen, so it should not be representable.
    @State private var picker: ExpensesScreen.Picklist?

    var body: some View {
        Group {
            if let category = viewModel.category(id: categoryID) {
                scrolling(category)
                    .navigationTitle(Text(verbatim: category.name))
            } else {
                // Reachable only if a reload came back without this category, which the seven structural
                // categories make impossible today. Drawing nothing beats drawing a page about nothing.
                EmptyView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // The pick lists are cacheable content fetched on demand, so the first sheet on a bad connection is the
        // slow one and every sheet after it is instant (ADR-0009).
        .task { await viewModel.loadPicklists() }
        .sheet(item: $picker) { picklist in
            pickerSheet(picklist)
        }
        // `openCat` — arriving at a category leaves edit mode, so a page is never found mid-edit from the last
        // visit. Unconditional, because the guard belongs *inside* `open(_:)`: edit mode is per visit and the
        // entry draft is per category, and a check out here got both by keeping neither (see `open(_:)`).
        .onAppear { viewModel.open(categoryID) }
    }

    private func scrolling(_ category: ExpensesScreen.Category) -> some View {
        ScrollView {
            ExpenseCategoryPage(viewModel: viewModel, category: category, picker: $picker)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The design's `.editbtn`, as a toolbar item — the platform's place for a mode toggle, and hidden for the
        // `log` kind exactly as `editBtn.hidden = cat.kind === 'log'` hides it: appending an entry is not editing.
        .toolbar {
            if category.kind != .log {
                ToolbarItem(placement: .topBarTrailing) {
                    editToggle(category)
                }
            }
        }
    }

    /// `.editbtn` / `.editbtn.on` — **Edit** turns the mode on and **Done** commits, as the design has it.
    private func editToggle(_ category: ExpensesScreen.Category) -> some View {
        HWEditButton(
            viewModel.isEditing ? "expenses.done" : "expenses.edit",
            systemImage: viewModel.isEditing ? "checkmark" : "pencil",
            isOn: viewModel.isEditing,
            state: viewModel.isWriting ? .inFlight : .ready
        ) {
            guard viewModel.isEditing else {
                viewModel.beginEditing(categoryID)
                return
            }
            Task { await save(category) }
        }
    }

    private func save(_ category: ExpensesScreen.Category) async {
        switch category.kind {
        case .lines: await viewModel.saveBills(categoryID: categoryID)
        case .fixed: await viewModel.saveFixedAmount(categoryID: categoryID)
        case .log: break
        }
    }

    // MARK: - Copy for each field shape


    /// The four field shapes' labels. **App copy chosen from a structural value** — the payload says which shape
    /// the field is and the words are the catalogue's, which is the split that keeps a sentence translatable while
    /// the *behaviour* stays the server's (ADR-0011, ADR-0033).
    static func label(for field: ExpensesScreen.Field) -> LocalizedStringResource {
        switch field {
        case .place: "expenses.field.place.label"
        case .source: "expenses.field.source.label"
        case .transportMode: "expenses.field.transportMode.label"
        case .otherType: "expenses.field.otherType.label"
        }
    }

    static func placeholder(for field: ExpensesScreen.Field) -> LocalizedStringResource {
        switch field {
        case .place: "expenses.field.place.placeholder"
        case .source: "expenses.field.source.placeholder"
        case .transportMode: "expenses.field.transportMode.placeholder"
        case .otherType: "expenses.field.otherType.placeholder"
        }
    }

    /// The design's `.lead` glyph per field — a tag for something typed, the category's own drawing for a pick.
    ///
    /// `nonisolated` for the reason `ExpensesView.symbol(_:)` is: `LocalisationTests` subtracts these from the
    /// keys it finds in the source, and a scan is not on the main actor.
    nonisolated static func glyph(for field: ExpensesScreen.Field) -> String {
        switch field {
        case .place, .source: "tag"
        case .transportMode: "bus"
        case .otherType: "questionmark.circle"
        }
    }

    static func title(for picklist: ExpensesScreen.Picklist) -> LocalizedStringResource {
        switch picklist {
        case .transport: "expenses.field.transportMode.title"
        case .other: "expenses.field.otherType.title"
        }
    }

    static func searchPrompt(for picklist: ExpensesScreen.Picklist) -> LocalizedStringResource {
        switch picklist {
        case .transport: "expenses.field.transportMode.search"
        case .other: "expenses.field.otherType.search"
        }
    }

    /// The combo's own message. **Only its own**: a missing free-text label belongs beside the text box below it,
    /// not beside the picker that is filled in — which is the mistake registration made and review caught.
    static func comboError(_ failure: ExpensesViewModel.EntryDraft.Failure?) -> LocalizedStringResource? {
        failure == .optionMissing ? "expenses.error.option" : nil
    }

    // MARK: - The pick list sheet

    private func pickerSheet(_ picklist: ExpensesScreen.Picklist) -> some View {
        HWPickerSheet(
            title: Self.title(for: picklist),
            searchPrompt: Self.searchPrompt(for: picklist),
            options: viewModel.options(for: picklist).map {
                HWPickerOption(id: $0.id, name: $0.name)
            },
            selection: viewModel.draft.optionID,
            onSelect: { id in
                viewModel.choose(option: id)
                picker = nil
            },
            onClose: { picker = nil }
        )
    }
}

/// The page's **content** — the hero, and whichever of the three structural kinds the category is.
///
/// Split from ``ExpenseCategoryView`` at the navigation chrome; see the note there for why, and for what looking
/// at a render found.
struct ExpenseCategoryPage: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let viewModel: ExpensesViewModel

    /// The category as the **current** payload has it — read by the chrome on every draw, so a write that answers
    /// with a new screen re-renders this page from server truth (ADR-0020).
    let category: ExpensesScreen.Category

    /// Which pick list to open. Owned by the chrome, because the chrome is what presents the sheet.
    @Binding var picker: ExpensesScreen.Picklist?

    private var categoryID: String { category.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HWCategoryHero(
                name: category.name,
                hint: category.hint,
                total: category.total.display,
                monthLabel: viewModel.monthLabel,
                systemImage: ExpensesView.symbol(category.icon),
                isIncoming: category.flow == .incoming
            )

            switch category.kind {
            case .log: logKind(category)
            case .lines: linesKind(category)
            case .fixed: fixedKind(category)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }



    @ViewBuilder
    private func logKind(_ category: ExpensesScreen.Category) -> some View {
        HWCard(caption: category.flow == .incoming ? "expenses.add.income.caption" : "expenses.add.caption") {
            VStack(alignment: .leading, spacing: 12) {
                amountField

                if let field = category.field {
                    extraField(field)
                }

                HWButton(
                    category.flow == .incoming ? "expenses.add.income.action" : "expenses.add.action",
                    systemImage: "plus",
                    state: viewModel.isWriting ? .inFlight : .ready
                ) {
                    Task { await viewModel.addEntry() }
                }
                .padding(.top, 4)
            }
        }

        // `.list-head` — the month, and how many entries are in it. Both the server's.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: viewModel.monthLabel)
                .hwEyebrow()
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let count = category.entryCountLabel {
                Text(verbatim: count)
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.surface.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)

        if category.entries.isEmpty {
            HWEmptyNote("expenses.entries.empty")
        } else {
            VStack(spacing: 8) {
                ForEach(category.entries) { entry in
                    HWEntryRow(
                        label: entry.label,
                        dateLabel: entry.dateLabel,
                        amount: entry.amount.display,
                        systemImage: ExpensesView.symbol(category.icon),
                        isIncoming: category.flow == .incoming,
                        removeLabel: "expenses.entry.remove",
                        // Unavailable rather than absent while a write is in flight: a delete that fired twice
                        // would send two requests, and a control that vanished would move the row under a finger.
                        onRemove: viewModel.isWriting
                            ? nil
                            : { Task { await viewModel.deleteEntry(id: entry.id) } }
                    )
                }
            }
            // Rows arriving and leaving is the one thing on this page that moves. Under Reduce Motion the list
            // changes without the slide — replaced by arriving in place, not removed (ADR-0012).
            .animation(
                reduceMotion ? nil : HWMotion.easeOut.animation(.standard),
                value: category.entries
            )
        }
    }

    /// `.amount` — the big field the figure is typed into.
    ///
    /// **The label is not drawn**, because the card's own caption already says "Add an expense" and the design puts
    /// no `.fld-lab` above it. It is still the field's VoiceOver label, which is the half that must not be dropped:
    /// a screen reader has no card caption to read from.
    private var amountField: some View {
        HWMoneyField(
            "expenses.amount.label",
            text: Binding(
                get: { viewModel.draft.amount },
                set: { viewModel.editAmount($0) }
            ),
            symbol: viewModel.entrySymbol,
            code: viewModel.entryCode,
            error: viewModel.draft.failure == .amountMissing ? "expenses.error.amount" : nil,
            prominence: .prominent,
            showsLabel: false
        )
    }

    /// The one extra field a `log` entry may carry — typed, or picked from a server-served list.
    @ViewBuilder
    private func extraField(_ field: ExpensesScreen.Field) -> some View {
        if let picklist = field.picklist {
            HWCombo(
                ExpenseCategoryView.label(for: field),
                value: viewModel.chosenOptionName.map { Text(verbatim: $0) },
                placeholder: ExpenseCategoryView.placeholder(for: field),
                systemImage: ExpenseCategoryView.glyph(for: field),
                error: ExpenseCategoryView.comboError(viewModel.draft.failure),
                isOpen: picker == picklist
            ) {
                picker = picklist
            }

            // The free-text box the one flagged option opens. **From the option's own flag, never from its
            // name** — the design matches `/something else/i` against English text, which stops working the
            // moment the list is translated.
            if viewModel.draft.needsFreeText {
                HWTextField(
                    "expenses.field.custom.label",
                    text: Binding(get: { viewModel.draft.label }, set: { viewModel.editLabel($0) }),
                    placeholder: "expenses.field.custom.placeholder",
                    systemImage: "tag",
                    error: viewModel.draft.failure == .labelMissing ? "expenses.error.custom" : nil
                )
            }
        } else {
            HWTextField(
                ExpenseCategoryView.label(for: field),
                text: Binding(get: { viewModel.draft.label }, set: { viewModel.editLabel($0) }),
                placeholder: ExpenseCategoryView.placeholder(for: field),
                systemImage: ExpenseCategoryView.glyph(for: field),
                error: viewModel.draft.failure == .labelMissing ? "expenses.error.label" : nil
            )
        }
    }

    // MARK: - `lines` — a set of named monthly bills

    @ViewBuilder
    private func linesKind(_ category: ExpensesScreen.Category) -> some View {
        HWCard(caption: "expenses.bills.caption") {
            VStack(alignment: .leading, spacing: 12) {
                Text("expenses.bills.explain")
                    .font(.hw(.body))
                    .foregroundStyle(theme.palette.surface.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.isEditing {
                    billEditors
                } else {
                    VStack(spacing: 9) {
                        ForEach(category.lines) { line in
                            HWBillLine(
                                name: line.name,
                                amount: line.amount.display,
                                systemImage: ExpensesView.symbol(line.icon)
                            )
                        }
                    }
                }
            }
        }
    }

    /// `.editing .lines` plus `.addline` and the save control.
    ///
    /// The whole set is edited and saved together, which is the gesture the design has: rename one, correct two
    /// amounts, delete a third, add a fourth, and commit all of it as one `PUT` (``BillLinesUpdate``).
    @ViewBuilder
    private var billEditors: some View {
        VStack(spacing: 9) {
            ForEach(Array(viewModel.billDrafts.enumerated()), id: \.element.key) { index, draft in
                HWBillLineEditor(
                    name: Binding(
                        get: { draft.name },
                        set: { viewModel.editBill(at: index, name: $0) }
                    ),
                    amount: Binding(
                        get: { draft.amount },
                        set: { viewModel.editBill(at: index, amount: $0) }
                    ),
                    symbol: viewModel.entrySymbol,
                    systemImage: ExpensesView.symbol(draft.icon),
                    nameLabel: "expenses.bill.name",
                    amountLabel: "expenses.bill.amount",
                    removeLabel: "expenses.bill.remove"
                ) {
                    viewModel.removeBill(at: index)
                }
            }

            HWButton("expenses.bills.add", variant: .dashed, systemImage: "plus") {
                viewModel.addBill()
            }

            HWButton(
                "expenses.bills.action",
                systemImage: "checkmark",
                state: viewModel.isWriting ? .inFlight : .ready
            ) {
                Task { await viewModel.saveBills(categoryID: categoryID) }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - `fixed` — one editable monthly amount

    @ViewBuilder
    private func fixedKind(_ category: ExpensesScreen.Category) -> some View {
        HWCard(caption: "expenses.fixed.caption") {
            VStack(alignment: .leading, spacing: 12) {
                Text("expenses.fixed.explain")
                    .font(.hw(.body))
                    .foregroundStyle(theme.palette.surface.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.isEditing {
                    HWMoneyField(
                        "expenses.fixed.label",
                        text: Binding(
                            get: { viewModel.fixedAmount },
                            set: { viewModel.editFixedAmount($0) }
                        ),
                        symbol: viewModel.entrySymbol,
                        code: viewModel.entryCode,
                        prominence: .prominent,
                        showsLabel: false
                    )

                    HWButton(
                        "expenses.fixed.action",
                        systemImage: "checkmark",
                        state: viewModel.isWriting ? .inFlight : .ready
                    ) {
                        Task { await viewModel.saveFixedAmount(categoryID: categoryID) }
                    }
                    .padding(.top, 4)
                } else {
                    // `.fixed-val` with its padlock: counted automatically, and edited from the toolbar.
                    HWFixedAmount(amount: category.total.display, label: category.name)
                }
            }
        }
    }
}

/// `Identifiable` so a picklist can drive `.sheet(item:)`. On the model rather than through a wrapper, because
/// which list is open *is* the identity — there is one sheet per list.
extension ExpensesScreen.Picklist: Identifiable {
    var id: Self { self }
}

#if DEBUG
// "Commute" rather than the category's own name in the preview titles: `LayeringTests` scans this layer for the
// word `Transport` — a screen must not be able to reach the networking layer's `Transport` protocol — and a
// preview label should not be what trips it. The same substitution `HWKeyRow`'s preview makes.
#Preview("A log category — Commute, with a pick list") {
    NavigationStack {
        ExpenseCategoryPreview(viewModel: .previewINR, categoryID: "transport")
    }
    .hwTheme()
}

#Preview("A log category — nothing logged yet") {
    NavigationStack {
        ExpenseCategoryPreview(viewModel: .previewFirstRun, categoryID: "groceries")
    }
    .hwTheme()
}

#Preview("Additional Income — money in") {
    NavigationStack {
        ExpenseCategoryPreview(viewModel: .previewINR, categoryID: "income")
    }
    .hwTheme()
}

#Preview("The lines kind — Utilities") {
    NavigationStack {
        ExpenseCategoryPreview(viewModel: .previewINR, categoryID: "utilities")
    }
    .hwTheme()
}

#Preview("The fixed kind — Rent, locked") {
    NavigationStack {
        ExpenseCategoryPreview(viewModel: .previewINR, categoryID: "rent")
    }
    .hwTheme()
}

#Preview("AX5 — the form and the rows grow") {
    NavigationStack {
        ExpenseCategoryPreview(viewModel: .previewINR, categoryID: "transport")
    }
    .hwTheme()
    .dynamicTypeSize(.accessibility5)
}

#Preview("RTL — Arabic, right to left") {
    NavigationStack {
        ExpenseCategoryPreview(viewModel: .previewINR, categoryID: "transport")
    }
    .hwTheme()
    .hwLanguage(LanguageManager(selected: .arabic))
}

/// Loads the screen before drawing the page, because the page is a projection of a payload rather than a screen
/// with a request of its own — a preview that drew it straight away would draw the `nil` branch.
private struct ExpenseCategoryPreview: View {
    let viewModel: ExpensesViewModel
    let categoryID: String

    var body: some View {
        ExpenseCategoryView(viewModel: viewModel, categoryID: categoryID)
            .task { try? await viewModel.load() }
    }
}
#endif
