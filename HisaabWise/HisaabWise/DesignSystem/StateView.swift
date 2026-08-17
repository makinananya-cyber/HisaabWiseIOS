import Foundation
import SwiftUI

/// The copy a screen supplies for the states in which it has no data.
///
/// Five tabs times four states is twenty-odd placeholders; ADR-0016's answer is one taxonomy and one
/// view, with the screen supplying only what a screen can know. Which is less than it looks:
///
/// - ``empty`` has **no shared default**, because an empty expense list and an empty reports archive
///   are genuinely different sentences and a generic one would be worse than either.
/// - ``loading`` and ``offline`` do, because they are not. A screen may still override them; twenty
///   rewordings of "you're offline" is the outcome ADR-0016 exists to avoid, so overriding should be
///   an argued exception.
/// - **Failure copy is not here at all.** It comes from the code, through ``ErrorCopy``.
struct StateCopy: Sendable {
    /// Read aloud, and drawn beside the spinner.
    var loading: LocalizedStringResource = "state.loading"

    /// The request succeeded and there is genuinely nothing to show. The one string only this screen
    /// can write.
    var empty: LocalizedStringResource

    /// Not reachable, and not broken.
    var offline: LocalizedStringResource = "state.offline"

    /// Title for the retry CTA, or `nil` on a screen where retrying is not worth offering. Drawn on
    /// ``LoadState/offline`` and ``LoadState/failed(_:)`` only.
    ///
    /// The *action* is not the screen's to supply: it is the screen's own load, wired by ``BaseView``,
    /// because a retry that did something subtly different from the first fetch is a second code path
    /// to keep in step.
    ///
    /// **What is deliberately not here yet:** a CTA for ``LoadState/empty`` — "Add your first expense"
    /// — where retrying is not the remedy and only the screen knows what is. It needs a closure, which
    /// costs this type its `Sendable` conformance, and it has no caller until Expenses (issue #18). It
    /// is added *there*, with a real remedy to shape it, rather than guessed at here.
    var retry: LocalizedStringResource? = "state.retry"
}

/// Which of the design's two light grounds a screen sits on.
///
/// Not two appearances — ADR-0021's two appearances are `surface` and `brand`, and both of these are `surface`.
/// This is the design's own distinction between a `.page` and a `.page--detail`, which is one extra layer on the
/// same ground and not a second palette.
enum HWGround: Sendable, Hashable, CaseIterable {
    /// `.page` — a tab root. The `.wash` and nothing else.
    case root

    /// `.page--detail` — a **pushed** page, which the design warms towards its foot.
    ///
    /// ```css
    /// .page--detail{background:linear-gradient(180deg,var(--bg) 0%,var(--bg) 40%,var(--bg-2) 100%)}
    /// ```
    ///
    /// `--bg` is `--milky` and `--bg-2` is `--meteor`: white-cream for the top 40%, then a fade to the warmer
    /// cream at the bottom. It is what makes a pushed page read as a different sheet of paper from the root it
    /// came off, and it is the reason the inside of a category looked like the wrong app — the detail pages are
    /// not `BaseView`s, so they inherited no ground at all and took the system's white.
    case detail
}

extension View {
    /// The ground a screen sits on: the design's `.wash`, filling the window and running under the status bar.
    ///
    /// **Three callers, which is why it is a modifier** — `ScreenChrome`, which every `BaseView` gets for free;
    /// Account's four **pushed** pages (#23); and Expenses' seven category pages, which are pushed for the same
    /// reason and were missing this for the same reason. Without it a pushed page takes the system's white, and
    /// the design's cards — which are `surface.raised`, also white — become invisible outlines on it. Looking at
    /// the running app is what found that; nothing a test asserts about a render could.
    ///
    /// - Parameter ground: which of ``HWGround``'s two the page is. Defaults to `root`, so no existing caller
    ///   changes meaning.
    ///
    /// `ignoresSafeArea` on the **ground alone**: it runs under the status bar, the content does not.
    func hwScreenGround(_ palette: HWPalette, _ ground: HWGround = .root) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(HWSurfaceWash(palette: palette, ground: ground).ignoresSafeArea())
    }
}

