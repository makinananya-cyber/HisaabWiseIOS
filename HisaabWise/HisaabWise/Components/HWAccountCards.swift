import SwiftUI

/// The design's `.profile` — the galaxy card at the top of Account, with the initials avatar, the name, the
/// address, and the one-line summary chip.
///
/// **The one `brand`-coloured card on a `surface` screen**, and it is the design's own doing:
/// `background:linear-gradient(145deg,var(--galaxy),#123273 55%,var(--planetary))` with `color:var(--milky)`
/// inside. Not an appearance switch — the card is *drawn* in the brand palette the way `HWSpendSummary`'s
/// galaxy summary is on Expenses, while the screen around it stays light (ADR-0021).
///
/// **The middle gradient stop is dropped.** `#123273` is a value between `--galaxy` and `--planetary` and is
/// not a token; the palette holds the two ends, and two stops of the same wash is what `HWButtonAppearance`
/// already does with the design's three-stop primary. Adding a colour set whose only job is to sit in the
/// middle of another gradient is what `ColorAssetTests` exists to prevent.
///
/// Three of the design's flourishes are **dropped rather than gated** under Reduce Motion, on the reasoning
/// the `START` flag's bob carries (ADR-0012): the `::after` orb drifting behind the card, the avatar's `pop`
/// entrance, and the ring pulsing around it are decoration whose only honest replacement is the card already
/// being there. The chip's pinging dot goes with them — a dot that pulses to mean nothing is an attention loop
/// with nothing to attend to, and what the chip says is in its words.
struct HWProfileHeader: View {
    @Environment(ThemeManager.self) private var theme

    /// `.avatar` — "AM". **The server's**, because initials are a question about a writing system: read
    /// `AccountScreen.Profile.initials`.
    private let initials: String
    /// `.pro-name`. Server content — the user typed it.
    private let name: String
    /// `.pro-mail` — the identity (invariant 4).
    private let email: String
    /// `.pro-chip` — "INR · English", as **one** server string rather than two joined (ADR-0011).
    private let summary: String

    init(initials: String, name: String, email: String, summary: String) {
        self.initials = initials
        self.name = name
        self.email = email
        self.summary = summary
    }

    /// `.avatar{width:60px;height:60px}` — a **minimum**, so the tile grows with the letter inside it rather
    /// than clipping it at AX5.
    private static let avatarSize: CGFloat = 60

