import SwiftUI

/// The design's `.entry` — one logged entry: a glyph tile, what it was for over when it was, the amount, and a
/// remove affordance.
///
/// **The date is a string the server computed** and this component could not compute if it wanted to: there is
/// no timestamp in the payload at all (invariant 6, ADR-0033). The design read `new Date()` here, so moving the
/// device clock re-labelled history.
///
/// The remove control is a **second** control inside the row, and the row itself is not one — an entry is not
/// tappable in the design. So there is nothing to nest and nothing to fight for the hit region: the row is
/// static content with one button in it.
struct HWEntryRow: View {
    @Environment(ThemeManager.self) private var theme

    /// `.entry-lab` — "Metro / subway". Server content: a pick-list option's name, or the user's own words.
    private let label: String
    /// `.entry-when` — "Today", "4 days ago". A string, from the server.
    private let dateLabel: String
    /// `.entry-amt` — server-formatted, and already signed where money is coming in.
    private let amount: String
    private let systemImage: String
    /// `.entry--income` — inverts the tile and tints the figure.
    private let isIncoming: Bool
    /// VoiceOver's reading of the remove affordance. Icon-only, so the caller supplies the whole of it.
    private let removeLabel: LocalizedStringResource
    /// `nil` while a write is in flight, which is how the row says "not now" without inventing a treatment: the
    /// design has no disabled entry row, and a delete that fired twice would send two requests.
    private let onRemove: (() -> Void)?

    init(
        label: String,
        dateLabel: String,
        amount: String,
        systemImage: String,
        isIncoming: Bool = false,
        removeLabel: LocalizedStringResource,
        onRemove: (() -> Void)?
    ) {
        self.label = label
        self.dateLabel = dateLabel
        self.amount = amount
        self.systemImage = systemImage
        self.isIncoming = isIncoming
        self.removeLabel = removeLabel
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 12) {
            tile

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label)
                    .font(.hw(.body).weight(.semibold))
                    .foregroundStyle(theme.palette.surface.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: dateLabel)
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.surface.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The three facts as one element, with the figure as the value: label, then amount, then when.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityValue(Text(verbatim: amount))
            .accessibilityHint(Text(verbatim: dateLabel))

            Text(verbatim: amount)
                .font(.hw(.bodyLarge).weight(.heavy))
                .foregroundStyle(isIncoming ? theme.palette.accent.base : theme.palette.surface.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                // Read as the row's own value above; a second reading would be the same figure twice.
                .accessibilityHidden(true)

            remove
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(minHeight: HWTouchTarget.minimum)
        .hwBox(
            fill: theme.palette.surface.raised,
            radius: .large,
            border: theme.palette.surface.separator,
            elevation: .small
        )
        // A container rather than one combined element: there is a button in here, and combining would swallow
        // it (ADR-0012).
        .accessibilityElement(children: .contain)
    }

    /// `.entry-ico{background:rgba(sky,.66)}`, and `.entry--income .entry-ico{background:rgba(galaxy,.9)}`.
    private var tile: some View {
        Image(systemName: systemImage)
            .font(.hw(.body))
            .foregroundStyle(isIncoming ? theme.palette.accent.soft : theme.palette.accent.base)
            .frame(width: 36, height: 36)
            .hwBox(
                fill: isIncoming ? theme.palette.accent.deep : theme.palette.accent.tint,
                radius: .medium
            )
            .accessibilityHidden(true)
    }

    /// `.entry-del` — a **quiet** cross.
    ///
    /// The weight matters and review caught it: drawn as the raised `.iconbtn`, every row in the list carried a
    /// bordered accent-blue button beside a ₹120 metro fare, which read as the most important thing in the row. It
    /// is the least. The design draws it transparent at 28pt in `--ink-3`; the *target* is 44 for the reason
    /// `HWTouchTarget` records, and the drawing stays the design's size.
    private var remove: some View {
        HWIconButton(
            removeLabel,
            systemImage: "xmark",
            state: onRemove == nil ? .disabled : .ready,
            variant: .quiet,
            action: onRemove ?? {}
        )
    }
}

/// The design's `.empty` — a dashed box saying a list has nothing in it yet.
///
/// **Not `StateView`'s `.empty`, deliberately.** That replaces the whole screen with one sentence; this is the
/// empty *treatment* inside one card, which is the same narrowing `HomeView` records for its first-run donut. A
/// category with nothing logged still has a working form above it and a hero above that, and a user who has just
/// opened Groceries for the first time has not reached an empty screen — they have reached an empty list on a
/// screen that is doing its job.
struct HWEmptyNote: View {
    @Environment(ThemeManager.self) private var theme

    private let message: LocalizedStringResource

    init(_ message: LocalizedStringResource) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.hw(.body))
            .foregroundStyle(theme.palette.surface.inkTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 26)
            .hwBox(
                fill: Color.clear,
                radius: .large,
                border: theme.palette.surface.separatorStrong,
                borderWidth: 1.5,
                // The same dash `HWButtonVariant.dashed` draws, from the same owner, and for the same reason the
                // design uses it here: a broken outline marks a space where a row could be.
                borderDash: HWBorderDash.standard
            )
    }
}

