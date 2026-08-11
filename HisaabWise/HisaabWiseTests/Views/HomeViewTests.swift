import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// The last link in the walking skeleton: the view itself.
///
/// Rendering is verified properly by the pinned snapshot suite, which arrives with the snapshot harness.
/// What is asserted here is what a snapshot cannot state as a rule — that the string the view puts on
/// screen is the server's, character for character, that its own copy comes out of the String Catalogue
/// rather than a literal baked into the binary, and that it is a ``BaseView`` and so cannot have grown a
/// placeholder of its own.
@Suite("HomeView")
@MainActor
struct HomeViewTests {
    private func makeViewModel(_ transport: FixtureTransport) -> HomeViewModel {
        let client = TestBench.client(transport)
        return HomeViewModel(client: client, content: ContentLoader(client: client, store: InMemoryContentStore()))
    }

    @Test("renders in every state, through the real environment")
    func rendersInEveryState() async throws {
        // Rendered rather than poked at: the view reads `ThemeManager` from `@Environment`, so touching
        // `body` directly would trap on a missing object and prove nothing about the real hierarchy.
        //
        // One view model per state, each over a *stubbed* transport rather than a queued one:
        // `ImageRenderer` runs the `.task` that `BaseView` supplies, so a queue would be drained by the
        // render as well as by the test and the states would depend on who got there first.
        #expect(TestBench.render(HomeView(viewModel: makeViewModel(FixtureTransport()))) != nil)

        // Offline — drawn by `StateView` now, through the chrome the protocol supplies, and it must not
        // read as a fault.
        let offline = makeViewModel(FixtureTransport(stubs: [Endpoint.screenHome: .notConnected]))
        try await offline.load()
        #expect(offline.state.isOffline)
        #expect(TestBench.render(HomeView(viewModel: offline)) != nil)

        // Failed, which draws copy from `ErrorCopy` and never from the server.
        let body = Data(#"{"error":{"code":"RATE_LIMITED"}}"#.utf8)
        let failed = makeViewModel(
            FixtureTransport(stubs: [Endpoint.screenHome: .response(status: 429, body: body)])
        )
        try await failed.load()
        #expect(failed.state.isFailed)
        #expect(TestBench.render(HomeView(viewModel: failed)) != nil)

        // Loaded, which is the branch that reads the money and the theme.
        let loaded = makeViewModel(FixtureTransport(stubs: [Endpoint.screenHome: try .ok(.homeINR)]))
        try await loaded.load()
        #expect(loaded.state.value != nil)
        #expect(TestBench.render(HomeView(viewModel: loaded)) != nil)
    }

    /// Nothing in `HomeView` starts the load; the `.task` that `BaseView`'s chrome supplies does. If that
    /// ever stopped firing, every screen in the app would render a permanent spinner and no unit test that
    /// calls `load()` itself would notice.
    @Test("the chrome starts the load — the screen never asks for it")
    func chromeStartsTheLoad() async throws {
        let transport = FixtureTransport(stubs: [Endpoint.screenHome: try .ok(.homeINR)])
        let viewModel = makeViewModel(transport)

        _ = TestBench.render(HomeView(viewModel: viewModel))

        // Bounded rather than unbounded: the request crosses two actors, so it needs a hop or two, and a
        // wait that could never end would hang the suite instead of failing it.
        for _ in 0..<200 where viewModel.state.value == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(viewModel.state.value?.savings.saved.display == "₹23,000")
    }

    @Test("renders the exact display string the server sent")
    func rendersTheServersDisplayString() async throws {
        let transport = FixtureTransport(stubs: [Endpoint.screenHome: try .ok(.homeINR)])
        let viewModel = makeViewModel(transport)

        try await viewModel.load()

        // The view's loaded content is `Text(budget.income.display)`. Asserting the view model's value is
        // asserting what reaches the screen: there is no formatting step in between, which is the whole of
        // ADR-0003.
        let rendered = try #require(viewModel.state.value?.savings.saved.display)
        #expect(rendered == "₹23,000")
        // Not `INR 65,000`: symbol spacing is a server rule, and a client that got this wrong would be
        // reimplementing it.
        #expect(!rendered.contains("INR"))
    }

    /// Every key `HomeView` renders **itself**. The shared `state.*` keys belong to `StateView` and are
    /// covered by its own suite — which is the division of labour issue #11 introduced: Home writes one
    /// string, and inherits the rest.
    private static let renderedKeys = [
        "home.empty",
        "home.greeting %@ %@",
        "home.spending.caption",
        "home.spending.total",
        "home.spending.readout.accessibilityValue %@ %@",
        "home.spending.firstRun",
        "home.spending.addFirst",
        "home.spending.addMore",
        "home.savings.caption",
        "home.savings.foot.met %@",
        "home.savings.foot.nothing",
        "home.savings.foot.remaining %@ %@",
        "home.savings.meter.accessibilityValue %@ %@ %@",
        "home.tip.caption",
        "home.tip.another",
        "home.learning.caption",
        "home.learning.continue",
        "home.learning.accessibilityValue %@ %@",
        "home.reads.caption",
        "home.reads.hint",
    ]

    @Test("takes its own copy from the String Catalogue, not from a literal")
    func copyComesFromTheStringCatalogue() throws {
        // ADR-0011 — externalised from the first string, so Phase 5 is translation rather than relayout.
        try CatalogueCopy.expectEnglishCopy(forKeys: Self.renderedKeys)
    }

    @Test("interpolates the figure into the accessibility sentence rather than concatenating it")
    func accessibilityLabelIsAFormatString() throws {
        let entry = try CatalogueCopy.entry("home.savings.meter.accessibilityValue %@ %@ %@")
        // The figure goes *into* the sentence, never onto it — otherwise word order is untranslatable
        // (ADR-0011, ADR-0012).
        // **Numbered**, because it takes three arguments and a language that wants them in another order has to
        // be able to ask (ADR-0011).
        #expect(CatalogueCopy.english(in: entry)?.contains("%1$@") == true)
    }

    /// ADR-0012's rule about money and VoiceOver, at the one screen that has a figure on it: the sentence is
    /// the app's and the **figure is the server's, character for character**. Re-spelling it is the tempting
    /// mistake — "₹65,000" read out as digits sounds wrong and the fix looks local — and the client has no
    /// formatter with which to make a better one (ADR-0003).
    @Test("the figure VoiceOver reads is the server's display string, not a spelled-out number")
    func theSpokenFigureIsTheServersString() async throws {
        let viewModel = makeViewModel(FixtureTransport(stubs: [Endpoint.screenHome: try .ok(.homeINR)]))
        try await viewModel.load()
        let display = try #require(viewModel.state.value?.savings.saved.display)

        // The label the screen composes, resolved the way a `Text` would resolve it.
        let spoken = String(localized: "home.savings.meter.accessibilityValue \(display) \("₹13,000") \("177% of goal")")

        #expect(spoken.contains(display))
        // And it is a sentence rather than the bare figure: a label that was only the number would read
        // identically to the text beside it and say nothing the caption was there to say.
        #expect(spoken != display)
        // **And it resolved.** An unresolved key formats *itself* with the arguments, so the two assertions
        // above both passed for a year while VoiceOver read "home.income.accessibilityLabel ₹65,000" — the
        // failure has no other symptom, which is why it is asserted rather than looked at.
        #expect(!spoken.contains("home.savings"), "the key did not resolve — VoiceOver is reading it aloud")
    }

    @Test("supplies the one piece of copy only a screen can write, and inherits the rest")
    func suppliesOnlyItsOwnCopy() {
        let copy = HomeView(viewModel: makeViewModel(FixtureTransport())).stateCopy
        let shared = StateCopy(empty: copy.empty)

        #expect(copy.empty.key == "home.empty")
        // Shared: a screen that reworded these would be re-introducing the twenty-placeholders problem.
        #expect(copy.loading.key == shared.loading.key)
        #expect(copy.offline.key == shared.offline.key)
        #expect(copy.retry?.key == shared.retry?.key)
    }
}
