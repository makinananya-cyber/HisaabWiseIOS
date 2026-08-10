import SwiftUI

/// The contract every screen conforms to, so that writing a screen is converting a design and nothing
/// else.
///
/// A conformance declares three things — the view model, the copy for its non-loaded states, and what
/// to draw when it has data — and inherits the rest: the spinner, the empty state, the offline state,
/// the failure state, the retry, the ground the screen sits on, and the `.task` that starts the load.
/// **It cannot re-invent any of them**, which is the point: five tabs times four data states is where
/// bespoke copy and bespoke VoiceOver come from (ADR-0016).
///
/// A **protocol with a defaulted `body`** rather than a container view a screen wraps itself in. Both
/// work; this one cannot be forgotten. A wrapper is opt-in, and the screen that forgets it is exactly
/// the screen that then grows its own `switch`.
///
/// **It covers the five in-app screens, not all twelve.** The chrome paints the `surface` ground and
/// ``StateView`` draws `surface` ink and `feedback.danger`; Landing and Auth sit on `brand`, which has
/// a ground and a `danger` of its own, and both appearances ship together rather than one being a mode
/// of the other (ADR-0021). Those screens are issues #13–#16 and are not conformances. Making the
/// chrome appearance-agnostic is the work to do *then*, with two real callers to shape it, rather than
/// now with one.
@MainActor
protocol BaseView: View {
    associatedtype Model: BaseViewModel
    associatedtype LoadedContent: View

    /// Held by the screen rather than read from `@Environment`, so a test or a preview can construct
    /// the screen over a fixture transport (ADR-0013).
    var viewModel: Model { get }

    /// Copy for the states in which there is nothing to draw. Only ``StateCopy/empty`` has no shared
    /// default.
    var stateCopy: StateCopy { get }

    /// The screen — the part that is actually this screen and not any other.
    @ViewBuilder func loadedContent(_ value: Model.Value) -> LoadedContent
}

extension BaseView {
    var body: some View {
        ScreenChrome(viewModel: viewModel, copy: stateCopy, loadedContent: loadedContent)
    }
}

/// What every screen has in common, as a view rather than as an extension.
///
/// It exists because a protocol extension cannot declare `@Environment` — a default `body` has no way
/// to read the theme. So the chrome is a real view that reads it, and the default `body` is one line.
///
/// **It carries the accessibility defaults**, which is ADR-0012's per-screen gate arranged so that a screen
/// passes it by conforming rather than by remembering. Four of them, and none is the screen's to repeat:
///
/// - **The screen is one container.** `children: .contain` keeps the screen's elements grouped as a screen
///   rather than flattened into whatever the five-tab shell (#5) puts around them, so VoiceOver's container
///   gestures move between screen and chrome instead of through them.
/// - **Focus order is document order.** Nothing here sets a sort priority, and nothing anywhere may — a
///   second ordering has nothing keeping it in step with the visual one, and it drifts only for the users
///   who cannot see what it disagrees with. `AccessibilityTests` asserts the absence app-wide.
/// - **Nothing clamps.** Text scales unclamped to AX5; the only clamp in the app is
///   ``HWScaling/visualisationCeiling``, applied by `hwVisualisation(replacedBy:)` and asserted to appear
///   nowhere else.
/// - **State changes are announced**, in ``StateView`` rather than here, because the taxonomy is what knows
///   that a placeholder has been replaced by a different placeholder.
///
/// What is deliberately *not* here: a heading, a screen label, or a rotor. Those are the screen's own words
/// and belong with its own content — `HWTopBar` carries the heading trait for the five tab roots.
struct ScreenChrome<Model: BaseViewModel, LoadedContent: View>: View {
    @Environment(ThemeManager.self) private var theme

    let viewModel: Model
    let copy: StateCopy
    @ViewBuilder let loadedContent: (Model.Value) -> LoadedContent

    var body: some View {
        StateView(
            state: viewModel.state,
            copy: copy,
            // The initial load and the retry are the same call on purpose: a CTA that did something
            // subtly different from the first fetch is a second code path to keep in step.
            reload: { await load() },
            loadedContent: loadedContent
        )
        // Fills the screen and starts at the top. Without `maxHeight` the background paints only the
        // band behind the content and the rest of the screen stays white.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // `ignoresSafeArea` on the colour alone: the ground runs under the status bar, the content
        // does not.
        .background(theme.palette.surface.background.ignoresSafeArea())
        // One container per screen — see the note above. Applied after the ground so the ground is inside
        // the container and not an element of it; a `Color` is not focusable either way, and relying on
        // that rather than saying so is how a decorative element becomes a swipe stop later.
        .accessibilityElement(children: .contain)
        .task { await load() }
        // The layout direction and the locale are **not** set here. Both come from the app's
        // `LanguageManager` at the root, through `hwLanguage(_:)`: Landing and Auth are not `BaseView`
        // conformances (ADR-0021) and have to mirror too, so setting them in the chrome would cover five
        // screens of twelve. There is nothing left for this view to decide about direction.
    }

    private func load() async {
        // `CancellationError` is the only thing `load()` throws, and swallowing it here is what it is
        // thrown for: the screen is going away, so there is nobody to tell and no state to set.
        try? await viewModel.load()
    }
}
