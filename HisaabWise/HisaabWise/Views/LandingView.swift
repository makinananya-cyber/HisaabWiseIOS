import SwiftUI

/// The first thing anyone sees, converted from the design's `landing` document.
///
/// Four bands on the galaxy ground, top to bottom: the wordmark, the hero illustration in a glass card, the
/// headline with a rotating strapline under it, and the call to action over its footnote. The design lays them
/// out with `justify-content:space-between`, which is what the spacers do here.
///
/// **It is not a ``BaseView``, and that is the criterion rather than an omission** (issue #13). Landing makes
/// no request, so it has no `LoadState` to render: no spinner, no empty state, no offline state, no failure.
/// It also sits on `brand` (ADR-0021), which `ScreenChrome` does not paint. This is the screen that proves the
/// theme and the layout before any data exists.
///
/// **What is deliberately less animated than the design.** The prototype runs six ambient loops — a floating
/// hero, a sheen across the headline, a pulsing dot, a sweep across the button, a ring around the wordmark, and
/// the strapline rotation. Only the last carries information, and it is the only one the acceptance criteria
/// name. Shipped: the strapline rotation, the entrance stagger, the hero's float, and the dot's pulse. Dropped:
/// the headline sheen (the gradient itself ships, static), the button sweep, and the wordmark ring — ADR-0029
/// records why, and the short version is that a hand-built animated gradient mask is a lot of code for
/// something nobody reads.
///
/// **Under Reduce Motion nothing moves at all**, including the strapline: ADR-0012 makes Landing the one place
/// where motion is *removed* rather than replaced — "one strapline, stable for the session" — because a
/// strapline that changed without animating would be a caption rewriting itself under the reader.
struct LandingView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The rotation's state. Held rather than made in `body` for the reason every screen's is (issue #5).
    let viewModel: LandingViewModel

    /// What the call to action does. A closure rather than a `NavigationLink`, because where sign-in lives is
    /// the root's decision and not this screen's — Landing knows that the user wants to start, not what
    /// starting is.
    let onGetStarted: () -> Void

    /// The four sentences, in the design's order.
    ///
    /// **The first is a [FIX].** The design says "Every rupee, tracked without thinking about it." — which
    /// names a currency the app does not display, since the figures come from the server in the user's own
    /// (Product Spec §3.1, ADR-0003). The replacement keeps the sentence's shape and drops the currency.
static let straplines: [LocalizedStringResource] = [
        "landing.strapline.1",
        "landing.strapline.2",
        "landing.strapline.3",
        "landing.strapline.4",
    ]

    /// The design's `setInterval(…, 3800)`.
    private static let rotation = Duration.milliseconds(3800)

    var body: some View {
        // **The design is one fixed viewport; iOS is not.** `justify-content:space-between` on a 390×844 frame
        // assumes the content always fits, and at AX5 it does not — the first build of this screen drew the
        // headline through the strapline and pushed the footnote off the bottom. So the bands sit in a scroll
        // view with a minimum height of one screen: when everything fits, the spacers spread it exactly as the
        // design does and there is nothing to scroll; when the type grows, the screen grows with it (ADR-0012).
        GeometryReader { proxy in
            ScrollView {
                bands
                    .padding(.horizontal, 22)
                    .padding(.vertical, 26)
                    .frame(minHeight: proxy.size.height, alignment: .top)
            }
            // No bounce when there is nothing to scroll, so the fitted layout still feels fixed.
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(HWBrandGround())
        // One container, so the screen reads as a screen rather than as five loose elements inside whatever
        // the root puts around it (ADR-0012).
        .accessibilityElement(children: .contain)
        .task(id: reduceMotion) {
            // **Reduce Motion suppresses the rotation entirely rather than speeding it up**: the loop never
            // starts, so the first strapline is the one for the session (ADR-0012). Keyed on the setting so
            // that turning it off mid-session starts the rotation rather than waiting for a relaunch.
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.rotation)
                guard !Task.isCancelled else { return }
                withAnimation(HWMotion.easeInOut.animation(.standard)) { viewModel.advance() }
            }
        }
    }

    /// The four bands, top to bottom, with the design's `space-between` spacing between them.
    private var bands: some View {
        VStack(spacing: 0) {
            wordmark
            Spacer(minLength: 12)
            hero
            Spacer(minLength: 18)
            copy
            Spacer(minLength: 22)
            callToAction
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - The bands

    /// `.brand-row` — the mark tile beside "Hisaab**Wise**", centred.
    private var wordmark: some View {
        HStack(spacing: 10) {
            HWMark(size: 34)

            // **One `Text`, two colours.** The design is `<div class="brand">Hisaab<span>Wise</span></div>` —
            // one text node with a styled span — and an `AttributedString` is that. The two alternatives are
            // both wrong: `Text + Text` is how an untranslatable sentence gets assembled (`LocalisationTests`
            // forbids it app-wide), and two `Text`s in an `HStack` **reorder under RTL**, which turned the
            // wordmark into "WiseHisaab" in Arabic. A brand name is one word whichever way the layout runs.
            Text(wordmarkName)
                .font(.hw(.subheading))
                .tracking(0.6)
        }
        .hwEnters(step: 0, suppressed: reduceMotion)
        // One element saying the name once. `children: .combine` would keep ``HWMark``'s own label — which is
        // also "HisaabWise" — and VoiceOver would say it twice (the same fix `HomeView` makes for its caption
        // and figure). The heading trait belongs to the headline below, which is the design's `<h1>`.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("shell.mark.accessibilityLabel"))
    }

    /// "Hisaab" in milky, "Wise" in sky — `.brand` and `.brand span`.
    ///
    /// Not localised: a brand name is the same word in every language, so there is no catalogue key and
    /// `AttributedString` carries the two colours a single `Text` could not.
    private var wordmarkName: AttributedString {
        var hisaab = AttributedString("Hisaab")
        hisaab.foregroundColor = theme.palette.brand.ink
        var wise = AttributedString("Wise")
        wise.foregroundColor = theme.palette.brand.inkAccent
        return hisaab + wise
    }

    /// `.hero-card` — the illustration inside a glass card that floats.
    private var hero: some View {
        Image(.hwHeroBook)
            .resizable()
            .scaledToFit()
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .frame(maxWidth: 344)
            .hwBox(
                fill: theme.palette.brand.raised,
                radius: .extraLarge,
                border: theme.palette.brand.separator,
                elevation: .large
            )
            // The design's `float 6s ease-io infinite alternate`, which is the one ambient loop worth its
            // three lines: the hero is the screen's subject and a still one reads as a screenshot.
            .ambientFloat(suppressed: reduceMotion)
            .hwEnters(step: 1, suppressed: reduceMotion)
            // The design's own `aria-label`, verbatim. It labelled this illustration rather than hiding it, so
            // it is content and not decoration (ADR-0012).
            .accessibilityElement()
            .accessibilityLabel(Text("landing.hero.accessibilityLabel"))
    }

    /// `.copy` — the headline, and the pill the strapline rotates inside.
    private var copy: some View {
        VStack(spacing: 18) {
            headline.hwEnters(step: 2, suppressed: reduceMotion)
            strapline.hwEnters(step: 3, suppressed: reduceMotion)
        }
    }

    /// `.headline` — two lines, the second in the design's sky→venus→sky gradient.
    private var headline: some View {
        // No spacing between the lines: the design draws them as one `<h1>` with a `<br>` at `line-height:1.26`,
        // so the only gap is the line box's own. Two `Text`s are what let the second carry the gradient.
        VStack(spacing: 0) {
            Text("landing.headline.first")
                .foregroundStyle(theme.palette.brand.ink)
            Text("landing.headline.second")
                // `.headline em` — a gradient clipped to the text. The design animates it across; the wash
                // itself is the visual and it ships, the sliding does not.
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            theme.palette.brand.inkAccent,
                            theme.palette.brand.inkSecondary,
                            theme.palette.brand.inkAccent,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .font(.hw(.title))
        .tracking(-0.4)
        .multilineTextAlignment(.center)
        // Wraps into a taller block rather than being cut off, which is what the doubled-length run and AX5
        // both need (ADR-0011, ADR-0012).
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        // The design's `<h1>`: heading navigation should land on what the screen says, not on the logo.
        .accessibilityAddTraits(.isHeader)
    }

    /// `.pill` — a dot and the rotating sentence, inside a bordered glass rectangle.
    private var strapline: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(theme.palette.brand.inkAccent)
                .frame(width: 7, height: 7)
                // `rgba(208,227,255,.55)` — sky at 55%, which is the accent ink.
                .ambientPulse(colour: theme.palette.brand.inkAccent, suppressed: reduceMotion)
                // Decorative: it marks the pill, it does not say anything.
                .accessibilityHidden(true)

            Text(Self.straplines[viewModel.strapline])
                // **The sentence has to be a new view to animate.** SwiftUI does not animate a `Text`'s
                // string, so without an identity the rotation would hard-cut — which is the "caption
                // rewriting itself under the reader" that Reduce Motion exists to prevent, delivered to
                // everybody. The design's own transition is asymmetric: out upward, in from below
                // (`.out{translateY(-10px)}` / `.in-up{translateY(10px)}`).
                .id(viewModel.strapline)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
                .font(.hw(.bodyLarge))
                .foregroundStyle(theme.palette.brand.inkSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                // **The rotation must not interrupt or re-announce** (issue #13). The design marks this
                // `aria-live="polite"`, which re-reads the sentence every 3.8 seconds — on a screen whose
                // only action is one button, that is a screen that talks over its own user. So the pill is a
                // labelled element whose *value* is the sentence: VoiceOver reads it when the user is on it
                // and stays quiet when it changes underneath them.
                .accessibilityLabel(Text("landing.strapline.accessibilityLabel"))
                .accessibilityValue(Text(Self.straplines[viewModel.strapline]))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 334, minHeight: 58)
        .hwBox(fill: theme.palette.brand.raised, radius: .large, border: theme.palette.brand.separator)
    }

    /// `.cta-wrap` — the button over its glow, and the footnote under it.
    private var callToAction: some View {
        VStack(spacing: 14) {
            HWButton(
                "landing.cta",
                appearance: .brand,
                // `.arrow` in the design is a literal "→", which does not mirror. `arrow.forward` does.
                systemImage: "arrow.forward",
                action: onGetStarted
            )
                // `.cta-glow` — a blurred sky pill *behind* the button, which is why it is here and not in
                // `HWButtonAppearance`: it sits outside the control's own bounds.
                .background {
                    Capsule()
                        .fill(theme.palette.brand.inkAccent)
                        .blur(radius: 24)
                        .opacity(0.5)
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                }
                .hwEnters(step: 4, suppressed: reduceMotion)

            Text("landing.free")
                .font(.hw(.caption))
                .foregroundStyle(theme.palette.brand.inkSecondary)
                .opacity(0.85)
                .tracking(0.2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .hwEnters(step: 5, suppressed: reduceMotion)
        }
    }
}

/// The two ambient loops Landing keeps, private to it.
///
/// Not vocabulary: a design system earns a modifier when a second screen wants it, and until Auth (#14) says
/// otherwise these are one screen's decoration. They live here so that `body` reads as the layout and the
/// Reduce Motion branch is written once each rather than at every call.
private extension View {
    /// `.hero-card{animation:float 6s var(--ease-io) infinite alternate}` — `translateY(5px)` to `-5px`.
    func ambientFloat(suppressed: Bool) -> some View {
        modifier(AmbientFloat(suppressed: suppressed))
    }

    /// `.pill-dot{animation:ping 2.2s var(--ease-out) infinite}` — a ring expanding out of the dot and fading.
    ///
    /// The design draws it as a growing `box-shadow`; here it is a second circle behind the dot, which is the
    /// same picture and the only way SwiftUI can animate a spread.
    ///
    /// - Parameter colour: the ring's, taken from the caller because a `ViewModifier` cannot read the theme
    ///   without becoming a view that resolves a role — and a role is what the caller already has.
    func ambientPulse(colour: Color, suppressed: Bool) -> some View {
        modifier(AmbientPulse(colour: colour, suppressed: suppressed))
    }
}

private struct AmbientFloat: ViewModifier {
    let suppressed: Bool

    @State private var lifted = false

    func body(content: Content) -> some View {
        content
            .offset(y: suppressed ? 0 : (lifted ? -5 : 5))
            .animation(
                suppressed ? nil : HWMotion.easeInOut.loop(seconds: 6).repeatForever(autoreverses: true),
                value: lifted
            )
            .onAppear { lifted = true }
            // Rebuilt when the setting changes, so turning Reduce Motion off starts the loop rather than
            // waiting for a relaunch — `.animation(_:value:)` has nothing to fire on once `lifted` has
            // latched. The content it wraps holds no state of its own to lose.
            .id(suppressed)
    }
}

private struct AmbientPulse: ViewModifier {
    let colour: Color
    let suppressed: Bool

    @State private var pinged = false

    func body(content: Content) -> some View {
        content.background {
            Circle()
                .stroke(colour.opacity(0.55), lineWidth: 2)
                .scaleEffect(pinged ? 3.6 : 1)
                .opacity(pinged ? 0 : 0.55)
                .animation(
                    suppressed ? nil : HWMotion.easeOut.loop(seconds: 2.2).repeatForever(autoreverses: false),
                    value: pinged
                )
                .onAppear { pinged = true }
                .id(suppressed)
                .accessibilityHidden(true)
        }
    }
}

#if DEBUG
#Preview("Landing") {
    LandingView(viewModel: LandingViewModel(), onGetStarted: {}).hwTheme()
}

/// The second strapline, so the pill's longest sentence is visible without waiting for it.
#Preview("Landing — a longer strapline") {
    let viewModel = LandingViewModel()
    viewModel.advance()
    return LandingView(viewModel: viewModel, onGetStarted: {}).hwTheme()
}

#Preview("RTL — the whole screen mirrors") {
    LandingView(viewModel: LandingViewModel(), onGetStarted: {})
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("AX5 — the copy grows and the bands give way") {
    LandingView(viewModel: LandingViewModel(), onGetStarted: {})
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
