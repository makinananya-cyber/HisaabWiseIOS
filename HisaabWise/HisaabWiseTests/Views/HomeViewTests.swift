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
        HomeViewModel(client: TestBench.client(transport))
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
        let offline = makeViewModel(FixtureTransport(stubs: ["/v1/budget": .notConnected]))
        try await offline.load()
        #expect(offline.state.isOffline)
        #expect(TestBench.render(HomeView(viewModel: offline)) != nil)

        // Failed, which draws copy from `ErrorCopy` and never from the server.
        let body = Data(#"{"error":{"code":"RATE_LIMITED"}}"#.utf8)
        let failed = makeViewModel(
            FixtureTransport(stubs: ["/v1/budget": .response(status: 429, body: body)])
        )
        try await failed.load()
        #expect(failed.state.isFailed)
        #expect(TestBench.render(HomeView(viewModel: failed)) != nil)

        // Loaded, which is the branch that reads the money and the theme.
        let loaded = makeViewModel(FixtureTransport(stubs: ["/v1/budget": try .ok(.budgetINR)]))
        try await loaded.load()
        #expect(loaded.state.value != nil)
        #expect(TestBench.render(HomeView(viewModel: loaded)) != nil)
    }

    /// Nothing in `HomeView` starts the load; the `.task` that `BaseView`'s chrome supplies does. If that
    /// ever stopped firing, every screen in the app would render a permanent spinner and no unit test that
    /// calls `load()` itself would notice.
    @Test("the chrome starts the load — the screen never asks for it")
    func chromeStartsTheLoad() async throws {
        let transport = FixtureTransport(stubs: ["/v1/budget": try .ok(.budgetINR)])
        let viewModel = makeViewModel(transport)

        _ = TestBench.render(HomeView(viewModel: viewModel))

        // Bounded rather than unbounded: the request crosses two actors, so it needs a hop or two, and a
        // wait that could never end would hang the suite instead of failing it.
        for _ in 0..<200 where viewModel.state.value == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(viewModel.state.value?.income.display == "₹65,000")
    }

    @Test("renders the exact display string the server sent")
    func rendersTheServersDisplayString() async throws {
        let transport = FixtureTransport(stubs: ["/v1/budget": try .ok(.budgetINR)])
        let viewModel = makeViewModel(transport)

        try await viewModel.load()

        // The view's loaded content is `Text(budget.income.display)`. Asserting the view model's value is
        // asserting what reaches the screen: there is no formatting step in between, which is the whole of
        // ADR-0003.
        let rendered = try #require(viewModel.state.value?.income.display)
        #expect(rendered == "₹65,000")
        // Not `INR 65,000`: symbol spacing is a server rule, and a client that got this wrong would be
        // reimplementing it.
        #expect(!rendered.contains("INR"))
    }

    /// Every key `HomeView` renders **itself**. The shared `state.*` keys belong to `StateView` and are
    /// covered by its own suite — which is the division of labour issue #11 introduced: Home writes one
    /// string, and inherits the rest.
    private static let renderedKeys = [
        "home.empty",
        "home.income.label",
        "home.income.accessibilityLabel",
    ]

    @Test("takes its own copy from the String Catalogue, not from a literal")
    func copyComesFromTheStringCatalogue() throws {
        // ADR-0011 — externalised from the first string, so Phase 5 is translation rather than relayout.
        try CatalogueCopy.expectEnglishCopy(forKeys: Self.renderedKeys)
    }

    @Test("interpolates the figure into the accessibility sentence rather than concatenating it")
    func accessibilityLabelIsAFormatString() throws {
        let entry = try CatalogueCopy.entry("home.income.accessibilityLabel")
        // The figure goes *into* the sentence, never onto it — otherwise word order is untranslatable
        // (ADR-0011, ADR-0012).
        #expect(CatalogueCopy.english(in: entry)?.contains("%@") == true)
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
