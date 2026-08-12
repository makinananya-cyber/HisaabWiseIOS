import SwiftUI

/// The design's `.arow` — one category of a closed month, openable to show every entry filed under it.
///
/// **The whole block is one component, panel included**, rather than a header with a `ViewBuilder` slot. The
/// entries are the panel's own layout — hairline-separated rows, and a note where there are none — so a screen
/// handed the slot would be a screen writing that layout, which is what the rule at the top of `Components.swift`
/// forbids. The screen maps the payload onto ``Entry`` and nothing else.
///
/// **One panel open at a time is the caller's rule, not this view's**: it takes `isExpanded` and reports a tap.
/// The design closes every other panel before opening one, which is a decision about the card rather than about a
/// row — `ReportsMonthViewModel.expanded` holds it, and a `String?` makes two-open unrepresentable.
///
/// **An archived entry has no remove affordance at all**, which is the one way this differs from ``HWEntryRow``
/// beyond the styling. That row draws a quiet cross and takes a `nil` closure to mean "not now"; an archived month
/// is immutable (invariant 7), so there is no delete to be unavailable — a disabled control here would offer
/// something that is not merely busy but impossible.
struct HWAccordionRow: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One `.ent` — an amount, what it was for, and when.
    ///
    /// **Identified by position**, because an archived entry carries no id: the id on a live entry is the address
    /// `DELETE /v1/expenses/:id` is sent to, and there is nothing to send anywhere about a closed month.
    struct Entry: Identifiable, Sendable, Hashable {
        let id: Int
        /// "Metro / subway" — server content.
        let label: String
        /// "14 Feb", or "Fixed each month". A string, from the server (invariant 6).
        let dateLabel: String
        /// Server-formatted, and already signed where money came in.
        let amount: String
        let systemImage: String
    }

    /// `.a-name` — the category's name. Server content.
    let name: String

    /// `.a-sub` — "3 entries · 28% of spend". A count, a plural, and a percentage, so the server composes it.
    let summaryLabel: String

    /// `.a-amt` — the category's total for the month.
    let amount: String

    let systemImage: String

    /// Which of the six category colour slots tints the glyph tile, `1...6`.
    let slot: Int

    /// `.arow--income` — inverts the tile and tints the figure, as ``HWEntryRow`` does for money coming in.
    var isIncoming: Bool = false

    let isExpanded: Bool

    /// Every entry, in the order the server sent them.
    let entries: [Entry]

    /// What the panel says when there are none — the category's own sentence, from the screen's catalogue.
    let emptyNote: LocalizedStringResource

    /// What VoiceOver says the tap does. Two sentences, chosen by the caller, because opening and closing are
    /// different consequences and a hint that described only one would be wrong half the time.
    let hint: LocalizedStringResource

    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) { header }
                // `.ahead:hover` is a pointer state; the press scale is the app's own (``HWPressStyle``).
                .buttonStyle(HWPressStyle.compact)
                // Read as one control — "Groceries", "₹14,780", "3 entries · 28% of spend" — with the figure as
                // the value so a re-read in another currency re-announces the number (ADR-0012).
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: name))
                .accessibilityValue(Text(verbatim: amount))
                .accessibilityHint(Text(hint))

            if isExpanded {
                panel
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hwBox(
            fill: theme.palette.surface.raised,
            radius: .large,
            border: isExpanded ? theme.palette.surface.separatorStrong : theme.palette.surface.separator,
            elevation: .small
        )
        // `max-height` transition on `.abody`. Under Reduce Motion the panel is simply *there* rather than
        // unrolling more slowly, which is the replacement ADR-0012 asks for: the content is the point, and it
        // arrives either way.
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.standard), value: isExpanded)
        // A container rather than one combined element: there is a control in here and a list under it.
        .accessibilityElement(children: .contain)
    }

    // MARK: - The header

    /// `.ahead` — the tile, the name over its summary, the total, and the chevron.
    private var header: some View {
        HStack(spacing: 12) {
            tile

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.hw(.bodyLarge).weight(.bold))
                    .foregroundStyle(theme.palette.surface.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: summaryLabel)
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.surface.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: amount)
                .font(.hw(.bodyLarge).weight(.heavy))
                .foregroundStyle(isIncoming ? theme.palette.accent.base : theme.palette.surface.ink)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)

            chevron
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(minHeight: HWTouchTarget.minimum)
        .contentShape(.rect)
    }

    /// `.a-ico` — the glyph on its own wash of the category's colour.
    ///
    /// The design carries a **sixth pastel** per slot as a literal hex with no custom property behind it, so the
    /// wash is the slot's own role at low opacity instead: one owner, and the later palette swap reaches it
    /// (ADR-0001). Income keeps ``HWEntryRow``'s inversion — the galaxy tile with the sky glyph — because that is
    /// the treatment the app already uses for money in.
    private var tile: some View {
        Image(systemName: systemImage)
            .font(.hw(.body))
            .foregroundStyle(isIncoming ? theme.palette.accent.soft : slotColour)
            .frame(width: 36, height: 36)
            .hwBox(
                fill: isIncoming ? theme.palette.accent.deep : slotColour.opacity(0.14),
                radius: .medium
            )
            .accessibilityHidden(true)
    }

    /// `.a-chev`, and `.arow.open .a-chev{transform:rotate(90deg)}`.
    ///
    /// Two glyphs rather than one rotated: `chevron.forward` mirrors under RTL (ADR-0011) and a rotation applied
    /// to it would fight that, where `chevron.down` points the same way in every language.
    private var chevron: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.forward")
            .font(.hw(.caption).weight(.bold))
            .foregroundStyle(isExpanded ? theme.palette.accent.base : theme.palette.surface.inkTertiary)
            .frame(width: 26, height: 26)
            // The chevron says "this opens", which the button trait and the hint already say.
            .accessibilityHidden(true)
    }

    // MARK: - The panel

    /// `.abody` — every entry, or the note that says there were none.
    private var panel: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                HWEmptyNote(emptyNote)
                    .padding(.top, 4)
            } else {
                ForEach(entries) { entry in
                    row(entry, isFirst: entry.id == entries.first?.id)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.bottom, 13)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }

    /// One `.ent`, with the hairline the design puts between entries and not above the first.
    private func row(_ entry: Entry, isFirst: Bool) -> some View {
        HStack(spacing: 11) {
            // `.ent-dot`
            Image(systemName: entry.systemImage)
                .font(.hw(.caption))
                .foregroundStyle(isIncoming ? theme.palette.accent.soft : theme.palette.accent.base)
                .frame(width: 28, height: 28)
                .hwBox(
                    fill: isIncoming ? theme.palette.accent.deep : theme.palette.accent.tint,
                    radius: .small
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.label)
                    .font(.hw(.body).weight(.semibold))
                    .foregroundStyle(theme.palette.surface.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: entry.dateLabel)
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.surface.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: entry.amount)
                .font(.hw(.body).weight(.heavy))
                .foregroundStyle(isIncoming ? theme.palette.accent.base : theme.palette.surface.ink)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(theme.palette.surface.separator)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        // "Metro / subway" — "₹1,890" — "5 Feb": the figure is the value and the date is the hint, which is the
        // reading ``HWEntryRow`` gives the same three facts.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: entry.label))
        .accessibilityValue(Text(verbatim: entry.amount))
        .accessibilityHint(Text(verbatim: entry.dateLabel))
    }

    /// The six category colour slots, by palette role. A slot outside the range wraps rather than crashing: the
    /// number arrives from a payload, and a seventh category is a server change, not a client crash — the same
    /// rule ``HWDonut`` and ``HWProportionBar`` apply.
    private var slotColour: Color {
        let palette = theme.palette.categories.all
        guard !palette.isEmpty else { return theme.palette.accent.base }
        return palette[(max(slot, 1) - 1) % palette.count]
    }
}

