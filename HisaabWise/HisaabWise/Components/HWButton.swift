import SwiftUI

/// One of the design's `.btn` variants.
///
/// Converted, not re-picked: these come from the design's own stylesheets — `.btn-primary`, `.btn-soft`,
/// `.btn-ghost`, `.btn-quiet`, and Expenses' `.addline` — and nothing else. A screen that needs another
/// adds it *here*, with the design rule beside it, rather than inlining a one-off. ``dashed`` is the
/// worked example of that rule being followed rather than described.
///
/// **The destructive shape arrived with Account** (#23) — see ``destructive``, and read it for the half of the
/// design's danger vocabulary that is still not here and why.
enum HWButtonVariant: Sendable, Equatable, CaseIterable {
    /// `.btn-primary` — the galaxy→planetary gradient, raised. One per screen, at most.
    case primary
    /// `.btn-soft` — a card-coloured button with a border. The secondary action beside a primary one.
    case soft
    /// `.btn-ghost` — tinted rather than filled, no elevation. The design spells this variant on the
    /// `brand` surface (`rgba(sky,.07)` over galaxy); on `surface` its twin is the tinted control the
    /// design uses for `.dial` and `.opt-chip`, which is what the tokens below resolve to.
    case ghost
    /// `.btn-quiet` — no fill at all, a hairline border, secondary ink. The lowest-emphasis affordance
    /// the design has.
    case quiet

    /// `.addline` — a **dashed** outline saying "there could be another one of these".
    ///
    /// The fifth shape, added because Expenses needed it (#18) rather than described in advance. The dash is
    /// the whole point: `border:1.5px dashed var(--line-2)` marks a control that *creates* a row in a list it
    /// sits under, as distinct from `.btn-quiet`'s solid hairline, which acts on what is already there. The
    /// design uses it in exactly one place — "Add another bill" inside Utilities' edit mode.
    case dashed

    /// `.logout` — the way out of the app, and the sixth shape: **card-coloured, with a danger border and
    /// danger ink** (#23).
    ///
    /// `background:var(--card);border:1px solid rgba(192,69,58,.3);color:var(--danger)`, with the small
    /// elevation. Not a filled red control: it is the only destructive action on a settings screen, it sits at
    /// the bottom under four ordinary rows, and the design draws it restrained on purpose — the *confirmation*
    /// is where the colour arrives.
    ///
    /// **The design's other danger control, `.btn-danger`, is still not here, and that is not an omission.**
    /// It is the filled red gradient on the log-out confirmation dialog, and that confirmation is a
    /// `confirmationDialog` rather than the design's own `.confirm` overlay (see ``LogoutControl``) — so its
    /// destructive button is the platform's red, drawn by the system, and a variant transcribing the design's
    /// gradient would have nowhere to be used. It arrives when something needs a filled destructive control
    /// that is not a system alert, which is the rule that kept *this* case out until Account had a caller.
    case destructive
}

/// What paints behind a button.
///
/// A small enum rather than an `AnyShapeStyle` so the appearance stays `Equatable` — "only primary is a
/// gradient" is then something a test states rather than something a reviewer looks for.
enum HWButtonFill: Sendable, Equatable {
    /// Two stops on the diagonal, as `linear-gradient(112deg, …)` draws it.
    ///
    /// The unit points are **not** mirrored under RTL, and deliberately are not chased: a 112° wash
    /// between two blues carries no direction to read, unlike an arrow or a chevron.
    case gradient(Color, Color)
    case flat(Color)
    /// `background:none`. `Color.clear` is the absence of a colour rather than a value, so there is
    /// nothing here for a palette swap to reach.
    case unfilled

