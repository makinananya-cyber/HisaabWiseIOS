import SwiftUI

/// The design's `.mchip` — a selectable pill in a horizontal run of them.
///
/// Reports scrolls a row of months through these; the same shape picks a filter or a range elsewhere.
/// `.mchip.on` inverts to the galaxy fill, which is a *state* of one chip rather than a second chip.
///
/// The label is a `Text` because a month chip carries a server-formatted label ("Feb 2026") while a filter
/// chip carries app copy — one component, and the caller decides which (ADR-0020).
struct HWChip: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let label: Text
    private let isSelected: Bool
    private let action: () -> Void

    init(_ label: Text, isSelected: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.hw(.caption).weight(.bold))
                .foregroundStyle(isSelected ? theme.palette.brand.ink : theme.palette.accent.base)
                // No `lineLimit`: at accessibility sizes the label wraps inside a taller chip rather than
                // being truncated, which is what "Dynamic Type unclamped" means for a control this small
                // (ADR-0012).
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                // The design draws these ~34pt tall; `HWTouchTarget` explains why it is 44 here.
                .frame(minHeight: HWTouchTarget.minimum)
                .hwBox(
                    fill: isSelected ? theme.palette.accent.deep : theme.palette.surface.raised,
                    radius: .small,
                    border: isSelected
                        ? theme.palette.accent.deep
                        : theme.palette.surface.separatorStrong,
                    elevation: isSelected ? .medium : .small
                )
                .contentShape(.rect)
                // Selecting a chip is a colour inversion, not a movement. Under Reduce Motion it
                // cross-fades rather than easing through the tint — replaced, not removed (ADR-0012).
                .animation(
                    reduceMotion
                        ? HWMotion.easeInOut.animation(.quick)
                        : HWMotion.easeOut.animation(.standard),
                    value: isSelected
                )
        }
        .buttonStyle(HWPressStyle.compact)
        .hwSelectionTraits(isSelected: isSelected)
    }
}

/// The design's `.opt-chip` / `.srow-iso` — a short code or symbol in a tinted box.
///
/// Not interactive, which is the whole difference from ``HWChip``: it labels the row it sits in — a
/// currency code, an ISO country code, a symbol — and is never the tap target itself.
struct HWCodeChip: View {
    @Environment(ThemeManager.self) private var theme

    private let code: String

    init(_ code: String) {
        self.code = code
    }

    var body: some View {
        Text(verbatim: code)
            .font(.hw(.caption).weight(.heavy))
            .tracking(0.5)
            .foregroundStyle(theme.palette.accent.base)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            // `.opt-chip{min-width:44px;text-align:center}` — the codes are 2–3 characters and the design
            // holds them to one width so a list of them reads as a column.
            .frame(minWidth: 44)
            .hwBox(
                fill: theme.palette.surface.backgroundSecondary,
                radius: .small,
                border: theme.palette.surface.separator
            )
    }
}

#if DEBUG
#Preview("Chips — selected and not") {
    VStack(alignment: .leading, spacing: 18) {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(["Feb 2026", "Mar 2026", "Apr 2026", "May 2026"], id: \.self) { month in
                    HWChip(Text(verbatim: month), isSelected: month == "Mar 2026") {}
                }
            }
            .padding(.horizontal, 2)
        }
        HStack(spacing: 8) {
            HWCodeChip("AED")
            HWCodeChip("INR")
            HWCodeChip("₹")
            HWCodeChip("AE")
        }
    }
    .padding()
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — chips grow rather than clipping") {
    VStack(alignment: .leading, spacing: 12) {
        HWChip(Text(verbatim: "Feb 2026"), isSelected: true) {}
        HWChip(Text(verbatim: "Mar 2026"), isSelected: false) {}
        HWCodeChip("AED")
    }
    .padding()
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

// Latin digits under `ar` — ADR-0011's decision, matching the server's own formatting.
#Preview("RTL") {
    HStack(spacing: 8) {
        HWChip(Text(verbatim: "فبراير 2026"), isSelected: true) {}
        HWChip(Text(verbatim: "مارس 2026"), isSelected: false) {}
        HWCodeChip("AED")
    }
    .padding()
    .environment(\.layoutDirection, .rightToLeft)
    .background(HWPreviewGround())
    .hwTheme()
}
#endif