/// The design's `.line`, in its resting form — a named bill and its amount.
struct HWBillLine: View {
    @Environment(ThemeManager.self) private var theme

    private let name: String
    private let amount: String
    private let systemImage: String

    init(name: String, amount: String, systemImage: String) {
        self.name = name
        self.amount = amount
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 9) {
            HWBillGlyph(systemImage: systemImage)

            Text(verbatim: name)
                .font(.hw(.body).weight(.semibold))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: amount)
                .font(.hw(.bodyLarge).weight(.heavy))
                .foregroundStyle(theme.palette.surface.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: HWTouchTarget.minimum)
        .hwBox(fill: theme.palette.surface.backgroundSecondary, radius: .medium)
        // "Electricity, ₹340" as one element: the name labels the bill and the figure is its value.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: amount))
    }
}

/// The design's `.line` under `.editing` — the same row with both halves typeable and a way to remove it.
///
/// **A row with two fields in it, which is the design's own layout and is worth defending.** The alternative —
/// pushing each bill onto its own form — would turn "correct two amounts and delete a third" into six
/// navigations, and the whole point of Utilities' edit mode is that the set is edited and saved as a set
/// (``BillLinesUpdate``).
///
/// The amount field is **not** ``HWMoneyField``: that control owns a label, an error, and a full-width box, and
/// what belongs here is a bare right-aligned entry beside a symbol. So the two do not share an implementation,
/// and each says which shape it is.
struct HWBillLineEditor: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    @Binding private var name: String
    /// As typed, in major units. Parsed into minor units by the view model, which is also the only layer allowed
    /// to name a minor unit (`AccessibilityTests`).
    @Binding private var amount: String
    /// `.line-cur` — the currency's symbol. Decoration, not formatting (ADR-0003).
    private let symbol: String
    private let systemImage: String
    private let nameLabel: LocalizedStringResource
    private let amountLabel: LocalizedStringResource
    private let removeLabel: LocalizedStringResource
    private let onRemove: () -> Void

    init(
        name: Binding<String>,
        amount: Binding<String>,
        symbol: String,
        systemImage: String,
        nameLabel: LocalizedStringResource,
        amountLabel: LocalizedStringResource,
        removeLabel: LocalizedStringResource,
        onRemove: @escaping () -> Void
    ) {
        self._name = name
        self._amount = amount
        self.symbol = symbol
        self.systemImage = systemImage
        self.nameLabel = nameLabel
        self.amountLabel = amountLabel
        self.removeLabel = removeLabel
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 9) {
            HWBillGlyph(systemImage: systemImage)

            TextField(text: $name) { Text(nameLabel) }
                .textFieldStyle(.plain)
                .font(.hw(.body).weight(.semibold))
                .foregroundStyle(theme.palette.surface.ink)
                .tint(theme.palette.accent.base)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isFocused)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(Text(nameLabel))

            Text(verbatim: symbol)
                .font(.hw(.body).weight(.heavy))
                .foregroundStyle(theme.palette.accent.base)
                // Read as part of the amount field's value below rather than as a loose glyph.
                .accessibilityHidden(true)

            TextField(text: $amount) { Text(amountLabel) }
                .textFieldStyle(.plain)
                .font(.hw(.bodyLarge).weight(.heavy))
                .foregroundStyle(theme.palette.surface.ink)
                .tint(theme.palette.accent.base)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                // `.amt-in{width:74px}` — wide enough for a bill, and a **minimum** rather than a width so the
                // figure is not clipped at accessibility sizes.
                .frame(minWidth: 74, idealWidth: 74)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel(Text(amountLabel))
                .accessibilityValue(
                    amount.isEmpty
                        ? Text("component.money.accessibilityEmpty \(symbol)")
                        : Text("component.money.accessibilityValue \(amount) \(symbol)")
                )

            // `.line-del{background:rgba(danger,.10);color:var(--danger)}` — **destructive**, unlike an entry's
            // quiet cross, because a bill is a named thing the user set up and there is nothing here to undo it
            // with: the removal lands with the whole set on Save.
            HWIconButton(removeLabel, systemImage: "xmark", variant: .destructive, action: onRemove)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: HWTouchTarget.minimum)
        .hwBox(
            fill: theme.palette.surface.raised,
            radius: .medium,
            // `.editing .line:focus-within{border-color:var(--universe)}` — the row lights while it is being
            // typed in, which is the only way a row in a set of four says which one has the keyboard.
            border: isFocused ? theme.palette.accent.muted : theme.palette.surface.separatorStrong,
            borderWidth: 1.5
        )
        .animation(reduceMotion ? nil : HWMotion.easeInOut.animation(.standard), value: isFocused)
        // A container: two fields and a button, each reachable.
        .accessibilityElement(children: .contain)
    }
}

/// `.line-ico` — the small tinted tile a bill carries. Shared by the two forms above so the row does not move
/// sideways when edit mode turns on.
private struct HWBillGlyph: View {
    @Environment(ThemeManager.self) private var theme

    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.hw(.body))
            .foregroundStyle(theme.palette.accent.base)
            .frame(width: 34, height: 34)
            .hwBox(fill: theme.palette.accent.tint, radius: .small)
            .accessibilityHidden(true)
    }
}