/// The design's `.wash` — the milky ground with a cool bloom in two opposite corners.
///
/// **The in-app screens are not a flat colour, and shipping them as one is what made them look unfinished.** The
/// design puts a `.wash` layer inside every `.screen`: two large blurred radial gradients, `--sky` off the
/// top-trailing corner and `--venus` off the bottom-leading one, over `--milky`. What the eye reads is an ombré
/// from pale blue at the top through white behind the cards to warm cream at the foot — which is what the cards,
/// being pure white, are drawn to sit on.
///
/// It lives here beside ``SwiftUI/View/hwScreenGround(_:)`` rather than in `Components/` for the reason
/// ``StateView``'s retry button is not an `HWButton`: `Components` draws with `DesignSystem`'s tokens, so a
/// `DesignSystem` view reaching the other way would point the dependency both directions. The brand ground —
/// `HWBrandGround`, the galaxy twin of this — is a component because Landing and Auth are ordinary screens that
/// place it themselves; this one is chrome that every `BaseView` inherits and no screen names.
///
/// **The design's slow float is not here.** `.wash::before/::after` drift over 13 and 17 seconds; a permanently
/// animating background is a permanently redrawing one, and at this blur nobody can see the difference between
/// the two positions. The ombré is what was asked for and the drift is what was dropped (the same call ADR-0029
/// records for `.grain`).
struct HWSurfaceWash: View {
    let palette: HWPalette

    /// Whether this is a tab root or a pushed page — see ``HWGround``. Defaulted, so the `ScreenChrome` call
    /// that has always said nothing about it goes on saying nothing.
    var ground: HWGround = .root

    var body: some View {
        ZStack {
            base

            // `.wash::before` — 420pt of `--sky`, off the top-right corner.
            bloom(
                colour: palette.accent.soft,
                opacity: 0.85,
                size: 420,
                alignment: .topTrailing,
                offset: CGSize(width: 160, height: -190)
            )

            // `.wash::after` — 400pt of `--venus`, off the bottom-left.
            bloom(
                colour: palette.accent.tintSecondary,
                opacity: 0.60,
                size: 400,
                alignment: .bottomLeading,
                offset: CGSize(width: -150, height: 180)
            )
        }
        // Decoration, exactly as the design's `aria-hidden` wash is.
        .accessibilityHidden(true)
    }

