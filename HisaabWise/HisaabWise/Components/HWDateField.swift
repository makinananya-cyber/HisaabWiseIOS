import SwiftUI

/// The design's date field — `<input type="date">`, which on iOS Safari opens a picker in a sheet. So this is a
/// **button that opens a sheet**, which is closer to the design than an inline control is.
///
/// **It was a compact `DatePicker` drawn at `opacity(0)` under the placeholder, and the words were not
/// tappable.** An `.overlay` is laid out by its parent but only the *picker's* own frame takes taps, and a
/// compact picker's frame is the small date pill on the leading edge — so the visible "Choose your date of birth"
/// was dead, and the live target was an invisible pill beside it. A `Button` has one unambiguous hit region, the
/// whole field box, in both states.
///
/// **The date is still rendered by the system, not by us.** `Text(_:format:)` resolves against the environment's
/// locale and calendar — the one `hwLanguage(_:)` set (ADR-0011) — so nothing here chooses whether a day comes
/// before a month. ADR-0003's no-formatter rule is about **money**, where the server owns conversion and
/// rounding; a date of birth the user picked thirty seconds ago is not a server-owned figure.
///
/// **`Date?`, not `Date`.** Nothing is chosen until the user chooses it — a field defaulted to "eighteen years
/// ago" would let somebody submit a birthday they never entered, and the "please choose your date of birth" rule
/// could then never fire.
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

    /// Whether the picker sheet is up. The field's own state: a caller that owned it would have to reset it.
    @State private var isChoosing = false

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

    /// The closed field: a button covering the whole box.
    private var box: some View {
        Button {
            isChoosing = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.hw(.bodyLarge))
                    .foregroundStyle(isInvalid ? theme.palette.brand.danger : theme.palette.brand.inkSecondary)
                    .accessibilityHidden(true)

                value

                Spacer(minLength: 0)

                // `.chev` — the same affordance the currency and question combos carry, because this is now the
                // same kind of control.
                Image(systemName: "chevron.down")
                    .font(.hw(.caption).weight(.bold))
                    .foregroundStyle(theme.palette.brand.inkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: HWTextField.minimumHeight)
            .hwBox(
                fill: theme.palette.brand.raised,
                radius: .large,
                border: isInvalid ? theme.palette.brand.danger : theme.palette.brand.separator,
                borderWidth: 1.5
            )
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        // One element: "Date of birth, 12 March 1994, button" — or the placeholder as the value while nothing is
        // chosen, which is what stops it announcing a date nobody picked.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(error.map { Text($0) } ?? Text("component.combo.hint"))
        .sheet(isPresented: $isChoosing) { sheet }
    }

    /// The chosen date, or the placeholder. **The system formats it** — `Text(_:format:)` against the environment
    /// locale — so nothing here decides whether the day comes before the month.
    @ViewBuilder
    private var value: some View {
        if let date {
            Text(date, format: .dateTime.day().month(.wide).year())
                .font(.hw(.bodyLarge).weight(.regular))
                .foregroundStyle(theme.palette.brand.ink)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(placeholder)
                .font(.hw(.bodyLarge).weight(.regular))
                .foregroundStyle(theme.palette.brand.inkSecondary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What VoiceOver reads as the value. `Text(_:format:)` resolves the same way it does on screen, so the two
    /// cannot disagree.
    private var accessibilityValue: Text {
        if let date {
            Text(date, format: .dateTime.day().month(.wide).year())
        } else {
            Text(placeholder)
        }
    }

    /// The picker, in the sheet the design's native input opens.
    ///
    /// `.graphical` rather than the wheel: a date of birth is reached by year first, and a calendar's year header
    /// is one tap away where a wheel is a long scroll. The picker's **own** colour scheme is forced dark, which is
    /// not an ADR-0021 palette swap — it is telling a system control which ground it has been placed on, and the
    /// galaxy panel is the ground. Left light, the calendar draws dark ink on a dark sheet.
    private var sheet: some View {
        HWSheetChrome(title: placeholder, onClose: { isChoosing = false }, appearance: .brand) {
            DatePicker(selection: chosen, in: range, displayedComponents: .date) {
                Text(label)
            }
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(theme.palette.brand.inkAccent)
                .environment(\.colorScheme, .dark)
                .padding(.horizontal, 16)
                .accessibilityLabel(Text(label))

            done
                .padding(.horizontal, 16)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .presentationBackground(theme.palette.brand.backgroundDeep)
        .presentationDetents([.medium, .large])
    }

    /// **Done, and it is load-bearing rather than a courtesy.**
    ///
    /// `chosen` reads `date ?? range.upperBound`, so a sheet opened with nothing chosen shows the *newest
    /// allowed* date already selected. Tapping that date in the calendar is therefore not a change, the binding's
    /// setter never runs, and `date` stays `nil` — the field closes still saying "Choose your date of birth".
    /// Which is exactly what was observed: the newest selectable day could not be selected, while any other day
    /// could. Somebody whose sixteenth birthday is today was refused by a picker that displayed their birthday
    /// as available.
    ///
    /// Writing `chosen.wrappedValue` through explicitly is what turns the *displayed* date into a *chosen* one,
    /// so the boundary case commits like every other. It also gives the sheet the ordinary "I have finished"
    /// affordance it lacked: closing was only possible through the X, which reads as cancelling.
    private var done: some View {
        HWButton("component.date.done", appearance: .brand, systemImage: "checkmark") {
            date = chosen.wrappedValue
            isChoosing = false
        }
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
