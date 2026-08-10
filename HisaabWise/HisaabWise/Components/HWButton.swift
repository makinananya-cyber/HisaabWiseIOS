import SwiftUI

/// One of the design's four `.btn` variants.
///
/// Converted, not re-picked: these are the four the design's stylesheets carry — `.btn-primary`,
/// `.btn-soft`, `.btn-ghost`, `.btn-quiet` — and nothing else. A screen that needs a fifth adds it
/// *here*, with the design rule beside it, rather than inlining a one-off.
///
/// **The design's destructive button is deliberately not here yet.** `.btn-danger` and Account's
/// `.logout` are a real fifth shape, and they arrive with the Account screen (#17) where there is a
/// caller to shape them — the same reasoning `ScreenChrome` applies to the `brand` appearance.
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
    /// `nil` where the design draws the control flat on the page.
    let elevation: HWShadow?
    let radius: HWRadius

    init(variant: HWButtonVariant, palette: HWPalette) {
        radius = .large
        switch variant {
        case .primary:
            // `linear-gradient(112deg,var(--galaxy),var(--planetary))`, `color:var(--milky)`.
            fill = .gradient(palette.accent.deep, palette.accent.base)
            foreground = palette.brand.ink
            border = nil
            elevation = .medium
        case .soft:
            // `background:var(--card);border:1px solid var(--line-2);color:var(--planetary)`.
            fill = .flat(palette.surface.raised)
            foreground = palette.accent.base
            border = palette.surface.separatorStrong
            elevation = .small
        case .ghost:
            // The tinted control: `background:var(--tint)` with the hairline border.
            fill = .flat(palette.accent.tint)
            foreground = palette.accent.base
            border = palette.surface.separator
            elevation = nil
        case .quiet:
            // `background:none;border:1px solid var(--border);color:var(--muted)`.
            fill = .unfilled
            foreground = palette.surface.inkSecondary
            border = palette.surface.separator
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
    private let systemImage: String?
    private let state: HWButtonState
    private let action: () -> Void

    init(
        _ title: LocalizedStringResource,
        variant: HWButtonVariant = .primary,
        systemImage: String? = nil,
        state: HWButtonState = .ready,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.systemImage = systemImage
        self.state = state
        self.action = action
    }

    /// The design's `.btn` heights are 50, 54, and 58 across the six documents — one cluster, collapsed.
    /// A **minimum** rather than a height, so AX5 text grows the control instead of being cut off.
    static let minimumHeight: CGFloat = 52

    var body: some View {
        let appearance = HWButtonAppearance(variant: variant, palette: theme.palette)

        Button(action: action) {
            HWButtonLabel(state: state, foreground: appearance.foreground) {
                label(appearance)
            }
            .frame(maxWidth: .infinity, minHeight: Self.minimumHeight)
            .padding(.horizontal, 16)
            .hwBox(
                fill: appearance.fill.shapeStyle,
                radius: appearance.radius,
                border: appearance.border,
                elevation: state.keepsElevation ? appearance.elevation : nil
            )
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle())
        .disabled(!state.isReady)
        .opacity(state.opacity)
        .accessibilityLabel(Text(title))
        .accessibilityValue(state.accessibilityValue)
    }

    private func label(_ appearance: HWButtonAppearance) -> some View {
        HStack(spacing: 9) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.hw(.bodyLarge).weight(.heavy))
        .foregroundStyle(appearance.foreground)
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
private struct HWButtonLabel<Label: View>: View {
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

/// The design's `.iconbtn` — a square, card-coloured button carrying one glyph.
///
/// Icon-only, so `label` is not decoration: it is the entire VoiceOver reading of the control. It is
/// therefore required rather than optional.
struct HWIconButton: View {
    @Environment(ThemeManager.self) private var theme

    private let label: LocalizedStringResource
    private let systemImage: String
    private let state: HWButtonState
    private let action: () -> Void

    init(
        _ label: LocalizedStringResource,
        systemImage: String,
        state: HWButtonState = .ready,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.state = state
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HWButtonLabel(state: state, foreground: theme.palette.accent.base) {
                Image(systemName: systemImage)
                    .font(.hw(.subheading))
                    .foregroundStyle(theme.palette.accent.base)
            }
            // The design draws this at 40×40; `HWTouchTarget` explains why it is 44 here.
            .frame(minWidth: HWTouchTarget.minimum, minHeight: HWTouchTarget.minimum)
            .hwBox(
                fill: theme.palette.surface.raised,
                radius: .medium,
                border: theme.palette.surface.separator,
                elevation: state.keepsElevation ? .small : nil
            )
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
