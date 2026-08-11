import SwiftUI

/// The design's `.check` — a box, a tick, and a sentence beside it.
///
/// New to the vocabulary with sign-in (#14), which is where the design first uses one: "Keep me signed in",
/// and it is **checked by default** there, so the caller's initial value carries that rather than this control
/// assuming it.
///
/// **Not a `Toggle`.** SwiftUI's is a switch, and a switch means "this takes effect now"; the design draws a
/// checkbox, which means "this is part of what I am about to submit". The distinction is the whole reason the
/// design has both shapes, so converting one into the other would change what the control says.
///
/// The tick is `Image(systemName: "checkmark")` rather than the design's dashed-stroke SVG: the design animates
/// its `stroke-dashoffset` to draw the tick on, which is a decoration a symbol cannot do — and a hand-rolled
/// path that only existed to be drawn on would be re-picking a glyph to animate it.
struct HWCheckbox: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: LocalizedStringResource
    @Binding private var isOn: Bool
    private let appearance: HWAppearance

    init(_ title: LocalizedStringResource, isOn: Binding<Bool>, appearance: HWAppearance = .surface) {
        self.title = title
        self._isOn = isOn
        self.appearance = appearance
    }

    /// `.box{width:18px;height:18px}`.
    private static let boxSize: CGFloat = 18

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 9) {
                box
                Text(title)
                    .font(.hw(.body))
                    .foregroundStyle(secondaryInk)
                    .multilineTextAlignment(.leading)
                    // Wraps rather than truncating, which at AX5 is the difference between a readable choice
                    // and half a sentence (ADR-0012).
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The design's 18pt box is well under a finger, and the sentence is part of the target: the whole
            // row is the control, raised to 44 (`HWTouchTarget`).
            .frame(minHeight: HWTouchTarget.minimum)
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        // One element that says what it is and whether it is on. `.isSelected` beside `.isButton` is what makes
        // the state audible — the design marks it with colour alone, and colour reaches VoiceOver not at all.
        .accessibilityLabel(Text(title))
        .hwSelectionTraits(isSelected: isOn)
    }

    /// `.box` — a rounded square, filled with `--sky` and carrying a galaxy tick when checked.
    private var box: some View {
        Image(systemName: "checkmark")
            .font(.hw(.micro).weight(.black))
            .foregroundStyle(isOn ? tickInk : .clear)
            .frame(width: Self.boxSize, height: Self.boxSize)
            .hwBox(
                fill: isOn ? accentInk : boxFill,
                radius: .hairline,
                border: isOn ? accentInk : borderInk,
                borderWidth: 1
            )
            // The tick's arrival is a **fill and a glyph**, not a movement: nothing travels, so Reduce Motion
            // has nothing to replace and the change is simply instant (ADR-0012). Suppressed rather than
            // cross-faded, because a cross-fading checkbox reads as an undecided one.
            .animation(reduceMotion ? nil : HWMotion.easeInOut.animation(.quick), value: isOn)
            .accessibilityHidden(true)
    }

    // MARK: - The two surfaces

    private var accentInk: Color {
        appearance == .brand ? theme.palette.brand.inkAccent : theme.palette.accent.base
    }

    /// The tick sits on the filled box, so it is the *ground* colour of the surface it is on — galaxy on brand,
    /// milky in-app.
    private var tickInk: Color {
        appearance == .brand ? theme.palette.brand.background : theme.palette.brand.ink
    }

    private var boxFill: Color {
        appearance == .brand ? theme.palette.brand.raised : theme.palette.surface.raised
    }

    private var borderInk: Color {
        appearance == .brand ? theme.palette.brand.separatorStrong : theme.palette.surface.separatorStrong
    }

    private var secondaryInk: Color {
        appearance == .brand ? theme.palette.brand.inkSecondary : theme.palette.surface.inkSecondary
    }
}

#if DEBUG
#Preview("Checked and unchecked, on both surfaces") {
    @Previewable @State var kept = true
    @Previewable @State var other = false

    ZStack {
        HWPreviewGround(appearance: .brand)
        VStack(alignment: .leading, spacing: 20) {
            HWCheckbox("Keep me signed in", isOn: $kept, appearance: .brand)
            HWCheckbox("Keep me signed in", isOn: $other, appearance: .brand)
        }
        .padding()
    }
    .hwTheme()
}

#Preview("On the in-app surface") {
    @Previewable @State var kept = true

    ZStack {
        HWPreviewGround()
        HWCheckbox("Keep me signed in", isOn: $kept).padding()
    }
    .hwTheme()
}

#Preview("AX3 — the sentence wraps and the box stays put") {
    @Previewable @State var kept = true

    HWCheckbox("Keep me signed in on this device", isOn: $kept, appearance: .brand)
        .padding()
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}

#Preview("RTL — the box leads on the right") {
    @Previewable @State var kept = true

    HWCheckbox("Keep me signed in", isOn: $kept, appearance: .brand)
        .padding()
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}
#endif
