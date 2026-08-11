import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// The shell: five tabs, one view model each, and one way out.
///
/// Most of what a `TabView` does is the platform's and is not worth asserting. What is worth asserting is
/// the part that is ours and that nothing would fail on: that there are five tabs and they are the five
/// the spec names, that each carries copy and a glyph that survives Arabic, that no two tabs share a view
/// model — which would make Expenses show Learn's state — and that logging out has exactly one caller.
@Suite("The five-tab shell")
@MainActor
struct AppShellTests {
    private func viewModels() -> TabViewModels {
        let client = TestBench.client(FixtureTransport())
        let content = ContentLoader(client: client, store: InMemoryContentStore())
        return TabViewModels(
            home: HomeViewModel(client: client, content: content),
            expenses: ExpensesViewModel(client: client, content: content)
        )
    }

    // MARK: - Five tabs, in order

    @Test("there are five tabs, in the order the spec lists them")
    func fiveTabsInOrder() {
        #expect(AppTab.allCases == [.home, .expenses, .learn, .reports, .account])
    }

    @Test("every tab has its own title and its own glyph")
    func everyTabIsDistinct() {
        // Distinct titles *and* distinct icons: two tabs sharing either is a tab bar a user cannot read.
        #expect(Set(AppTab.allCases.map(\.title.key)).count == AppTab.allCases.count)
        #expect(Set(AppTab.allCases.map(\.systemImage)).count == AppTab.allCases.count)
    }

    @Test("every tab title has English copy behind it")
    func everyTitleHasCopy() throws {
        try CatalogueCopy.expectEnglishCopy(forKeys: AppTab.allCases.map(\.title.key))
    }

    /// The rule `LocalisationTests` applies app-wide, checked here against the values rather than the
    /// source: a tab glyph is chosen from a list of five and is exactly where a `.left`/`.right` symbol
    /// would slip in unnoticed, since the tab bar itself mirrors and the icon would not.
    @Test("no tab glyph encodes a direction")
    func noGlyphEncodesDirection() {
        for tab in AppTab.allCases {
            #expect(!tab.systemImage.contains("left"), "\(tab) points left in every language")
            #expect(!tab.systemImage.contains("right"), "\(tab) points right in every language")
        }
    }

    // MARK: - One view model per tab

    /// The criterion, as identity: five distinct objects. Sharing one would make two tabs render the same
    /// state, and re-making one per `body` evaluation would reset a screen every time the user switched
    /// away and back.
    @Test("each tab has a view model of its own")
    func oneViewModelPerTab() {
        let models = viewModels()
        // By identity rather than by `!==`, which is what the assertion means and which also keeps an
        // existential out of the macro's expansion — `#expect` on `AnyObject !== AnyObject` crashes SILGen in
        // Swift 6.3.3.
        let identities = models.everyModel.map(ObjectIdentifier.init)

        #expect(identities.count == AppTab.allCases.count)
        #expect(Set(identities).count == identities.count, "two tabs share a view model")
    }

    @Test("reading a tab's view model twice yields the same object")
    func viewModelsAreHeldRatherThanMade() {
        let models = viewModels()

        #expect(ObjectIdentifier(models.home) == ObjectIdentifier(models.home))
        #expect(ObjectIdentifier(models.expenses) == ObjectIdentifier(models.expenses))
    }

    // MARK: - It renders

    /// **`ImageRenderer` cannot draw a `TabView`** — it yields the "unsupported view" glyph, a yellow field
    /// with a red bar through it, rather than a tab bar. So this is not a pixel assertion and does not pretend
    /// to be one: what it proves is that the shell's `body` evaluates with the environment it is given, which
    /// is where a missing `TabViewModels` or a missing theme would trap. The tab bar's *appearance* needs a
    /// hosted render, and that is the snapshot harness's problem (#9).
    @Test("the shell builds with the environment it is handed")
    func theShellBuilds() {
        let session = SessionCoordinator(
            client: TestBench.client(FixtureTransport()),
            keptStore: InMemoryTokenStore(),
            transientStore: InMemoryTokenStore()
        )

        #expect(TestBench.render(AppShell().environment(viewModels()).environment(session)) != nil)
    }