    var shapeStyle: AnyShapeStyle {
        switch self {
        case .gradient(let start, let end):
            AnyShapeStyle(
                LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        case .flat(let colour):
            AnyShapeStyle(colour)
        case .unfilled:
            AnyShapeStyle(Color.clear)
        }
    }
}

/// One variant resolved against the palette.
///
/// Pulled out of `body` as a value for the same reason ``StatePresentation`` is: it makes "the four
/// variants are visually distinct" and "there is one disabled treatment" facts a test can assert rather
/// than pixels a reviewer has to eyeball.
struct HWButtonAppearance: Sendable, Equatable {
    let fill: HWButtonFill
    let foreground: Color
    /// `nil` where the design draws no border.
    let border: Color?
    /// The dash pattern, or `nil` for a solid stroke. Only ``HWButtonVariant/dashed`` has one, which is what
    /// makes "the dash belongs to exactly one variant" a fact `HWButtonTests` states rather than a reviewer
    /// checks.
    let borderDash: [CGFloat]?
    /// `nil` where the design draws the control flat on the page.
    let elevation: HWShadow?
    let radius: HWRadius

    init(variant: HWButtonVariant, appearance: HWAppearance = .surface, palette: HWPalette) {
        // Solid unless the one variant that is not says otherwise, set once so every arm below does not have
        // to repeat `nil`.
        borderDash = variant == .dashed ? HWBorderDash.standard : nil

        // The design's brand buttons are pills — `border-radius:29px` on a 58pt control, `30` on the
        // landing CTA's 60 — where the in-app ones use the 18pt card radius. Half my height is what a pill
        // radius means, so it is the `pill` token rather than a number (ADR-0021).
        radius = appearance == .brand ? .pill : .large

        switch (appearance, variant) {
        case (.surface, .primary):
            // `linear-gradient(112deg,var(--galaxy),var(--planetary))`, `color:var(--milky)`.
            fill = .gradient(palette.accent.deep, palette.accent.base)
            foreground = palette.brand.ink
            border = nil
            elevation = .medium
        case (.surface, .soft):
            // `background:var(--card);border:1px solid var(--line-2);color:var(--planetary)`.
            fill = .flat(palette.surface.raised)
            foreground = palette.accent.base
            border = palette.surface.separatorStrong
            elevation = .small
        case (.surface, .ghost):
            // The tinted control: `background:var(--tint)` with the hairline border.
            fill = .flat(palette.accent.tint)
            foreground = palette.accent.base
            border = palette.surface.separator
            elevation = nil
        case (.surface, .quiet):
            // `background:none;border:1px solid var(--border);color:var(--muted)`.
            fill = .unfilled
            foreground = palette.surface.inkSecondary
            border = palette.surface.separator
            elevation = nil
        case (.surface, .dashed):
            // `.addline{background:none;border:1.5px dashed var(--line-2);color:var(--planetary)}` — no fill,
            // the *strong* hairline rather than `.btn-quiet`'s light one, and accent ink rather than secondary:
            // it creates a row, so it reads as an action and not as a way out.
            fill = .unfilled
            foreground = palette.accent.base
            border = palette.surface.separatorStrong
            elevation = nil
        case (.surface, .destructive):
            // `.logout{background:var(--card);border:1px solid rgba(192,69,58,.3);color:var(--danger);
            // box-shadow:var(--shadow-s)}` — the card fill and the small lift of `.btn-soft`, with danger in
            // place of accent in both the border and the ink.
            //
            // The border is `dangerSoft` rather than `danger` at 30%: the palette holds the design's own
            // `--danger-soft` token, which is that same red at a tenth — a hairline the ink can be read
            // against without a second red in the asset catalogue whose only job is to be a border
            // (`ColorAssetTests`).
            fill = .flat(palette.surface.raised)
            foreground = palette.feedback.danger
            border = palette.feedback.dangerSoft
            elevation = .small

        case (.brand, .primary):
            // `linear-gradient(100deg,var(--milky),var(--meteor) 48%,var(--milky));color:var(--galaxy)` —
            // the light control on the dark ground, and the same values the landing `.cta` carries.
            //
            // **Three stops become two.** The design's first and last stops are the same colour; the middle
            // one is what its `sweep` animation slides across. Two stops keep the wash and drop the sheen,
            // which is ambient decoration rather than information.
            //
            // The middle stop is `--meteor`, which lives in the palette as a *surface* background role. The
            // design paints a light ground colour on the dark surface here, exactly as it does for the
            // wordmark tile (see ``HWMark``), so the role reads oddly and is right.
            fill = .gradient(palette.brand.ink, palette.surface.backgroundSecondary)
            foreground = palette.brand.background
            border = nil
            // No shadow on the control itself: the design puts a blurred `--sky` glow *behind* it, which is
            // the screen's to draw because it sits outside the button's own bounds.
            elevation = nil
        // **Two variants, one treatment, deliberately.** `.btn-ghost` is the variant the design spells on
        // `brand` and nowhere else — the `surface` twin above is the adaptation, not the original — and the
        // design has **no `.btn-soft` on brand** at all: its secondary filled control there *is* the ghost.
        // Folded into one arm rather than duplicated, so the collapse is visible instead of looking like two
        // rows that happen to agree. `HWButtonTests` states the same thing as an exception to "no two
        // variants draw alike", which holds on `surface` and cannot on `brand`.
        case (.brand, .ghost), (.brand, .soft):
            // `background:rgba(sky,.07);border:1px solid var(--border-lit);color:var(--sky)`.
            fill = .flat(palette.brand.raised)
            foreground = palette.brand.inkAccent
            border = palette.brand.separatorStrong
            elevation = nil
        case (.brand, .quiet):
            // `background:none;border:1px solid var(--border);color:var(--muted)`.
            fill = .unfilled
            foreground = palette.brand.inkSecondary
            border = palette.brand.separator
            elevation = nil
        case (.brand, .dashed):
            // **The design has no dashed control on the galaxy ground**, so this is the surface rule read
            // through the brand tokens rather than a transcription: the strong lit border and the accent ink.
            // Written out rather than folded in with `quiet` because the two differ — the dash and the ink —
            // and folding them would say the design collapses them, which it does not.
            fill = .unfilled
            foreground = palette.brand.inkAccent
            border = palette.brand.separatorStrong
            elevation = nil
        case (.brand, .destructive):
            // **The design has no destructive control on the galaxy ground either** — the only two are Account's
            // `.logout` and its confirmation, both on `surface`. So this is the surface rule read through the
            // brand tokens, exactly as `(.brand, .dashed)` is: the brand's own danger value (which is a *different
            // colour* from the surface's — `#FFC9C0` against `#C0453A`, ADR-0021's clearest evidence that these
            // are two surfaces) as both ink and hairline.
            fill = .flat(palette.brand.raised)
            foreground = palette.brand.danger
            border = palette.brand.danger
            elevation = nil
        }
    }

}

/// Whether a button can be pressed, and if not, why.
///
/// The design has two non-ready treatments and they are different things: `.btn[disabled]` dims **and**
/// drops its shadow, `.btn.loading` swaps the label for a spinner and keeps both. Naming them here is
/// what stops a screen inventing a third, or showing a dimmed spinner because it conflated them.
enum HWButtonState: Sendable, Equatable, CaseIterable {
    case ready
    /// The action is not available. Dimmed, flattened, and not hittable.
    case disabled
    /// The action is available but already running. The label is replaced by a spinner; the control keeps
    /// its opacity and its elevation, because a busy control is not an unavailable one.
    case inFlight

