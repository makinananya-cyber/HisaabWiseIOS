import SwiftUI

/// The design's `.topbar` — the eyebrow-over-title header a tab-root screen opens with.
///
/// `.topbar` is `.mark`, then `.eyebrow` above `.h1`, with room at the trailing edge for whatever that
/// screen puts there: Expenses puts an `.editbtn`, Reports puts nothing. So the trailing slot is a
/// `ViewBuilder` rather than a value — it holds a *control*, and a component that took one as data would
/// be picking which control.
///
/// **The design's `.mark` is now here**, which is what the old note in this place said would happen once
/// the logo shipped: `.topbar{display:flex;align-items:center;gap:11px}` opens with a 38pt tile on all four
/// tab roots that carry a top bar, and the app was drawing the titles alone. It is unconditional rather
/// than an argument, because the design puts it on every one of them — a screen able to leave it out is a
/// screen that will, and then four headers disagree about what a header is. Home draws no `HWTopBar` at
/// all (its header is a greeting) and so is untouched.
///
/// **`.center`, not `.firstTextBaseline`.** The row is a tile, a two-line block, and a pill, and a
/// baseline shared between them lands the tile's *bottom* on the eyebrow's baseline — which puts the logo
/// most of its own height above the title. `align-items:center` is what the design sets, and with three
/// items of three heights it is the only alignment that reads as a row.
struct HWTopBar<Trailing: View>: View {
    @Environment(ThemeManager.self) private var theme

    private let eyebrow: LocalizedStringResource?
    private let title: Text
    private let trailing: Trailing

    init(
        eyebrow: LocalizedStringResource? = nil,
        title: Text,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.trailing = trailing()
    }

    /// `.mark{width:38px;height:38px}`, and `.topbar{gap:11px}`.
    ///
    /// An instance constant rather than a `static` one because `HWTopBar` is generic over its trailing slot, and
    /// Swift does not allow static stored properties in a generic type.
    private let markSize: CGFloat = 38

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            // `surface`, because a top bar only ever appears on the five light screens — the galaxy tile is
            // the privacy overlay's and Landing's (``HWMark``).
            HWMark(size: markSize, appearance: .surface)

            VStack(alignment: .leading, spacing: 1) {
                if let eyebrow {
                    Text(eyebrow).hwEyebrow()
                }
                title
                    .font(.hw(.title))
                    .foregroundStyle(theme.palette.surface.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The eyebrow and the title are one heading, read together and announced as one.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            trailing
        }
    }
}

extension HWTopBar where Trailing == EmptyView {
    /// A top bar with nothing at its trailing edge, which is most of them.
    init(eyebrow: LocalizedStringResource? = nil, title: Text) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

/// The design's `.backbar` — an `.iconbtn` back affordance, the title of wherever you are, and room for
/// one control.
///
/// Distinct from ``HWTopBar`` in the way the design distinguishes them: a back bar belongs to a pushed
/// detail — an article, an expense, a settings page — and it always has somewhere to go back to, so
/// `onBack` is required rather than optional.
///
/// The title is `.backbar .who`, which truncates in the design because it holds a name of unknown length.
/// It wraps here instead: truncating the thing that says where you are is worse than a taller bar.
struct HWBackBar<Trailing: View>: View {
    @Environment(ThemeManager.self) private var theme

    private let title: Text
    /// VoiceOver's reading of the back affordance. Icon-only, so the screen supplies the words.
    private let backLabel: LocalizedStringResource
    private let onBack: () -> Void
    private let trailing: Trailing

    init(
        title: Text,
        backLabel: LocalizedStringResource,
        onBack: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.backLabel = backLabel
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            // `chevron.backward` rather than `chevron.left`: the glyph mirrors under RTL and the named
            // direction would not.
            HWIconButton(backLabel, systemImage: "chevron.backward", action: onBack)

            title
                .font(.hw(.subheading))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            trailing
        }
    }
}

extension HWBackBar where Trailing == EmptyView {
    /// A back bar with nothing at its trailing edge.
    init(title: Text, backLabel: LocalizedStringResource, onBack: @escaping () -> Void) {
        self.init(title: title, backLabel: backLabel, onBack: onBack) { EmptyView() }
    }
}

#if DEBUG
#Preview("Bars — with and without a trailing control") {
    VStack(spacing: 26) {
        HWTopBar(eyebrow: "Your account", title: Text(verbatim: "Settings")) {
            HWEditButton("Edit", systemImage: "pencil", isOn: false) {}
        }
        HWTopBar(eyebrow: "This month", title: Text(verbatim: "Expenses"))
        HWTopBar(title: Text(verbatim: "No eyebrow"))
        HWBackBar(title: Text(verbatim: "Where your salary goes"), backLabel: "Go back") {}
        HWBackBar(title: Text(verbatim: "Rent"), backLabel: "Go back", onBack: {}) {
            HWIconButton("Delete", systemImage: "trash") {}
        }
    }
    .padding()
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — the titles wrap rather than truncating") {
    VStack(spacing: 26) {
        HWTopBar(eyebrow: "Your account", title: Text(verbatim: "Settings")) {
            HWEditButton("Edit", isOn: false) {}
        }
        HWBackBar(title: Text(verbatim: "Where your salary goes"), backLabel: "Go back") {}
    }
    .padding()
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("RTL — the back chevron mirrors") {
    VStack(spacing: 26) {
        HWTopBar(eyebrow: "حسابك", title: Text(verbatim: "الإعدادات")) {
            HWEditButton("تعديل", systemImage: "pencil", isOn: false) {}
        }
        HWBackBar(title: Text(verbatim: "إلى أين يذهب راتبك"), backLabel: "رجوع") {}
    }
    .padding()
    .environment(\.layoutDirection, .rightToLeft)
    .background(HWPreviewGround())
    .hwTheme()
}
#endif
