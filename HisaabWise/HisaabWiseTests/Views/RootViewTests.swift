import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// The root: which of the two worlds is on screen, and what the app-switcher gets to see.
///
/// Two decisions live here and nowhere else, which is why they are asserted here rather than being left to
/// a reviewer's eye. **The session decides the world** — tabs or Landing — so a sign-out has one visible
/// consequence rather than five screens each noticing. And **the privacy overlay is unconditional**
/// (ADR-0014): there is no setting, so the only thing that can be wrong about it is the phase it covers.
@Suite("The root")
@MainActor
struct RootViewTests {
    private func viewModels() -> TabViewModels {
        TabViewModels(home: HomeViewModel(client: TestBench.client(FixtureTransport())))
    }

    // MARK: - Which world

    /// **The branch, as a value.** `ImageRenderer` draws neither a `TabView` nor a `NavigationStack` — both
    /// come back as the unsupported-view glyph, byte for byte identical — so the pixel comparison this suite
    /// used to make compared two pictures of the same yellow square and would have passed with the branch
    /// inverted. `RootView.world(isSignedIn:)` is the decision, and this is it.
    @Test("the session decides the world")
    func theSessionDecidesTheWorld() {
        #expect(RootView.world(isSignedIn: true) == .shell)
        #expect(RootView.world(isSignedIn: false) == .landing)
        // Two worlds, and only two: a third would be a state no screen has been written for.
        #expect(RootWorld.allCases.count == 2)
    }

    @Test("a fresh session is signed out, so the app starts at Landing")
    func aFreshSessionStartsAtLanding() {
        let session = SessionCoordinator(
            client: TestBench.client(FixtureTransport()),
            keptStore: InMemoryTokenStore(),
            transientStore: InMemoryTokenStore()
        )

        #expect(!session.isSignedIn)
        #expect(RootView.world(isSignedIn: session.isSignedIn) == .landing)
    }

    /// The consequence the criterion names: "clears the session and returns to Landing". One object changes,
    /// and the world follows it — which is only true if the root reads the *same* coordinator the sign-out
    /// went through.
    @Test("signing out returns the root to Landing")
    func signingOutReturnsToLanding() async throws {
        let session = try await TestBench.signedInSession()
        #expect(RootView.world(isSignedIn: session.isSignedIn) == .shell)

        await session.signOut()

        #expect(RootView.world(isSignedIn: session.isSignedIn) == .landing)
    }

    /// And the root still builds with the environment it is given, in both worlds. A smoke test, and said to
    /// be one: what it catches is a missing environment object, not a layout.
    @Test("the root builds in both worlds")
    func theRootBuilds() async throws {
        let signedOut = SessionCoordinator(
            client: TestBench.client(FixtureTransport()),
            keptStore: InMemoryTokenStore(),
            transientStore: InMemoryTokenStore()
        )
        #expect(TestBench.render(RootView().environment(signedOut).environment(viewModels())) != nil)

        let signedIn = try await TestBench.signedInSession()
        #expect(TestBench.render(RootView().environment(signedIn).environment(viewModels())) != nil)
    }

    /// Every pre-auth destination, as cases of one path rather than a set of booleans — so a new screen is a
    /// case somebody adds on purpose and #15, #16, and #24 each replace one placeholder.
    @Test("the pre-auth routes are the four screens before sign-in is finished")
    func thePreAuthRoutes() {
        #expect(PreAuthRoute.allCases == [.signIn, .register, .forgotPassword, .restoreAccount])
    }

    // MARK: - The app switcher

    /// ADR-0014 — the overlay goes up when the scene stops being active, which is the moment iOS takes the
    /// snapshot. Asserted as a value across all three phases rather than at `.inactive` alone: the mistake
    /// this rule is exposed to is covering one phase and leaving another uncovered.
    @Test("the overlay covers every phase except active")
    func theOverlayCoversTheSnapshotMoment() {
        #expect(PrivacyOverlay.covers(.inactive))
        #expect(PrivacyOverlay.covers(.background))
        #expect(!PrivacyOverlay.covers(.active))
    }

    @Test("the overlay renders, and carries no figures to render")
    func theOverlayRenders() throws {
        #expect(TestBench.render(PrivacyOverlay()) != nil)
    }

    /// The phase is **passed in** rather than read inside the modifier, which is what makes this assertable
    /// at all: `scenePhase` has one reader, the composition root, and it already had one for ADR-0008's
    /// foreground sequence.
    @Test("the modifier hides the content it covers")
    func theModifierCoversWhatIsUnderIt() throws {
        // Screen-shaped content, because that is what the overlay covers in the app: an `.overlay` is
        // proposed the size of what it sits on, so a label-sized one would be a label-sized overlay.
        let content = Text(verbatim: "AED 8,000")
            .font(.hw(.display))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        let active = try #require(TestBench.render(content.hwPrivacyOverlay(covering: .active))?.pngData())
        let inactive = try #require(TestBench.render(content.hwPrivacyOverlay(covering: .inactive))?.pngData())
        let overlayAlone = try #require(TestBench.render(PrivacyOverlay())?.pngData())

        #expect(active != inactive)
        // Pixel-identical to the overlay on its own: the figure underneath is not showing through, which is
        // the entire requirement.
        #expect(inactive == overlayAlone)
    }

    /// It is not an app lock (ADR-0014). There is nothing to assert about an absent authentication step
    /// except that nothing in the overlay asks for one — no field, no biometry, no gate.
    @Test("the overlay asks for nothing — it is not an app lock")
    func theOverlayIsNotAnAppLock() throws {
        let source = try SourceTree.codeLines(
            of: SourceTree.appSources.appending(path: "Views/PrivacyOverlay.swift")
        )

        for gate in ["LocalAuthentication", "LAContext", "SecureField", "TextField", "Button", "onTapGesture"] {
            #expect(
                !source.contains { $0.contains(gate) },
                "the overlay reaches for \(gate) — returning to the app requires no authentication (ADR-0014)"
            )
        }
    }

    /// The overlay must be **up before the snapshot**, so nothing about its appearance may be animated: a
    /// cross-fade would put a half-transparent overlay — and therefore half a screen of figures — in the
    /// picture iOS keeps. The one place in the app where ADR-0012's replace-not-remove does not apply,
    /// because there was never any motion to replace.
    @Test("nothing about the overlay is animated")
    func theOverlayDoesNotAnimate() throws {
        let source = try SourceTree.codeLines(
            of: SourceTree.appSources.appending(path: "Views/PrivacyOverlay.swift")
        )

        for motion in [".animation(", ".transition(", "withAnimation"] {
            #expect(
                !source.contains { $0.contains(motion) },
                "the overlay animates — a half-faded overlay is half a screen of figures in the snapshot"
            )
        }
    }

    @Test("every key the root renders has English copy")
    func rootCopyExists() throws {
        try CatalogueCopy.expectEnglishCopy(forKeys: ["shell.mark.accessibilityLabel", "shell.unwritten.note"])
    }
}