    var isReady: Bool { self == .ready }

    /// `.btn[disabled]{opacity:.45}`.
    var opacity: Double { self == .disabled ? 0.45 : 1 }

    /// `.btn[disabled]{box-shadow:none}` — and only `[disabled]`. A dimmed control that still cast a
    /// shadow would read as available.
    var keepsElevation: Bool { self != .disabled }

    var showsProgress: Bool { self == .inFlight }
}

/// The design's `.btn`, in its four variants and its three states.
///
/// Takes a title, a variant, a state, and a closure. It holds no view model and cannot fetch — the
/// caller decides when ``HWButtonState/inFlight`` starts and stops, because only the caller knows what is
/// in flight.
///
/// Accessibility arrives with the component (ADR-0012): the title is the VoiceOver label, the in-flight
/// spinner is announced as a *value* since a `ProgressView` reaches VoiceOver silently, and the control
/// grows with Dynamic Type instead of clipping — the design's fixed 50–58px height becomes a minimum.
struct HWButton: View {
    @Environment(ThemeManager.self) private var theme

    private let title: LocalizedStringResource
    private let variant: HWButtonVariant
    private let appearance: HWAppearance
    private let systemImage: String?
    private let state: HWButtonState
    private let action: () -> Void

    /// - Parameter appearance: which of the design's two surfaces this button sits on (ADR-0021). Defaults to
    ///   `surface`, the five in-app screens; Landing and Auth pass `brand` at the call site, where a reviewer
    ///   can see it, rather than the control inferring it from the environment.
    init(
        _ title: LocalizedStringResource,
        variant: HWButtonVariant = .primary,
        appearance: HWAppearance = .surface,
        systemImage: String? = nil,
        state: HWButtonState = .ready,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.appearance = appearance
        self.systemImage = systemImage
        self.state = state
        self.action = action
    }

