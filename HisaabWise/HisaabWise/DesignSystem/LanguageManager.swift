import Foundation
import Observation
import SwiftUI

/// The one owner of the app's language choice.
///
/// It sits beside ``ThemeManager`` for the same reason that one exists: a screen asks the graph what
/// language it is in rather than each screen deciding, so switching is one mutation rather than a
/// search through twelve files. Both are composed in `AppEnvironment` and handed down — no
/// singletons.
///
/// It owns four things, and they are four views of one choice:
///
/// - ``acceptLanguage`` — the wire. `APIClient` sets the header from *this* object on every request,
///   which is what makes the server's formatted money strings come back in the language on screen
///   (ADR-0003).
/// - ``locale`` — how a screen formats. Latin digits in both languages (ADR-0011).
/// - ``layoutDirection`` — which way a screen reads.
/// - ``shipped`` — what a picker may offer. Two languages, not the design's 87 (Product Spec §3.7
///   **[FIX]**).
///
/// **Nothing here is a mode of the device.** The device's language is only the *initial* choice; once the
/// user picks one, `LanguageManager` disagrees with the system on purpose and every screen follows this
/// object rather than `Locale.current`. That is what the injection in ``SwiftUICore/View/hwLanguage(_:)``
/// buys, and why no screen reads `Locale.current` anywhere.
@MainActor
@Observable
final class LanguageManager: LanguageSource {
    /// The language in force.
    ///
    /// `private(set)`: the only way to change it is ``select(_:)``, because a change has to reach the
    /// server too and a settable property would let a caller change the app's language without telling
    /// anyone (ADR-0024).
    private(set) var selected: AppLanguage

    /// What a picker may offer, in the order it lists them. The design's 87-language list is reference
    /// content the backend serves; this is the promise.
    let shipped = AppLanguage.shipped

    /// Where the choice is kept. Not `private`, for the reason `SessionCoordinator.keptStore` is not: the
    /// *choice* of store is made once, in `AppEnvironment`, and a suite that could not see which one it
    /// made would leave the real conformance correct and unreachable.
    let store: any LanguageStore

    /// Set once by `AppEnvironment`, after the client exists.
    ///
    /// The graph has a genuine cycle in it — the client reads the language, the language is recorded
    /// through the client — so one of the two has to be connected rather than injected, and it is
    /// cheaper for it to be this one: `APIClient` gets a `LanguageSource` that is fully formed, and the
    /// half-built state is confined to a manager nobody has called ``select(_:)`` on yet.
    private var sink: (any LanguageSink)?

    /// The explicit choice. Tests and previews use this so a request's header is a value they picked,
    /// not a property of the machine the suite runs on.
    ///
    /// - Parameter store: where the choice is kept. An in-memory store by default, so constructing a
    ///   manager in a test or a preview writes nothing to the device; the app passes the real one.
    init(selected: AppLanguage, store: any LanguageStore = InMemoryLanguageStore()) {
        self.selected = selected
        self.store = store
    }

    /// The user's stored choice if they have made one, otherwise the device's, narrowed to what the app
    /// ships.
    ///
    /// The order matters and is the point: a user who chose Arabic in the app keeps Arabic even after
    /// changing the phone's language, because an explicit choice outranks an inferred one.
    /// `Locale.preferredLanguages` is the ordered list iOS resolved from the user's settings, so an
    /// Arabic-first device gets Arabic and anything else gets English. Injectable rather than read from
    /// the system inside, so the fallback is testable without a device set to French.
    init(
        store: any LanguageStore = InMemoryLanguageStore(),
        preferring identifiers: [String] = Locale.preferredLanguages
    ) {
        self.store = store
        selected = store.language ?? AppLanguage(preferring: identifiers) ?? .english
    }

    // MARK: - What a screen reads

    var acceptLanguage: String {
        selected.rawValue
    }

    /// The locale every screen formats in, Latin digits pinned (ADR-0011).
    var locale: Locale {
        selected.locale
    }

    /// Which way the app reads.
    ///
    /// Mapped here rather than on ``AppLanguage`` because `LayoutDirection` is SwiftUI's type and
    /// `Models` holds no view code — the layering scans keep it that way.
    var layoutDirection: LayoutDirection {
        selected.isRightToLeft ? .rightToLeft : .leftToRight
    }

