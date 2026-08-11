import SwiftUI

/// The design's date field — `<input type="date">` with its label `.pinned`, which on iOS is a `DatePicker`.
///
/// **The system's picker, deliberately, and it is the one place a date is rendered without our code touching
/// it.** ADR-0011 keeps every formatter out of the app; a compact `DatePicker` draws the chosen date in the
/// environment's own locale and calendar, which is the same rule applied to dates rather than an exception to it.
/// Building a field that showed `12/03/1994` would mean choosing an order, and the order is the locale's.
///
/// **`Date?`, not `Date`.** Nothing is chosen until the user chooses it — a picker defaulted to today's date
/// minus eighteen years would let somebody submit a birthday they never entered, and the "please choose your date
/// of birth" rule could then never fire. Until then the placeholder is drawn over the picker, which stays
/// tappable underneath: one tap still opens the calendar.
///
/// **Brand only** — the design has one date field, on registration.
struct HWDateField: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let label: LocalizedStringResource
    @Binding private var date: Date?
    /// The choosable span. Registration's is "13 years ago to 120 years ago", so the commonest mistake — a year
    /// that makes the user four — is unavailable rather than rejected after the fact.
    private let range: ClosedRange<Date>
    /// What the box says before anything is chosen.
    private let placeholder: LocalizedStringResource
    private let error: LocalizedStringResource?

    init(
        _ label: LocalizedStringResource,
        date: Binding<Date?>,
        in range: ClosedRange<Date>,
        placeholder: LocalizedStringResource,
        error: LocalizedStringResource? = nil
    ) {
        self.label = label
        self._date = date
        self.range = range
        self.placeholder = placeholder
        self.error = error
    }

    private var isInvalid: Bool { error != nil }

    /// The picker needs a non-optional binding. Reading gives it the **newest allowed** date when nothing is
    /// chosen — the far end of the range rather than an arbitrary default, so the calendar opens where a 13-year
    /// -old's birthday would be and the user scrolls back rather than forward. Writing is what makes the choice
    /// real, and is the only thing that ever sets it.
    private var chosen: Binding<Date> {
        Binding(get: { date ?? range.upperBound }, set: { date = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .hwLabel(.brand)
                .accessibilityHidden(true)

            box
                .animation(reduceMotion ? nil : HWMotion.easeInOut.animation(.standard), value: isInvalid)

            if let error {
                Text(error)
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.standard), value: isInvalid)
    }

    private var box: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.hw(.bodyLarge))
                .foregroundStyle(isInvalid ? theme.palette.brand.danger : theme.palette.brand.inkSecondary)
                .accessibilityHidden(true)

            picker

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: HWTextField.minimumHeight)
        .hwBox(
            fill: theme.palette.brand.raised,
            radius: .large,
            border: isInvalid ? theme.palette.brand.danger : theme.palette.brand.separator,
            borderWidth: 1.5
        )
    }

    /// The system picker, with the placeholder drawn over it while nothing is chosen.
    ///
    /// **`.opacity(0)` does not take a view out of the accessibility tree**, and the proxy binding reads
    /// `range.upperBound` — so an untouched field used to announce "Date of birth, 1 January 2013", a date the
    /// user never chose, to exactly the users who cannot see the placeholder saying otherwise. The value is
    /// overridden in that state; when a date *has* been chosen the system's own value stands, because there is no
    /// formatter here to reproduce it (ADR-0003, ADR-0011).
    @ViewBuilder
    private var picker: some View {
        if date == nil {
            systemPicker
                .opacity(0)
                .overlay(alignment: .leading) { prompt }
                .accessibilityValue(Text(placeholder))
        } else {
            systemPicker
        }
    }

    private var systemPicker: some View {
        DatePicker(selection: chosen, in: range, displayedComponents: .date) {
            Text(label)
        }
        .labelsHidden()
        .datePickerStyle(.compact)
        .tint(theme.palette.brand.inkAccent)
        .accessibilityLabel(Text(label))
        .accessibilityHint(error.map { Text($0) } ?? Text(verbatim: ""))
    }

    /// The placeholder, drawn over the hidden picker. Not announced: the picker beneath it carries the same words
    /// as its value, so a second element would read the field twice.
    private var prompt: some View {
        Text(placeholder)
            .font(.hw(.bodyLarge).weight(.regular))
            .foregroundStyle(theme.palette.brand.inkSecondary.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

#if DEBUG
/// A fixed span, so the previews do not move with the calendar: 1906 to 2013, which is the 13-to-120 window as
/// it stood when these were written.
private let previewRange: ClosedRange<Date> = {
    var components = DateComponents(year: 1906, month: 1, day: 1)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let oldest = calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    components.year = 2013
    let newest = calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    return oldest...newest
}()

#Preview("Date field — chosen, unchosen, invalid") {
    @Previewable @State var chosen: Date? = previewRange.upperBound
    @Previewable @State var unchosen: Date?
    @Previewable @State var invalid: Date? = previewRange.upperBound

    VStack(spacing: 16) {
        HWDateField("Date of birth", date: $chosen, in: previewRange, placeholder: "Choose your date of birth")
        HWDateField("Date of birth", date: $unchosen, in: previewRange, placeholder: "Choose your date of birth")
        HWDateField(
            "Date of birth",
            date: $invalid,
            in: previewRange,
            placeholder: "Choose your date of birth",
            error: "You need to be at least 13 to open an account."
        )
    }
    .padding(22)
    .background(HWPreviewGround(appearance: .brand))
    .hwTheme()
}

#Preview("AX3 — the box grows around the picker") {
    @Previewable @State var chosen: Date? = previewRange.upperBound

    HWDateField("Date of birth", date: $chosen, in: previewRange, placeholder: "Choose your date of birth")
        .padding(22)
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}

#Preview("RTL — the glyph leads on the right and the picker follows the locale") {
    @Previewable @State var unchosen: Date?

    HWDateField("تاريخ الميلاد", date: $unchosen, in: previewRange, placeholder: "اختر تاريخ ميلادك")
        .padding(22)
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}
#endif