#if DEBUG
private let previewEntries: [HWAccordionRow.Entry] = [
    .init(id: 0, label: "Groceries", dateLabel: "2 Feb", amount: "₹5,580", systemImage: "basket"),
    .init(id: 1, label: "Groceries", dateLabel: "14 Feb", amount: "₹4,900", systemImage: "basket"),
    .init(id: 2, label: "Groceries", dateLabel: "24 Feb", amount: "₹4,300", systemImage: "basket"),
]

@MainActor
private func previewRows(expanded: String?) -> some View {
    VStack(spacing: 8) {
        HWAccordionRow(
            name: "Groceries",
            summaryLabel: "3 entries · 28% of spend",
            amount: "₹14,780",
            systemImage: "basket",
            slot: 2,
            isExpanded: expanded == "groceries",
            entries: previewEntries,
            emptyNote: "Nothing logged under Groceries that month.",
            hint: "Shows the entries",
            onToggle: {}
        )

        HWAccordionRow(
            name: "Entertainment",
            summaryLabel: "No entries",
            amount: "₹0",
            systemImage: "film",
            slot: 5,
            isExpanded: expanded == "entertainment",
            entries: [],
            emptyNote: "Nothing logged under Entertainment that month.",
            hint: "Shows the entries",
            onToggle: {}
        )

        HWAccordionRow(
            name: "Additional income",
            summaryLabel: "1 entry · on top of salary",
            amount: "+₹8,100",
            systemImage: "arrow.down.to.line",
            slot: 1,
            isIncoming: true,
            isExpanded: expanded == "income",
            entries: [
                .init(id: 0, label: "Freelance design work", dateLabel: "24 Feb", amount: "+₹8,100",
                      systemImage: "arrow.down.to.line"),
            ],
            emptyNote: "No extra income that month — salary only.",
            hint: "Shows the entries",
            onToggle: {}
        )
    }
}

#Preview("The accordion — one panel open, one empty, and the income row") {
    previewRows(expanded: "groceries")
        .padding()
        .background(HWPreviewGround())
        .hwTheme()
}

#Preview("Every panel closed") {
    previewRows(expanded: nil)
        .padding()
        .background(HWPreviewGround())
        .hwTheme()
}

#Preview("AX3 — the rows grow and the entries wrap") {
    ScrollView {
        previewRows(expanded: "groceries").padding()
    }
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("RTL — the tiles, the figures, and the chevron mirror") {
    previewRows(expanded: "entertainment")
        .padding()
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround())
        .hwTheme()
}
#endif