    // MARK: - Changing it

    /// Closes the loop between the manager and the client that speaks for it. Called once, by
    /// `AppEnvironment`.
    func connect(to sink: any LanguageSink) {
        self.sink = sink
    }

    /// Switches the app's language, and tells the server so that its emails agree with its screens.
    ///
    /// The order is deliberate, and it is **optimistic with a revert** rather than server-first:
    ///
    /// 1. ``selected`` changes, so every screen re-renders immediately — no relaunch, and no spinner
    ///    over a language switch, which is a change the user expects to be instant.
    /// 2. The request is sent, and because step 1 already happened it *carries* the new language. The
    ///    response therefore comes back formatted in the language the user just picked, which is what a
    ///    screen re-rendering from it needs (ADR-0020).
    /// 3. Only once the server has agreed is the choice written to the store. A relaunch can then never
    ///    resurrect a language the server never accepted.
    ///
    /// If any of that fails — offline, a 5xx, or a server that answers with a different language — the
    /// change is **undone** and the error is rethrown for the screen to render. Every write needs a
    /// connection (ADR-0019), and the alternative to reverting is a client and a server that disagree
    /// with nothing to notice it: Arabic screens and English email.
    ///
    /// **Selecting the language already on screen is not always a no-op.** It is one when the store holds
    /// that language, because the store is only written after the server agreed — so a stored choice is a
    /// confirmed one. It is *not* one when the language came from the device and was never sent: an
    /// Arabic-phone user whose account was registered in English sees an Arabic app and receives English
    /// mail, and tapping "العربية" has to be able to repair that rather than return silently. The proper
    /// fix is for login to carry the language the way it carries `timeZone` (ADR-0023); until it does, this
    /// is the only channel there is.
    ///
    /// - Throws: whatever the request threw, or ``SwitchFailure``.
    func select(_ language: AppLanguage) async throws {
        guard language != selected || store.language != language else { return }
        guard let sink else { throw SwitchFailure.notConnected }

        let previous = selected
        selected = language
        do {
            let confirmed = try await sink.setLanguage(language)
            guard confirmed == language else { throw SwitchFailure.serverDisagreed(confirmed) }
            store.save(language)
        } catch {
            selected = previous
            throw error
        }
    }

    /// The two ways a switch can fail that are not the request failing.
    enum SwitchFailure: Error, Equatable {
        /// `AppEnvironment` never called ``LanguageManager/connect(to:)``. An assembly bug rather than a
        /// user condition — thrown rather than trapped only so that a test can prove the silent
        /// alternative was rejected: a manager that switched the language locally and told nobody would
        /// look like it worked.
        case notConnected

        /// The server stored a different language from the one asked for. Surfaced rather than accepted,
        /// because accepting it is how screens and email come to disagree.
        case serverDisagreed(AppLanguage)
    }
}

extension View {
    /// Injects the language: the object, the locale a screen formats in, and the direction it reads in.
    ///
    /// All three together and at the root, not per screen. Landing and Auth are not ``BaseView``
    /// conformances (ADR-0021) and still have to be laid out right to left, so the direction cannot live
    /// in the screen chrome; and a screen that had to remember to set its own locale is a screen that
    /// will forget.
    ///
    /// A `ViewModifier` rather than a chain of `.environment` calls in this extension's own body, so that
    /// the reads of ``LanguageManager/locale`` and ``LanguageManager/layoutDirection`` sit in a `body` of
    /// their own. Read directly here, they would be tracked against whoever *called* the extension — and at
    /// the root that caller is `WindowGroup`'s builder closure inside a `Scene`, which is not a place to
    /// stake a re-render on. The modifier makes the observation scope the view tree, where it belongs.
    func hwLanguage(_ language: LanguageManager) -> some View {
        modifier(HWLanguageEnvironment(language: language))
    }
}

/// The three environment values a language choice sets. See ``SwiftUICore/View/hwLanguage(_:)``.
private struct HWLanguageEnvironment: ViewModifier {
    let language: LanguageManager

    func body(content: Content) -> some View {
        content
            .environment(language)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.layoutDirection)
    }
}