    /// The design's `.btn` heights are 50, 54, and 58 across the six documents — one cluster, collapsed.
    /// A **minimum** rather than a height, so AX5 text grows the control instead of being cut off.
    static let minimumHeight: CGFloat = 52

    var body: some View {
        Button(action: action) {
            HWButtonFace(
                title,
                variant: variant,
                appearance: appearance,
                systemImage: systemImage,
                state: state
            )
        }
        .buttonStyle(HWPressStyle())
        .disabled(!state.isReady)
        .opacity(state.opacity)
        .accessibilityLabel(Text(title))
        .accessibilityValue(state.accessibilityValue)
    }
}

/// The button's **face** — everything it looks like, with nothing that makes it a control.
///
/// Split out with Account (#23) for the reason ``HWRowLabel`` was: `ShareLink` is a control of its own, and a
/// `Button` inside it is two controls for one action. So the export link wears this and the framework supplies the
/// behaviour, which is the same trade `HWMonthRowLabel` makes inside a `NavigationLink`.
///
/// It is not a second button. It has no action, no `.disabled`, and no accessibility of its own: whatever wraps it
/// owns all three, and ``HWButton`` is what wraps it almost everywhere.
struct HWButtonFace: View {
    @Environment(ThemeManager.self) private var theme

    private let title: LocalizedStringResource
    private let variant: HWButtonVariant
    private let appearance: HWAppearance
    private let systemImage: String?
    private let state: HWButtonState

    init(
        _ title: LocalizedStringResource,
        variant: HWButtonVariant = .primary,
        appearance: HWAppearance = .surface,
        systemImage: String? = nil,
        state: HWButtonState = .ready
    ) {
        self.title = title
        self.variant = variant
        self.appearance = appearance
        self.systemImage = systemImage
        self.state = state
    }

    var body: some View {
        let resolved = HWButtonAppearance(variant: variant, appearance: appearance, palette: theme.palette)

        HWButtonLabel(state: state, foreground: resolved.foreground) {
            label(resolved)
        }
        .frame(maxWidth: .infinity, minHeight: HWButton.minimumHeight)
        .padding(.horizontal, 16)
        .hwBox(
            fill: resolved.fill.shapeStyle,
            radius: resolved.radius,
            border: resolved.border,
            borderWidth: resolved.borderDash == nil ? 1 : 1.5,
            borderDash: resolved.borderDash,
            elevation: state.keepsElevation ? resolved.elevation : nil
        )
        .contentShape(.rect)
    }

    private func label(_ resolved: HWButtonAppearance) -> some View {
        HStack(spacing: 9) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.hw(.bodyLarge).weight(.heavy))
        .foregroundStyle(resolved.foreground)
        .multilineTextAlignment(.center)
        // Wraps rather than truncating once the text outgrows one line.
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension HWButtonState {
    /// A `ProgressView` reaches VoiceOver silently, so the busy state is spoken as the control's value.
    /// Empty when there is nothing in flight — an unconditional value would be read on every button.
    var accessibilityValue: Text {
        showsProgress ? Text(HWComponentCopy.inFlight) : Text(verbatim: "")
    }
}

/// The label-or-spinner swap `.btn.loading` performs, for whichever button is performing it.
///
/// Held in a `ZStack` rather than switched, so the button does not resize under its own spinner —
/// `.btn.loading .lbl{opacity:0}` keeps the label's space for exactly that reason.
struct HWButtonLabel<Label: View>: View {
    let state: HWButtonState
    let foreground: Color
    @ViewBuilder let label: () -> Label