    /// The flat colour the two blooms sit on — `--milky` for a root, and the design's own
    /// `linear-gradient(180deg,--milky 0%,--milky 40%,--meteor 100%)` for a pushed page.
    ///
    /// A `LinearGradient` in both arms rather than a `Color` in one, so the two branches are the same *kind* of
    /// thing and the root is visibly "the same gradient with both ends the same". Two stops at the same colour
    /// cost nothing to draw and one branch fewer to read.
    @ViewBuilder
    private var base: some View {
        switch ground {
        case .root:
            palette.surface.background
        case .detail:
            LinearGradient(
                stops: [
                    .init(color: palette.surface.background, location: 0),
                    .init(color: palette.surface.background, location: 0.40),
                    .init(color: palette.surface.backgroundSecondary, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// One blurred radial fade. `filter:blur(10px)` on a gradient that already fades to nothing at 70% — the
    /// blur is what stops the stop's edge reading as a ring.
    private func bloom(
        colour: Color,
        opacity: Double,
        size: CGFloat,
        alignment: Alignment,
        offset: CGSize
    ) -> some View {
        RadialGradient(
            stops: [
                .init(color: colour.opacity(opacity), location: 0),
                .init(color: colour.opacity(0), location: 0.70),
            ],
            center: .center,
            startRadius: 0,
            endRadius: size / 2
        )
        .frame(width: size, height: size)
        .blur(radius: 10)
        .offset(offset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// How one state with nothing to draw is presented, as a value.
///
/// Pulled out of ``StateView``'s `body` so that "offline is visually distinct from failed" is a fact a
/// test can assert rather than a pixel a reviewer has to eyeball. It resolves a ``LoadState`` and a
/// ``StateCopy`` against the palette and answers with what differs between states: a symbol, a tint, a
/// sentence, and whether there is a CTA.
struct StatePresentation: Sendable, Equatable {
    /// SF Symbol for the state, or `nil` while loading — where a spinner says it better.
    let symbol: String?

    /// The distinction ADR-0016 is about. `offline` takes the calm informational accent; `failed`
    /// takes danger. Telling a user in a tunnel that something broke is the defect.
    let tint: Color

    /// What the user reads. For ``LoadState/failed(_:)`` this comes from ``ErrorCopy`` and so is
    /// never, at any point, the server's own prose.
    let message: LocalizedStringResource

    /// The CTA title, or `nil` for no CTA.
    let retry: LocalizedStringResource?

    /// Loading draws a spinner instead of a symbol, and is the only state that does.
    let showsProgress: Bool

    /// `nil` for ``LoadState/loaded(_:)`` — there is no placeholder for data, and making that
    /// unrepresentable is cheaper than a `fatalError` nobody reads.
    init?<Value>(state: LoadState<Value>, copy: StateCopy, palette: HWPalette) {
        switch state {
        case .loaded:
            return nil
        case .loading:
            symbol = nil
            tint = palette.accent.base
            message = copy.loading
            // Nothing to offer: a request is already in flight.
            retry = nil
            showsProgress = true
        case .empty:
            symbol = "tray"
            tint = palette.surface.inkTertiary
            message = copy.empty
            // Re-asking a question the server has already answered is not a remedy. The CTA that
            // belongs on an empty screen is the screen's own, and arrives with the first screen that
            // has one — see ``StateCopy/retry``.
            retry = nil
            showsProgress = false
        case .offline:
            symbol = "wifi.slash"
            tint = palette.accent.muted
            message = copy.offline
            retry = copy.retry
            showsProgress = false
        case .failed(let code):
            symbol = "exclamationmark.triangle.fill"
            tint = palette.feedback.danger
            message = ErrorCopy.message(for: code)
            retry = copy.retry
            showsProgress = false
        }
    }
}

/// The single view every screen's four empty-handed states go through, and the passthrough for the
/// fifth.
///
/// ADR-0016 — one `StateView`, so that four data states across twelve screens are four placeholders
/// rather than forty-eight. It takes the whole ``LoadState`` rather than only the empty cases on
/// purpose: **this is the only `switch` over the taxonomy in the app**, and a source scan in
/// `HisaabWiseTests/Architecture` keeps it that way. A screen reaches it through ``BaseView`` and never
/// constructs it directly.
///
/// **It draws the `surface` appearance**, which is the five in-app screens (ADR-0021). Landing and Auth
/// sit on `brand` — a different ground and a different `danger` — and are not `BaseView` screens; see
/// the note on ``BaseView``.
struct StateView<Value: Sendable, Loaded: View>: View {
    @Environment(ThemeManager.self) private var theme

    /// For the announcement, not for a format string: it is the language `hwLanguage(_:)` put in the
    /// environment, and an announcement is the one piece of copy that has to resolve itself (ADR-0024).
    @Environment(\.locale) private var locale

    let state: LoadState<Value>
    let copy: StateCopy

    /// The screen's own load, offered as the retry on offline and failed. Supplied by ``BaseView``;
    /// `nil` and no CTA is drawn, however much ``StateCopy/retry`` holds.
    let reload: (@MainActor () async -> Void)?

    @ViewBuilder let loadedContent: (Value) -> Loaded

    /// `nil` while there is data, which is what makes the announcement below say nothing on arrival.
    private var presentation: StatePresentation? {
        StatePresentation(state: state, copy: copy, palette: theme.palette)
    }

    var body: some View {
        drawn
            // **The accessibility default every screen inherits** (ADR-0012). A placeholder replaced by a
            // *different* placeholder — retry tapped, back to offline — is the same layout with different
            // words in it, and VoiceOver has no way to discover that: focus was on a button that no longer
            // exists, and nothing moved.
            //
            // Keyed on the **sentence**, not on the presentation: the sentence is what would be said, and
            // `StatePresentation` also carries a tint. Watching the whole value would re-speak the same
            // words on a palette swap, which is the one mutation `ThemeManager` exists to allow.
            //
            // Two silences, both deliberate. **Nothing on first appearance** — the placeholder is text on
            // screen, and VoiceOver reads a screen it has just moved to. **Nothing for `loaded`** — there is
            // content to explore and VoiceOver reads it on the next swipe; a sentence saying the screen has
            // loaded is the app talking about itself rather than about the user's money.
            .onChange(of: presentation?.message) { _, message in
                guard let message else { return }
                // Standard priority: the same words are on screen, so interrupting would be shouting.
                HWAnnouncement.post(message, in: locale)
            }
    }

    @ViewBuilder
    private var drawn: some View {
        if let value = state.value {
            loadedContent(value)
        } else if let presentation {
            placeholder(presentation)
        }
    }

    private func placeholder(_ presentation: StatePresentation) -> some View {
        VStack(spacing: 12) {
            if presentation.showsProgress {
                ProgressView()
                    .tint(presentation.tint)
            } else if let symbol = presentation.symbol {
                Image(systemName: symbol)
                    .font(.hw(.heading))
                    .foregroundStyle(presentation.tint)
                    // The symbol restates the sentence below it; announcing both is noise (ADR-0012).
                    .accessibilityHidden(true)
            }

            // `Text(LocalizedStringResource)` resolves against the **environment's** locale, not the one the
            // resource captured when it was created — which is what makes the language switch reach copy
            // that was written as a literal in a type initialiser long before any screen existed
            // (`StateCopy`'s defaults, `ErrorCopy`'s table). That is a platform behaviour the "no relaunch"
            // requirement rests on, so `ShellLocalisationTests` pins it rather than trusting it.
            Text(presentation.message)
                .font(.hw(.body))
                .foregroundStyle(theme.palette.surface.inkSecondary)
                .multilineTextAlignment(.center)

            if let title = presentation.retry, let reload {
                // `Components/` carries the design's `.btn.quiet` now (issue #26) and this still does
                // not use it: `HWButton` reads `DesignSystem`'s tokens, so a `DesignSystem` view
                // reaching back for it would point the dependency both ways. This stays what it was —
                // design-system code styling its own control, which is the one place allowed to. A
                // *screen* never is. Reconsider if `StateView` ever moves out of `DesignSystem/`.
                Button {
                    Task { await reload() }
                } label: {
                    Text(title)
                        .font(.hw(.bodyLarge))
                        .foregroundStyle(theme.palette.accent.base)
                        // 44pt is the minimum target and text this size does not reach it on its own.
                        // ADR-0012 makes the Accessibility Inspector a per-screen gate, and this is the
                        // one control on a placeholder that could fail it.
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(24)
        // One VoiceOver container per placeholder: the sentence, then the button, in that order.
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Offline — a supported mode, not a fault") {
    StateView(state: LoadState<Int>.offline, copy: StateCopy(empty: "home.empty"), reload: {}) { _ in
        EmptyView()
    }
    .hwTheme()
}

#Preview("Failed — and it does read as a fault") {
    StateView(
        state: LoadState<Int>.failed(.rateLimited),
        copy: StateCopy(empty: "home.empty"),
        reload: {}
    ) { _ in
        EmptyView()
    }
    .hwTheme()
}
#endif
