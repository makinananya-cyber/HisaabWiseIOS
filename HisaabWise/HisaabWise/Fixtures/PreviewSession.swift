#if DEBUG
import Foundation

/// Session coordinators for previews.
///
/// Here rather than beside the views for the reason `PreviewViewModels` gives: assembling a client is not a
/// view's business, and `LayeringTests` asserts that no file under `Views/` names `APIClient` or `Transport`.
extension SessionCoordinator {
    /// Signed out, which is where the app starts and what a log out returns to.
    @MainActor
    static var preview: SessionCoordinator {
        make(FixtureTransport())
    }

    /// Signed in — by **signing in**, over the corpus's own login, identity, and logout payloads.
    ///
    /// There is no way to set `isSignedIn` from outside, deliberately (ADR-0007), so this starts a task and the
    /// preview flips to the shell a frame later. That is the same sequence the app runs, which is the point:
    /// a preview built on a fabricated flag would keep rendering after the real one stopped working.
    ///
    /// The bodies are the **fixture files**, not literals written here (ADR-0013). A preview holding its own
    /// copy of the `GET /v1/me` shape is a second corpus, and the second copy is the one nobody updates.
    @MainActor
    static var previewSignedIn: SessionCoordinator {
        let fixtures: [Fixture] = [.sessionTokens, .meVerified, .logoutAcknowledged]
        guard let transport = try? FixtureTransport.serving(fixtures) else {
            // Trapping rather than quietly drawing the signed-out preview: a missing fixture file is a bundle
            // assembled wrong, it reproduces in every preview, and a canvas that silently shows the other
            // branch is how nobody finds out. The same reasoning as `TestBench.payload(_:)` (ADR-0027).
            preconditionFailure("A preview fixture is missing from the bundle: \(fixtures.map(\.rawValue))")
        }
        let session = make(transport)
        Task { try? await session.signIn(email: "a@b.com", password: "a-long-password", keepMeSignedIn: false) }
        return session
    }

    @MainActor
    private static func make(_ transport: FixtureTransport) -> SessionCoordinator {
        SessionCoordinator(
            client: APIClient(
                baseURL: URL(string: "https://fixtures.invalid")!,
                transport: transport,
                // An explicit language rather than the device's, and no session on disk: a preview must not
                // reach the Keychain of the machine drawing it.
                language: LanguageManager(selected: .english),
                refreshTokens: InMemoryTokenStore()
            ),
            keptStore: InMemoryTokenStore(),
            transientStore: InMemoryTokenStore()
        )
    }

}
#endif