    var body: some View {
        HStack(spacing: 15) {
            avatar

            VStack(alignment: .leading, spacing: 3) {
                // `.pro-name` truncates in the design (`text-overflow:ellipsis`). It wraps here, for the reason
                // `HWBackBar`'s title does: cutting off the thing that says whose account this is is worse than
                // a taller card.
                Text(verbatim: name)
                    .font(.hw(.subheading).weight(.heavy))
                    .foregroundStyle(theme.palette.brand.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: email)
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.brand.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                chip
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .hwBox(
            fill: LinearGradient(
                colors: [theme.palette.brand.backgroundDeep, theme.palette.accent.base],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            radius: .extraLarge,
            elevation: .large
        )
        // The avatar restates the name beside it, so the card reads as one element: the name, the address, and
        // the summary in one swipe. Three stops for one card is the focus-order failure ADR-0012 is about.
        .accessibilityElement(children: .combine)
    }

    /// `.avatar{background:linear-gradient(150deg,var(--sky),var(--venus));color:var(--galaxy)}`
    private var avatar: some View {
        Text(verbatim: initials)
            .font(.hw(.subheading).weight(.heavy))
            .foregroundStyle(theme.palette.brand.background)
            .frame(minWidth: Self.avatarSize, minHeight: Self.avatarSize)
            .padding(4)
            .hwBox(
                fill: LinearGradient(
                    colors: [theme.palette.accent.soft, theme.palette.accent.tintSecondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                radius: .large
            )
            // A pair of letters standing in for the name that is read out immediately after it.
            .accessibilityHidden(true)
    }

    /// `.pro-chip` — a lit hairline pill on the galaxy ground.
    private var chip: some View {
        Text(verbatim: summary)
            .font(.hw(.micro).weight(.bold))
            .foregroundStyle(theme.palette.brand.inkAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .hwBox(fill: theme.palette.brand.raised, radius: .small, border: theme.palette.brand.separator)
    }
}

/// The design's `.bubble` — the tinted tray the four settings rows sit in.
///
/// A container rather than a card: `background:linear-gradient(180deg,rgba(sky,.62),rgba(venus,.34))` with a
/// hairline and an 8px inset, which is a *group* of rows rather than a surface with content on it. Distinct
/// from ``HWCard`` in exactly that way — a card holds one thing, and this holds a list of things each of which
/// is already a raised row.
struct HWSettingsTray<Content: View>: View {
    @Environment(ThemeManager.self) private var theme

    /// `.bubble-cap` — "Your account".
    private let caption: LocalizedStringResource
    private let content: Content

    init(caption: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption)
                .hwEyebrow()
                .padding(.horizontal, 8)
                .padding(.top, 4)

            content
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hwBox(
            fill: LinearGradient(
                colors: [theme.palette.accent.soft, theme.palette.accent.tintSecondary],
                startPoint: .top,
                endPoint: .bottom
            ),
            radius: .extraLarge,
            border: theme.palette.surface.separator
        )
        // One container, so VoiceOver's container gestures move between the tray and what surrounds it rather
        // than through four rows.
        .accessibilityElement(children: .contain)
    }
}

/// The design's `.card{padding:6px}` — a card that holds **full-width rows** rather than inset content.
///
/// Distinct from ``HWCard``, whose `padding:18px 16px` is the same class on every other screen. The difference
/// is what is inside: `HWCard` holds content that needs a margin, and this holds rows that carry their own
/// padding and whose hairline separators have to reach both edges. Insetting them by sixteen more points would
/// draw a separator that stops short of the border, which is the one thing a separator must not do.
///
/// A second component rather than an inset parameter on ``HWCard``, because the choice is not a spacing
/// preference: it follows from whether the caller's content is rows. A parameter would let any of the eleven
/// existing callers pick the wrong one.
struct HWRowCard<Content: View>: View {
    @Environment(ThemeManager.self) private var theme

    /// `.card-cap` — "Personal information". `nil` for a card whose rows say what they are.
    private let caption: LocalizedStringResource?
    private let content: Content

    init(caption: LocalizedStringResource? = nil, @ViewBuilder content: () -> Content) {
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let caption {
                Text(caption)
                    .hwEyebrow()
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }

            content
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hwBox(
            fill: theme.palette.surface.raised,
            radius: .extraLarge,
            border: theme.palette.surface.separator,
            elevation: .small
        )
        // One container per card, as ``HWCard`` does: VoiceOver reads a card as a card rather than as loose rows.
        .accessibilityElement(children: .contain)
    }
}

/// One line of the design's `.info` card — a label, and either a value or the control that edits it.
///
/// The Personal Information page is four of these, and what makes it worth a component is that each line
/// switches between two renderings of the same row: `.info-val` when the card is at rest and an `input` when
/// it is being edited. A screen that inlined both would draw the label twice.
///
/// **The value slot is a `ViewBuilder`**, because in edit mode it holds a *control* — a field, a money field, a
/// phone field — and a component that took one as data would be picking which control (the reason
/// ``HWTopBar``'s trailing slot is one).
struct HWInfoRow<Value: View>: View {
    @Environment(ThemeManager.self) private var theme

    /// `.info-lab` — "Username", "Salary". Always app copy: a field's name is never a server string.
    private let label: LocalizedStringResource
    /// Whether a hairline separates this row from the one above it — `.info + .info{box-shadow:inset 0 1px 0}`.
    private let isSeparated: Bool
    private let value: Value

    init(_ label: LocalizedStringResource, isSeparated: Bool = true, @ViewBuilder value: () -> Value) {
        self.label = label
        self.isSeparated = isSeparated
        self.value = value()
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSeparated {
                Divider().overlay(theme.palette.surface.separator)
            }

            // **A `VStack` at accessibility sizes and an `HStack` below them.** The design's row is a label at
            // one edge and a value at the other, which at AX5 leaves each about half a phone's width; stacking
            // them gives the value the whole line. `ViewThatFits` rather than a size check, so the switch happens
            // when the content needs it rather than at a threshold somebody picked (ADR-0012).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    caption
                    value.frame(maxWidth: .infinity, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 7) {
                    caption
                    value.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
    }

    private var caption: some View {
        Text(label)
            .font(.hw(.caption).weight(.bold))
            .foregroundStyle(theme.palette.surface.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The design's `.info-val`, and its `.locked` variant with the padlock beside it.
///
/// Two renderings of one thing, so that "the email is locked" is a *value* the row is given rather than a
/// second row somebody wrote. The padlock is `.info-lock`, and it is decoration: what tells a screen-reader
/// user the field cannot be edited is the ``HWInfoNote`` under it, which is a sentence.
struct HWInfoValue: View {
    @Environment(ThemeManager.self) private var theme

    private let text: String
    /// `.info-val.locked{color:var(--ink-2)}` plus the padlock — the email (invariant 4).
    private let isLocked: Bool
    /// A trailing unit the design sets smaller and greyer — Salary's `/mo`.
    private let unit: LocalizedStringResource?

    init(_ text: String, isLocked: Bool = false, unit: LocalizedStringResource? = nil) {
        self.text = text
        self.isLocked = isLocked
        self.unit = unit
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: text)
                .font(.hw(.body).weight(.bold))
                .foregroundStyle(isLocked ? theme.palette.surface.inkSecondary : theme.palette.surface.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)

            if let unit {
                Text(unit)
                    .font(.hw(.micro).weight(.bold))
                    .foregroundStyle(theme.palette.surface.inkTertiary)
            }

            if isLocked {
                Image(systemName: "lock")
                    .font(.hw(.caption).weight(.bold))
                    .foregroundStyle(theme.palette.surface.inkTertiary)
                    // The sentence under the row is what says why, and a glyph that repeated it would be read
                    // before the explanation rather than instead of it.
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The design's `.info input` — an **underlined inline field**, trailing-aligned, inside a row that already has
/// a border.
///
/// Not ``HWTextField``, and the difference is the design's: `.info input` is
/// `background:none;border:0;border-bottom:1.5px solid var(--line-2);text-align:right`, sitting in a card whose
/// rows are separated by hairlines. `HWTextField` is `.field-box` — a filled, fully bordered box with its own
/// label above it, which is registration's shape. Drawing a box inside a row inside a card is three borders for
/// one field, and the design draws one.
///
/// It carries the salary's `.money-wrap .cur` symbol too, because that is the same row with a prefix rather than
/// a second control: ``HWMoneyField`` is the *prominent* form on its own line (`HWMoneyProminence`), and a
/// 28-point figure has nowhere to go inside a 14-point row.
struct HWInlineField: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    /// VoiceOver's reading. **Required**, because the visible label belongs to the ``HWInfoRow`` around this and
    /// a field with no label of its own reaches a screen reader as "text field".
    private let label: LocalizedStringResource
    @Binding private var text: String
    /// `.money-wrap .cur` — `₹`, `AED`. Decoration around a number being typed, never formatting (ADR-0003).
    private let symbol: String?
    private let keyboardType: UIKeyboardType
    private let textContentType: UITextContentType?
    /// `.info.bad` — the underline turns danger. The *message* is the caller's, drawn under the card.
    private let isInvalid: Bool

    init(
        _ label: LocalizedStringResource,
        text: Binding<String>,
        symbol: String? = nil,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        isInvalid: Bool = false
    ) {
        self.label = label
        self._text = text
        self.symbol = symbol
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.isInvalid = isInvalid
    }

    /// `.info input{border-bottom:1.5px solid}`.
    private static let underlineHeight: CGFloat = 1.5

    /// `border-bottom-color:var(--universe)` on focus, `--line-2` at rest, danger when the row is bad.
    private var underline: Color {
        if isInvalid { return theme.palette.feedback.danger }
        return isFocused ? theme.palette.accent.muted : theme.palette.surface.separatorStrong
    }

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Text(verbatim: symbol)
                    .font(.hw(.body).weight(.heavy))
                    .foregroundStyle(theme.palette.accent.base)
                    // The currency is spoken as part of the field's value, not as an element beside it.
                    .accessibilityHidden(true)
            }

            TextField(text: $text) { Text(verbatim: "") }
                .textFieldStyle(.plain)
                .font(.hw(.body).weight(.bold))
                .foregroundStyle(theme.palette.surface.ink)
                .tint(theme.palette.accent.base)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                // Never capitalised and never corrected, for the reason `HWTextField` gives: a name and a
                // number are both things iOS would silently edit.
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                // **Trailing in the design (`text-align:right`), and leading here.** A right-aligned field
                // mirrors to *left*-aligned under Arabic — which is what `text-align:right` cannot express and
                // what a `.trailing` multiline alignment would give. The field is the trailing element of its
                // row either way, so the alignment inside it costs nothing and a caret that started on the
                // wrong side of the box would cost the user their place.
                .focused($isFocused)
                .accessibilityLabel(Text(label))
        }
        .frame(maxWidth: 190, alignment: .trailing)
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(underline)
                .frame(height: Self.underlineHeight)
                .accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : HWMotion.easeInOut.animation(.standard), value: isFocused)
        .animation(reduceMotion ? nil : HWMotion.easeInOut.animation(.standard), value: isInvalid)
    }
}

/// The design's `.info-note` — the small print under a row that explains it.
///
/// One caller: the sentence under the locked email. A component rather than an inline `Text` because it is a
/// *role* in the card — the design gives it its own class, its own size, and its own ink — and the next screen
/// with a row that needs explaining should draw it the same way.
struct HWInfoNote: View {
    @Environment(ThemeManager.self) private var theme

    private let message: LocalizedStringResource

    init(_ message: LocalizedStringResource) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.hw(.micro))
            .foregroundStyle(theme.palette.surface.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
    }
}

/// A strip of copy about the state of something, in one of two tones.
///
/// Two callers, which is why it is a component: the shell's "verify your email" reminder above the tabs
/// (ADR-0031) and Account's own beside the locked email — plus the explanation the currency page shows when a
/// change could not be sent. All three are a glyph, a sentence, and a tinted ground, and the shell's was
/// inlined until Account needed the second one.
///
/// **Not a `LoadState`**, and it must not become one: the taxonomy has one owner (`StateView`, ADR-0016). This
/// is a notice *beside* content that is fine, which is precisely the case a `LoadState` cannot express.
struct HWBanner: View {
    @Environment(ThemeManager.self) private var theme

    /// Which of the two tones — informational or a refusal.
    enum Tone: Sendable, Equatable, CaseIterable {
        /// The accent tint. Something the user might want to do, not something that went wrong.
        case informational
        /// The danger tint. Something that did not happen.
        case refusal
    }

    private let message: LocalizedStringResource
    private let systemImage: String
    private let tone: Tone

    init(_ message: LocalizedStringResource, systemImage: String, tone: Tone = .informational) {
        self.message = message
        self.systemImage = systemImage
        self.tone = tone
    }

    private var ink: Color {
        switch tone {
        case .informational: theme.palette.accent.base
        case .refusal: theme.palette.feedback.danger
        }
    }

    private var ground: Color {
        switch tone {
        case .informational: theme.palette.accent.tint
        case .refusal: theme.palette.feedback.dangerSoft
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.hw(.body))
                .foregroundStyle(ink)
                .accessibilityHidden(true)

            Text(message)
                .font(.hw(.caption))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(ground)
        // One element, read as a whole, and **not** a header: a notice is not the title of anything (ADR-0012).
        .accessibilityElement(children: .combine)
    }
}

/// The design's `.dial` — the country-code trigger beside a phone number.
///
/// It exists as its own control because Account's phone row is **not** ``HWPhoneField``: the design draws the
/// registration field as one box with two halves and the Account row as a bare `input` with the dial button
/// floating beside it, inside a card that already has its own border. So the trigger is shared and the box is
/// not — which is the same split ``HWMonthRowLabel`` makes between a row's label and the control around it.
struct HWDialTrigger: View {
    @Environment(ThemeManager.self) private var theme

    /// `.dial-iso` — ISO 3166-1 alpha-2.
    private let countryCode: String
    /// `.dial-code` — `+91`, with the plus.
    private let dialCode: String
    /// VoiceOver's reading, since the two codes alone do not say what pressing it does.
    private let label: LocalizedStringResource
    private let action: () -> Void

    init(
        countryCode: String,
        dialCode: String,
        label: LocalizedStringResource,
        action: @escaping () -> Void
    ) {
        self.countryCode = countryCode
        self.dialCode = dialCode
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(verbatim: countryCode)
                Text(verbatim: dialCode)
                // `chevron.down` carries no reading direction, so nothing to mirror.
                Image(systemName: "chevron.down")
                    .font(.hw(.micro).weight(.heavy))
            }
            .font(.hw(.caption).weight(.heavy))
            .foregroundStyle(theme.palette.accent.base)
            .padding(.horizontal, 9)
            .frame(minHeight: HWTouchTarget.minimum)
            .hwBox(fill: theme.palette.accent.tint, radius: .small, border: theme.palette.surface.separator)
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        // The codes are the control's *value*; what it does is the label. VoiceOver then reads
        // "Change country code, IN +91, button" rather than two codes and no verb.
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: "\(countryCode) \(dialCode)"))
    }
}

#if DEBUG
#Preview("The profile card and the settings tray") {
    ScrollView {
        VStack(spacing: 18) {
            HWProfileHeader(
                initials: "N",
                name: "Neeraj",
                email: "neeraj@example.ae",
                summary: "INR · English"
            )

            HWSettingsTray(caption: "Your account") {
                HWRow(
                    systemImage: "person",
                    name: Text(verbatim: "Personal Information"),
                    subtitle: Text(verbatim: "Username, salary, phone")
                ) {}
                HWRow(
                    systemImage: "globe",
                    name: Text(verbatim: "Language"),
                    subtitle: Text(verbatim: "How the app is written"),
                    value: Text(verbatim: "English")
                ) {}
            }

            HWButton("Log Out", variant: .destructive, systemImage: "rectangle.portrait.and.arrow.forward") {}
        }
        .padding(18)
    }
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("The personal card, at rest and being edited") {
    @Previewable @State var name = "Neeraj"
    @Previewable @State var salary = "65000"
    @Previewable @State var digits = "98765"

    ScrollView {
        VStack(spacing: 18) {
            HWRowCard(caption: "Personal information") {
                HWInfoRow("Username", isSeparated: false) { HWInfoValue("Neeraj") }
                HWInfoRow("Salary") { HWInfoValue("₹65,000", unit: "/mo") }
                HWInfoRow("Email") { HWInfoValue("neeraj@example.ae", isLocked: true) }
                HWInfoNote("This is the address you registered with — it is how we check it is you, so it cannot be changed here.")
                HWInfoRow("Phone") { HWInfoValue("+91 98765 43210") }
            }

            HWRowCard(caption: "Personal information") {
                HWInfoRow("Username", isSeparated: false) {
                    HWInlineField("Username", text: $name, textContentType: .name)
                }
                HWInfoRow("Salary") {
                    HWInlineField("Monthly salary", text: $salary, symbol: "₹", keyboardType: .decimalPad)
                }
                HWInfoRow("Phone") {
                    HStack(spacing: 8) {
                        HWDialTrigger(countryCode: "IN", dialCode: "+91", label: "Change country code") {}
                        HWInlineField("Phone number", text: $digits, keyboardType: .phonePad, isInvalid: true)
                    }
                }
            }

            HWBanner("Confirm your email address to keep your account secure.", systemImage: "envelope.badge")
            HWBanner(
                "A currency change needs a connection. Nothing has changed.",
                systemImage: "wifi.slash",
                tone: .refusal
            )
        }
        .padding(18)
    }
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX5 — the rows stack and the avatar grows") {
    ScrollView {
        VStack(spacing: 18) {
            HWProfileHeader(
                initials: "N",
                name: "Neeraj",
                email: "neeraj@example.ae",
                summary: "INR · English"
            )
            HWRowCard {
                HWInfoRow("Salary", isSeparated: false) { HWInfoValue("₹65,000", unit: "/mo") }
                HWInfoRow("Email") { HWInfoValue("neeraj@example.ae", isLocked: true) }
            }
        }
        .padding(18)
    }
    .dynamicTypeSize(.accessibility5)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("RTL — the card, the tray and the dial mirror") {
    ScrollView {
        VStack(spacing: 18) {
            HWProfileHeader(initials: "ن", name: "نيراج", email: "neeraj@example.ae", summary: "AED · العربية")
            HWSettingsTray(caption: "حسابك") {
                HWRow(
                    systemImage: "globe",
                    name: Text(verbatim: "اللغة"),
                    subtitle: Text(verbatim: "في كل التطبيق"),
                    value: Text(verbatim: "العربية")
                ) {}
            }
            HWDialTrigger(countryCode: "AE", dialCode: "+971", label: "تغيير رمز البلد") {}
        }
        .padding(18)
    }
    .environment(\.layoutDirection, .rightToLeft)
    .background(HWPreviewGround())
    .hwTheme()
}
#endif
