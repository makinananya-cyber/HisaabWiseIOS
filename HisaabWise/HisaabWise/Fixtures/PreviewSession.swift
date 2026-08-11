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

    /// Signed in — by **signing in**, over a fixture that answers the login and identity routes.
    ///
    /// There is no way to set `isSignedIn` from outside, deliberately (ADR-0007), so this starts a task and the
    /// preview flips to the shell a frame later. That is the same sequence the app runs, which is the point:
    /// a preview built on a fabricated flag would keep rendering after the real one stopped working.
    @MainActor
    static var previewSignedIn: SessionCoordinator {
        let transport = FixtureTransport(stubs: [
            Endpoint.login: .response(
                status: 200,
                body: Data(
                    #"{"accessToken":"\#(Self.previewAccessToken)","refreshToken":"preview-refresh"}"#.utf8
                )
            ),
            Endpoint.me: .response(
                status: 200,
                body: Data(#"{"email":"a@b.com","displayName":"Neeraj","emailVerified":true}"#.utf8)
            ),
            Endpoint.logout: .response(status: 200, body: Data("{}".utf8)),
        ])
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

    /// A syntactically real access token: three base64url segments, the middle one carrying an `exp` far
    /// enough out that a preview never refreshes. Unsigned — nothing in the client verifies a signature, so a
    /// literal in that segment exercises exactly what a real one would.
    private static var previewAccessToken: String {
        let exp = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        func segment(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(segment(#"{"alg":"HS256","typ":"JWT"}"#)).\(segment(#"{"exp":\#(exp),"sec":1}"#)).preview"
    }
}
#endif
