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