    // MARK: - The verification banner

    /// #15 — an unverified account **can use the app** and sees a reminder above the tabs.
    ///
    /// Asserted as a value rather than through a render, for the reason the root's world branch is: the shell is
    /// a `TabView`, and `ImageRenderer` draws one as a single unsupported-view glyph whether the strip is there
    /// or not. The three inputs are the whole rule.
    @Test("the verification banner shows only for a signed-in, unverified account")
    func theVerificationBannerFollowsTheIdentity() throws {
        let verified = try JSONDecoder().decode(SessionUser.self, from: TestBench.payload(.meVerified))
        let unverified = try JSONDecoder().decode(SessionUser.self, from: TestBench.payload(.meUnverified))

        #expect(AppShell.showsVerificationBanner(for: unverified))
        #expect(!AppShell.showsVerificationBanner(for: verified))
        // **`nil` shows nothing.** The identity arrives one request after the shell does, and a banner that
        // flashed on every cold launch would be an accusation the app then withdraws.
        #expect(!AppShell.showsVerificationBanner(for: nil))
    }

    /// Three tabs are still placeholders — Learn (#19), Reports (#21), and Account (#23). Expenses stopped being
    /// one with #18, so it is asserted through its own screen below rather than here.
    @Test("every unwritten tab root renders in the state its view model starts in")
    func everyUnwrittenRootRenders() async throws {
        for tab in AppTab.allCases where tab != .home && tab != .expenses {
            let viewModel = UnwrittenScreenViewModel()
            try await viewModel.load()
            #expect(TestBench.render(UnwrittenTabRoot(tab: tab, viewModel: viewModel)) != nil, "\(tab)")
        }
    }

    /// Every tab root goes through ``BaseView``, which is what makes its four empty-handed states
    /// `StateView`'s rather than its own (ADR-0016). Asserted structurally — the conformance is the
    /// criterion, and a screen that dropped it would still compile.
    @Test("every tab root is a BaseView conformance")
    func everyRootIsABaseView() throws {
        let roots = ["HomeView.swift", "ExpensesView.swift", "UnwrittenTabRoot.swift"]

        for name in roots {
            let source = try String(
                contentsOf: SourceTree.appSources.appending(path: "Views/\(name)"),
                encoding: .utf8
            )
            #expect(source.contains(": BaseView {"), "Views/\(name) is a tab root and not a BaseView")
        }
    }

    // MARK: - The only way out

    /// "Every tab reachable from every other; the only exit is log out." The first half is what a `TabView`
    /// is; the second is a claim about the app, and this is what keeps it true — a second caller of
    /// `signOut()` in the presentation layers is a second exit, and it would not be one anybody chose.
    @Test("logging out has exactly one caller in the presentation layers")
    func logOutHasOneCaller() throws {
        var callers: [String] = []

        for layer in ["Views", "Components", "DesignSystem"] {
            for file in try SourceTree.swiftFiles(in: layer) {
                if try SourceTree.codeLines(of: file).contains(where: { $0.contains("signOut()") }) {
                    callers.append("\(layer)/\(file.lastPathComponent)")
                }
            }
        }

        #expect(callers == ["Views/LogoutControl.swift"], "the exits from the app are \(callers)")
    }

    @Test("the logout copy the design specifies is all present")
    func logoutCopyExists() throws {
        try CatalogueCopy.expectEnglishCopy(forKeys: LogoutControl.copyKeys)
    }

    /// The second half of the criterion — "then clears the session and returns to Landing". The dialog is
    /// SwiftUI's; what is ours is that confirming it ends the session, which is what the root branches on.
    @Test("confirming the dialog ends the session")
    func confirmingEndsTheSession() async throws {
        let session = try await TestBench.signedInSession()
        #expect(session.isSignedIn)

        await session.signOut()

        #expect(!session.isSignedIn)
        #expect(session.user == nil)
    }
}