    var body: some View {
        ZStack {
            label().opacity(state.showsProgress ? 0 : 1)

            if state.showsProgress {
                ProgressView().tint(foreground)
            }
        }
    }
}

/// How much weight an icon-only control carries.
///
/// The design draws three, and they are three different jobs rather than three sizes. Collapsing them is what
/// review caught in the running screen: every logged entry had a **raised, bordered, accent-blue** cross beside it,
/// which read as the most important thing in the row when it is the least.
enum HWIconButtonVariant: Sendable, Equatable, CaseIterable {
    /// `.iconbtn` — a card-coloured square with a hairline border and a small elevation. A back affordance, a
    /// sheet's close button: a control that stands on its own.
    case raised

    /// `.entry-del` — no fill, no border, no elevation, tertiary ink. A control that belongs *to* a row and must
    /// not compete with what the row says. `:hover{background:rgba(danger,.1);color:var(--danger)}` in the design,
    /// which on a phone is only ever the pressed state — so what ships is the resting form.
    case quiet

    /// `.line-del` — a danger-tinted square with danger ink. Removing a *named* thing, where the design makes the
    /// consequence visible because there is nothing to undo it with.
    case destructive
}

/// The design's icon-only buttons — `.iconbtn`, `.entry-del`, and `.line-del`.
///
/// Icon-only, so `label` is not decoration: it is the entire VoiceOver reading of the control. It is
/// therefore required rather than optional.
struct HWIconButton: View {
    @Environment(ThemeManager.self) private var theme

    private let label: LocalizedStringResource
    private let systemImage: String
    private let state: HWButtonState
    /// Which surface it sits on (ADR-0021). The design's `.sheet-x` is drawn on both grounds — the auth sheet's
    /// galaxy panel and the in-app sheets' light one — so the close button that comes with the chrome has to
    /// follow the chrome.
    private let appearance: HWAppearance
    private let variant: HWIconButtonVariant
    private let action: () -> Void

    init(
        _ label: LocalizedStringResource,
        systemImage: String,
        state: HWButtonState = .ready,
        appearance: HWAppearance = .surface,
        variant: HWIconButtonVariant = .raised,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.state = state
        self.appearance = appearance
        self.variant = variant
        self.action = action
    }

    /// `.sheet-x{color:var(--muted)}` on brand, planetary on surface; tertiary for the quiet form and danger for
    /// the destructive one.
    private var ink: Color {
        switch variant {
        case .raised: appearance == .brand ? theme.palette.brand.inkSecondary : theme.palette.accent.base
        case .quiet: theme.palette.surface.inkTertiary
        case .destructive: theme.palette.feedback.danger
        }
    }

    private var fill: Color {
        switch variant {
        case .raised: appearance == .brand ? theme.palette.brand.raised : theme.palette.surface.raised
        // `background:transparent` — the row it sits in is what the user sees.
        case .quiet: Color.clear
        // `background:rgba(danger,.10)`.
        case .destructive: theme.palette.feedback.dangerSoft
        }
    }

    /// Only the raised form is bordered; the other two are defined by their ink and their fill.
    private var border: Color? {
        guard variant == .raised else { return nil }
        return appearance == .brand ? theme.palette.brand.separator : theme.palette.surface.separator
    }

    /// And only the raised form is lifted off the page.
    private var elevation: HWShadow? {
        guard variant == .raised, state.keepsElevation else { return nil }
        return .small
    }

    /// The glyph's own size. The design draws `.iconbtn svg` at 18 and the two row affordances at 13–14, so the
    /// quiet and destructive forms keep a *smaller drawing* inside the same 44pt target: the target grows for
    /// ADR-0012 and the drawing stays the design's.
    private var glyph: HWTextStyle {
        variant == .raised ? .subheading : .body
    }