/// The design's `.fixed-val` in its **locked** form — one monthly amount, with a padlock saying it is counted
/// automatically.
///
/// The editable form is ``HWMoneyField`` at `.prominent`, which is the same shape without the lock. Two views
/// rather than one with a flag, because SwiftUI's own swap is a replacement anyway — a `TextField` and a `Text`
/// are different types — and because what changes between them is not only whether it accepts a keystroke: the
/// resting form is a sky-gradient panel and the editing one is a field box.
struct HWFixedAmount: View {
    @Environment(ThemeManager.self) private var theme

    /// The `.cur` symbol beside the figure. The design prints the symbol separately here even though the figure
    /// is a display string; this draws **only the display string**, for the reason ``HWSpendSummary`` gives —
    /// splitting one would be the client deciding where a symbol ends.
    private let amount: String
    /// What VoiceOver calls it — "Rent", from the payload.
    private let label: String

    init(amount: String, label: String) {
        self.amount = amount
        self.label = label
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: amount)
                .font(.hw(.heading))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // `.lock` — it says "not editable from here", which the absence of a field already says to anybody
            // who can see it, and which is why the *value* below carries the state in words as well.
            Image(systemName: "lock")
                .font(.hw(.body))
                .foregroundStyle(theme.palette.accent.base.opacity(0.55))
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hwBox(
            // `background:linear-gradient(140deg,var(--sky),rgba(venus,.62))`.
            fill: LinearGradient(
                colors: [theme.palette.accent.soft, theme.palette.accent.tint],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            radius: .large,
            border: theme.palette.surface.separator
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: amount))
    }
}

#if DEBUG
#Preview("Entry rows, an empty note, and a locked amount") {
    ScrollView {
        VStack(spacing: 10) {
            HWEntryRow(
                label: "Metro / subway",
                dateLabel: "Today",
                amount: "₹120",
                systemImage: "bus",
                removeLabel: "Remove entry"
            ) {}
            HWEntryRow(
                label: "Freelance design work",
                dateLabel: "5 days ago",
                amount: "+₹900",
                systemImage: "arrow.down.to.line",
                isIncoming: true,
                removeLabel: "Remove entry"
            ) {}
            // A row whose delete is in flight: the affordance is unavailable rather than absent.
            HWEntryRow(
                label: "Cinema — Reel Cinemas",
                dateLabel: "3 days ago",
                amount: "₹300",
                systemImage: "film",
                removeLabel: "Remove entry",
                onRemove: nil
            )

            HWEmptyNote("Nothing logged yet this month.")

            HWFixedAmount(amount: "₹3,000", label: "Rent")
        }
        .padding(18)
    }
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("Bill lines — resting and being edited") {
    @Previewable @State var name = "Electricity"
    @Previewable @State var amount = "340"

    VStack(spacing: 9) {
        HWBillLine(name: "Electricity", amount: "₹340", systemImage: "bolt")
        HWBillLine(name: "Water", amount: "₹48", systemImage: "drop")
        HWBillLineEditor(
            name: $name,
            amount: $amount,
            symbol: "₹",
            systemImage: "bolt",
            nameLabel: "Bill name",
            amountLabel: "Amount",
            removeLabel: "Remove bill"
        ) {}
    }
    .padding(18)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — every row grows and the amount field is not clipped") {
    @Previewable @State var name = "Phone / data"
    @Previewable @State var amount = "141"

    ScrollView {
        VStack(spacing: 10) {
            HWEntryRow(
                label: "Ride-hailing app",
                dateLabel: "Yesterday",
                amount: "₹320",
                systemImage: "bus",
                removeLabel: "Remove entry"
            ) {}
            HWEmptyNote("Nothing logged yet this month.")
            HWBillLineEditor(
                name: $name,
                amount: $amount,
                symbol: "₹",
                systemImage: "iphone",
                nameLabel: "Bill name",
                amountLabel: "Amount",
                removeLabel: "Remove bill"
            ) {}
            HWFixedAmount(amount: "₹3,000", label: "Rent")
        }
        .padding(18)
    }
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("RTL — the tiles lead on the right and the amounts run left") {
    @Previewable @State var name = "الكهرباء"
    @Previewable @State var amount = "340"

    VStack(spacing: 10) {
        HWEntryRow(
            label: "مترو",
            dateLabel: "اليوم",
            amount: "₹120",
            systemImage: "bus",
            removeLabel: "إزالة"
        ) {}
        HWEmptyNote("لا شيء مسجل هذا الشهر.")
        HWBillLineEditor(
            name: $name,
            amount: $amount,
            symbol: "₹",
            systemImage: "bolt",
            nameLabel: "اسم الفاتورة",
            amountLabel: "المبلغ",
            removeLabel: "إزالة"
        ) {}
        HWFixedAmount(amount: "₹3,000", label: "الإيجار")
    }
    .padding(18)
    .environment(\.layoutDirection, .rightToLeft)
    .background(HWPreviewGround())
    .hwTheme()
}
#endif
