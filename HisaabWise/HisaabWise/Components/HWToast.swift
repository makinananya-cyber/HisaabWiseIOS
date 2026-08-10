import SwiftUI

/// The design's `.toast` — a galaxy pill that says one short thing above the tab bar.
///
/// Values and closures only, which for a toast means: it draws a message and knows nothing about when the
/// message stops being true. **Dismissal timing belongs to the screen** that raised it — a component that
/// owned a timer would own the lifetime of state it does not hold, and every screen would need a way to
/// override it anyway.
///
/// Present it with ``SwiftUI/View/hwToast(_:isPresented:)``, which carries the transition and the
/// announcement.
struct HWToast: View {
    @Environment(ThemeManager.self) private var theme

    private let message: LocalizedStringResource

    init(_ message: LocalizedStringResource) {
        self.message = message
    }

    var body: some View {
        HStack(spacing: 11) {
            // `.toast i` — a sky dot. Decorative: it marks the pill, it does not say anything.
            Circle()
                .fill(theme.palette.accent.soft)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(message)
                .font(.hw(.body).weight(.semibold))
                .foregroundStyle(theme.palette.brand.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hwBox(fill: theme.palette.accent.deep, radius: .medium, elevation: .large)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Overlays a ``HWToast`` above the content while `isPresented`.
    ///
    /// The design animates it in with `translateY(16px) scale(.97)` → none, which is ``HWEntrance/rise``.
    /// Under Reduce Motion that entrance **reduces** to a cross-fade of the same length rather than being
    /// dropped, so the toast still arrives as an event rather than appearing between one frame and the next
    /// (ADR-0012). This is the worked example of that rule: the choice is `HWEntrance.rise` and the
    /// replacement is the vocabulary's, not a ternary of this modifier's own.
    ///
    /// A toast is the case ADR-0012 names explicitly: neither the animated nor the static form reaches
    /// VoiceOver on its own, so an announcement is posted when it appears.
    func hwToast(_ message: LocalizedStringResource?, isPresented: Bool) -> some View {
        modifier(HWToastOverlay(message: message, isPresented: isPresented))
    }
}

/// The transition, the placement, and the announcement — the parts of presenting a toast that every
/// screen would otherwise write for itself.
struct HWToastOverlay: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The announcement resolves against this rather than against whatever locale the message literal
    /// captured, which is the device's (ADR-0024). It is the one string on screen that a `Text` is not
    /// drawing, so it is the one that has to ask.
    @Environment(\.locale) private var locale

    let message: LocalizedStringResource?
    let isPresented: Bool

    private var isShowing: Bool { isPresented && message != nil }

    /// The design's arrival, and — under Reduce Motion — its replacement. One value, decided once.
    private var entrance: HWEntrance {
        HWEntrance.rise.resolved(reduceMotion: reduceMotion)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message, isPresented {
                    HWToast(message)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .transition(entrance.transition)
                }
            }
            .animation(entrance.animation, value: isShowing)
            .onChange(of: isShowing) { _, showing in
                guard showing, let message else { return }
                // Immediate: a toast confirms something the user just did, and one that arrives after
                // VoiceOver has finished reading the screen they moved on to is worse than silence.
                HWAnnouncement.post(message, in: locale, priority: .immediate)
            }
    }
}

#if DEBUG
#Preview("Toast — presented") {
    HWPreviewGround()
        .hwToast("Expense logged.", isPresented: true)
        .hwTheme()
}

#Preview("Toast — absent") {
    HWPreviewGround()
        .hwToast("Expense logged.", isPresented: false)
        .hwTheme()
}

#Preview("AX3 — the message wraps rather than truncating") {
    HWPreviewGround()
        .hwToast("Expense logged. It will show up in this month's report.", isPresented: true)
        .dynamicTypeSize(.accessibility3)
        .hwTheme()
}

// Latin digits under `ar` — ADR-0011's decision, matching the server's own formatting.
#Preview("RTL") {
    HWPreviewGround()
        .hwToast("تم تسجيل المصروف: 250 درهم.", isPresented: true)
        .environment(\.layoutDirection, .rightToLeft)
        .hwTheme()
}
#endif