    var body: some View {
        Button(action: action) {
            HWButtonLabel(state: state, foreground: ink) {
                Image(systemName: systemImage)
                    .font(.hw(glyph).weight(.bold))
                    .foregroundStyle(ink)
            }
            // The design draws these at 40×40 and 28×28; `HWTouchTarget` explains why both are 44 here.
            .frame(minWidth: HWTouchTarget.minimum, minHeight: HWTouchTarget.minimum)
            .hwBox(fill: fill, radius: .medium, border: border, elevation: elevation)
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        .disabled(!state.isReady)
        .opacity(state.opacity)
        .accessibilityLabel(Text(label))
        .accessibilityValue(state.accessibilityValue)
    }
}

/// The design's `.editbtn` — the pill that turns a screen's edit mode on and reads "Done" while it is.
///
/// A toggle rather than a button: `.editbtn.on` inverts to the galaxy fill, which is a *state* of one
/// control and not a second control. The caller supplies both the title and `isOn`, because which word
/// goes with which state is the screen's copy (`.txt-edit` / `.txt-done`).
///
/// It carries the same ``HWButtonState`` as the other two forms, because saving an edit is exactly where a
/// screen would otherwise invent an in-flight treatment of its own.
struct HWEditButton: View {
    @Environment(ThemeManager.self) private var theme

    private let title: LocalizedStringResource
    private let systemImage: String?
    private let isOn: Bool
    private let state: HWButtonState
    private let action: () -> Void

    init(
        _ title: LocalizedStringResource,
        systemImage: String? = nil,
        isOn: Bool,
        state: HWButtonState = .ready,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        self.state = state
        self.action = action
    }

    /// `.editbtn.on{background:var(--galaxy);color:var(--milky)}`
    private var foreground: Color {
        isOn ? theme.palette.brand.ink : theme.palette.accent.base
    }

    var body: some View {
        Button(action: action) {
            HWButtonLabel(state: state, foreground: foreground) {
                HStack(spacing: 7) {
                    if let systemImage {
                        Image(systemName: systemImage)
                    }
                    Text(title)
                }
                .font(.hw(.body).weight(.bold))
                .foregroundStyle(foreground)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: HWTouchTarget.minimum)
            .hwBox(
                fill: isOn ? theme.palette.accent.deep : theme.palette.surface.raised,
                radius: .medium,
                border: isOn ? theme.palette.accent.deep : theme.palette.surface.separatorStrong,
                elevation: state.keepsElevation ? (isOn ? .medium : .small) : nil
            )
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        .disabled(!state.isReady)
        .opacity(state.opacity)
        .accessibilityLabel(Text(title))
        .accessibilityValue(state.accessibilityValue)
        // A toggle, so VoiceOver should say which way it is set rather than relying on the inverted fill.
        .hwSelectionTraits(isSelected: isOn)
    }
}

#if DEBUG
#Preview("Buttons — every variant, every state") {
    ScrollView {
        VStack(spacing: 14) {
            ForEach(HWButtonVariant.allCases, id: \.self) { variant in
                ForEach(HWButtonState.allCases, id: \.self) { state in
                    HWButton("Log an expense", variant: variant, systemImage: "plus", state: state) {}
                }
            }
        }
        .padding()
    }
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("Icon and edit forms, in every state") {
    VStack(spacing: 14) {
        HStack(spacing: 12) {
            ForEach(HWIconButtonVariant.allCases, id: \.self) { variant in
                HWIconButton("Remove", systemImage: "xmark", variant: variant) {}
            }
        }

        ForEach(HWButtonState.allCases, id: \.self) { state in
            HStack(spacing: 12) {
                HWIconButton("Go back", systemImage: "chevron.backward", state: state) {}
                HWEditButton("Edit", systemImage: "pencil", isOn: false, state: state) {}
                HWEditButton("Done", systemImage: "checkmark", isOn: true, state: state) {}
            }
        }
    }
    .padding()
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — the height is a minimum, not a height") {
    VStack(spacing: 14) {
        HWButton("Log an expense", systemImage: "plus") {}
        HWButton("Not now", variant: .quiet) {}
        HWEditButton("Edit", systemImage: "pencil", isOn: false) {}
    }
    .padding()
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("RTL — the label and the icon mirror") {
    VStack(spacing: 14) {
        HWButton("سجل مصروفاً", systemImage: "plus") {}
        HWButton("ليس الآن", variant: .soft, systemImage: "clock") {}
        HWIconButton("رجوع", systemImage: "chevron.backward") {}
    }
    .padding()
    .environment(\.layoutDirection, .rightToLeft)
    .background(HWPreviewGround())
    .hwTheme()
}
#endif
