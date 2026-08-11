import Foundation
import Observation
import SwiftUI
import Synchronization
@testable import HisaabWise
import Testing

/// The localisation properties that only a rendered screen can show.
///
/// `LocalisationTests` scans the source and can only prove that the wrong things are absent. What it cannot
/// say is whether the shell actually mirrors, whether it actually grows for longer copy, or whether changing
/// the language actually reaches a view at all. Those are the claims ADR-0011 is really making.
///
/// **Why the mirroring is asserted through ``StateView`` rather than through `HomeView`.** A `BaseView`
/// render always lands on `.loading`: the chrome supplies `.task { load() }`, `load()` writes `.loading`
/// first, and `ImageRenderer` yields to the main actor before it captures — so the pixels are the spinner
/// however loaded the view model was a moment earlier. A centred spinner is symmetric, so it can prove
/// nothing about direction. `StateView` has no `.task`, and it is the view every screen's content is drawn
/// inside, so it is where an asymmetric layout can be rendered deterministically. `HomeView` is still
/// rendered here, as the smoke test it can be.
@Suite("The shell, localised")
@MainActor
struct ShellLocalisationTests {
    /// Content shaped like a screen's: a caption over a figure, leading-aligned, in a column that does not
    /// fill the width — which is what makes its position tell you which way the layout runs.
    private func screenContent() -> some View {
        StateView(state: LoadState.loaded(1), copy: StateCopy(empty: "home.empty"), reload: {}) { _ in
            VStack(alignment: .leading, spacing: 12) {
                Text("home.income.label")
                Text(verbatim: "₹65,000")
            }
            .padding()
        }
        // The frame the chrome applies, which is the part that decides where a short column sits.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Right to left

    @Test("the shell mirrors, driven by the language rather than by the device")
    func theShellMirrors() throws {
        // Through `hwLanguage(_:)`, which is what the app applies at its root — so this exercises the
        // injection as well as the layout. Setting `\.layoutDirection` by hand would prove the content can
        // mirror while leaving the thing that decides it untested.
        let arabic = TestBench.render(screenContent().hwLanguage(LanguageManager(selected: .arabic)))
        let english = TestBench.render(screenContent().hwLanguage(LanguageManager(selected: .english)))

        #expect(arabic != nil)
        #expect(english != nil)
        // Different pixels: the caption and the figure lead from the other edge. Identical renders would mean
        // the direction reached the view and changed nothing, which is how an RTL pass gets signed off
        // without having happened.
        #expect(arabic?.pngData() != english?.pngData())
    }

    @Test("a real screen renders under both directions")
    func aRealScreenRendersEitherWay() async throws {
        let transport = FixtureTransport(stubs: [Endpoint.screenHome: try .ok(.homeINR)])
        let client = TestBench.client(transport)
        let viewModel = HomeViewModel(client: client, content: ContentLoader(client: client, store: InMemoryContentStore()))
        try await viewModel.load()
        let home = HomeView(viewModel: viewModel)

        // A smoke test, and said to be one: see the note on the suite. What it catches is a screen that traps
        // under a mirrored layout — a missing environment object, a negative frame — not a mislaid edge.
        #expect(TestBench.render(home.hwLanguage(LanguageManager(selected: .arabic))) != nil)
        #expect(TestBench.render(home.hwLanguage(LanguageManager(selected: .english))) != nil)
    }

    @Test("the language sets the header, the locale, and the direction together")
    func oneChoiceSetsAllThree() {
        // Read off the manager the modifier injects all three from. A direction from one object and a locale
        // from another is the bug this shape makes unrepresentable — an Arabic screen quietly asking the
        // server for English money strings.
        let arabic = LanguageManager(selected: .arabic)

        #expect(arabic.layoutDirection == .rightToLeft)
        #expect(arabic.locale.language.languageCode?.identifier == "ar")
        #expect(arabic.acceptLanguage == "ar")
    }

    // MARK: - Without a relaunch

    @Test("a language change notifies the observers a view's body registers")
    func aChangeNotifiesObservers() async throws {
        let language = LanguageManager(selected: .english)
        let transport = TestBench.languageTransport(agreeingTo: .arabic)
        _ = TestBench.connect(language, to: transport)

        // The exact mechanism `hwLanguage(_:)` depends on: `layoutDirection` is computed from `selected`, so
        // reading it inside a `body` has to register a dependency on `selected` — and the change has to fire.
        // Rendering twice would not prove this: a fresh `ImageRenderer` re-evaluates the modifier either way,
        // so it would pass just as well with observation broken and a relaunch required.
        let notified = Mutex(false)
        withObservationTracking {
            _ = language.layoutDirection
            _ = language.locale
        } onChange: {
            // Called off the main actor, hence the lock rather than a captured `var`.
            notified.withLock { $0 = true }
        }

        try await language.select(.arabic)

        #expect(notified.withLock { $0 })
    }

    /// **The platform assumption the whole "no relaunch" requirement rests on.**
    ///
    /// Copy in this app travels as `LocalizedStringResource` values — `StateCopy`'s defaults, `ErrorCopy`'s
    /// table, every component's control copy — and every one of them is created as a literal in a type
    /// initialiser, long before a screen exists to have a locale. A `LocalizedStringResource` captures a
    /// locale at that moment, so if `Text` honoured the captured one the app's language switch would reach
    /// nothing that was written this way, and it would fail *silently*: with English-only copy there is no
    /// visible difference to notice.
    ///
    /// It does not: `Text` substitutes the **environment's** locale, which is the one `hwLanguage(_:)` sets.
    /// Asserted here rather than assumed, because the alternative would need a stamping helper at every
    /// render site in `Components/` and `DesignSystem/`, and "SwiftUI already does this" is the reason not
    /// to have one.
    @Test("Text resolves a resource against the environment's locale, not the one the resource captured")
    func resourcesFollowTheEnvironmentLocale() throws {
        // An interpolated number, because that is the part of resolution whose result is *visible*: the
        // grouping separator differs between `en_US` (1,234) and `de_DE` (1.234). Two locales the app does
        // not ship, deliberately — this asserts a SwiftUI behaviour, not a HisaabWise one, and the shipped
        // languages have identical copy today so they could not tell these apart.
        var resource = LocalizedStringResource("\(1234)")
        resource.locale = Locale(identifier: "en_US")

        let underEnglish = TestBench.render(Text(resource).environment(\.locale, Locale(identifier: "en_US")))
        let underGerman = TestBench.render(Text(resource).environment(\.locale, Locale(identifier: "de_DE")))
        #expect(underEnglish?.pngData() != underGerman?.pngData())

        // And the converse, which is why there is no stamping helper: re-pointing the resource's own locale
        // has no effect on what `Text` draws.
        var stamped = resource
        stamped.locale = Locale(identifier: "de_DE")
        #expect(TestBench.render(Text(resource))?.pngData() == TestBench.render(Text(stamped))?.pngData())
    }

    @Test("what the injection puts in the environment follows the current choice")
    func theInjectionFollowsTheChoice() async throws {
        let language = LanguageManager(selected: .english)
        let transport = TestBench.languageTransport(agreeingTo: .arabic)
        _ = TestBench.connect(language, to: transport)

        let before = TestBench.render(screenContent().hwLanguage(language))
        try await language.select(.arabic)
        let after = TestBench.render(screenContent().hwLanguage(language))

        // The same view and the same manager across one mutation. Together with the observation assertion
        // above, this is "no relaunch": the change fires, and what the modifier then injects is the new
        // direction rather than the one the process started in.
        #expect(before?.pngData() != after?.pngData())
    }

    // MARK: - Room for a longer language

    /// Copy doubled the way `-NSDoubleLocalizedStrings` doubles it: the string, a space, the string again.
    private func doubled(_ value: String) -> String {
        "\(value) \(value)"
    }

    /// A `StateCopy` whose sentences are the real English copy served twice over.
    ///
    /// Built from `LocalizedStringResource` literals with no catalogue entry behind them, which renders the
    /// literal itself — the one case where a missing key is useful rather than a defect. It is the closest a
    /// unit test gets to the pseudolanguage run, and unlike that run it fails a build.
    private func doubledCopy() throws -> StateCopy {
        let english = { (key: String) in
            try CatalogueCopy.english(in: try CatalogueCopy.entry(key)) ?? key
        }
        return StateCopy(
            loading: LocalizedStringResource(stringLiteral: doubled(try english("state.loading"))),
            empty: LocalizedStringResource(stringLiteral: doubled(try english("home.empty"))),
            offline: LocalizedStringResource(stringLiteral: doubled(try english("state.offline"))),
            retry: LocalizedStringResource(stringLiteral: doubled(try english("state.retry")))
        )
    }

    @Test("doubled copy makes the shell taller rather than being cut off")
    func doubledCopyWraps() throws {
        let single = StateCopy(empty: "state.offline")
        let doubled = try doubledCopy()

        let short = TestBench.measure(
            StateView(state: LoadState<Int>.offline, copy: single, reload: {}) { _ in EmptyView() }
        )
        let long = TestBench.measure(
            StateView(state: LoadState<Int>.offline, copy: doubled, reload: {}) { _ in EmptyView() }
        )

        let shortHeight = try #require(short?.height)
        let longHeight = try #require(long?.height)
        // Strictly taller. Equal heights would mean the extra words went somewhere the user cannot read them,
        // which is exactly what a `lineLimit` does and what the pseudolanguage run exists to reveal.
        #expect(longHeight > shortHeight)
        // And no wider: a placeholder that grew sideways has escaped the phone rather than wrapped.
        #expect(short?.width == long?.width)
    }

    @Test("every empty-handed state survives doubled copy", arguments: [
        LoadState<Int>.loading, .empty, .offline, .failed(.rateLimited),
    ])
    func everyStateSurvivesDoubledCopy(_ state: LoadState<Int>) throws {
        // Each of the four, because they are four different placeholders — a spinner with a sentence beside
        // it, a symbol with a sentence under it, and two of those with a CTA as well.
        let view = StateView(state: state, copy: try doubledCopy(), reload: {}) { _ in EmptyView() }

        #expect(TestBench.measure(view) != nil)
    }

    @Test("doubled copy at the largest accessibility size still wraps rather than clipping")
    func doubledCopyAtAX5() throws {
        // The two costs compound: twice the words at five times the type is the worst case any screen faces,
        // and it is the case ADR-0012's unclamped Dynamic Type promises to handle.
        let view = StateView(state: LoadState<Int>.offline, copy: try doubledCopy(), reload: {}) { _ in
            EmptyView()
        }

        let standard = try #require(TestBench.measure(view)?.height)
        let accessibility = try #require(TestBench.measure(view.dynamicTypeSize(.accessibility5))?.height)

        #expect(accessibility > standard)
    }
}
