import Foundation
import SwiftUI
import UIKit
@testable import HisaabWise

/// The two pieces of scaffolding every suite here needs, in one place.
///
/// Both were copied between suites before: the fixture base URL five times and the `ImageRenderer`
/// incantation twice. Neither is interesting enough to be worth reading twice, and a render size that
/// drifted between suites would make two suites disagree about what "renders" means.
enum TestBench {
    /// Where a client under test points. Deliberately unresolvable: a test that reached the network
    /// should fail, not succeed slowly.
    static let baseURL = URL(string: "https://fixtures.invalid")!

    /// The two hosted legal pages, on the same unreachable host. A suite never opens them — what the tests care
    /// about is that the graph carries what the build configuration said, not what is at the other end.
    static let legal = LegalLinks(
        terms: URL(string: "https://fixtures.invalid/terms")!,
        privacy: URL(string: "https://fixtures.invalid/privacy")!
    )

    /// A client over `transport`, in a language the test picked.
    ///
    /// `@MainActor` because the language manager is, and the real one is what goes in: `LanguageSource`
    /// is a dependency direction, not a seam, so no suite here has a double for it (ADR-0013).
    ///
    /// - Parameter refreshTokens: the store the client refreshes from. Defaults to an **empty in-memory**
    ///   one, so a suite that is not about the session gets a client with no session — and no suite
    ///   writes a credential to the Keychain of the machine it runs on.
    @MainActor
    static func client(
        _ transport: some Transport,
        in language: AppLanguage = .english,
        refreshTokens: any TokenStore = InMemoryTokenStore()
    ) -> APIClient {
        APIClient(
            baseURL: baseURL,
            transport: transport,
            language: LanguageManager(selected: language),
            refreshTokens: refreshTokens
        )
    }

    /// A client over `transport` for a language manager the test already holds, with the graph's cycle
    /// closed exactly as `AppEnvironment` closes it.
    ///
    /// The real `APIClient` rather than a double, because `LanguageSink` is a dependency direction and not
    /// a seam (ADR-0013): a test that stubbed the sink would assert that `LanguageManager` calls something,
    /// which is not the interesting claim. What is interesting is that a request reaches the transport
    /// carrying the new language, and only the real client can show that.
    @MainActor
    static func connect(
        _ language: LanguageManager,
        to transport: some Transport,
        refreshTokens: any TokenStore = InMemoryTokenStore()
    ) -> APIClient {
        let client = APIClient(
            baseURL: baseURL,
            transport: transport,
            language: language,
            refreshTokens: refreshTokens
        )
        language.connect(to: client)
        return client
    }

    /// A transport that answers `PUT /v1/me/language` by agreeing to `language`.
    ///
    /// The happy path four suites need, in one place — and the body comes from the **corpus** rather than being
    /// assembled here (ADR-0013). The shape matters: a narrow decode reads its one field out of the wider screen
    /// payload ADR-0020 will eventually put around it, and a copy of that shape written in the test target is
    /// the copy that would keep passing after the real one moved.
    static func languageTransport(agreeingTo language: AppLanguage) -> FixtureTransport {
        FixtureTransport(
            stubs: [Endpoint.language: .response(status: 200, body: languagePreference(language))]
        )
    }

    /// The body `PUT /v1/me/language` answers with, for the suites that need a *disagreeing* one.
    static func languagePreference(_ language: AppLanguage) -> Data {
        switch language {
        case .english: payload(.languageEnglish)
        case .arabic: payload(.languageArabic)
        }
    }

    /// The identity the corpus's `GET /v1/me` payloads describe.
    ///
    /// So that an assertion about who is signed in reads the fixture rather than repeating its email — a
    /// literal in a test is the copy nobody updates when the payload changes.
    static let identity: SessionUser = {
        do {
            return try JSONDecoder().decode(SessionUser.self, from: payload(.meVerified))
        } catch {
            preconditionFailure("The corpus's me-verified.json no longer decodes as SessionUser: \(error)")
        }
    }()

    /// A fixture's bytes, for the many places a stub needs a body and cannot throw.
    ///
    /// **It traps**, deliberately: a missing fixture file is not a test outcome, it is a bundle assembled
    /// wrong, and it reproduces for every suite. Returning empty `Data` instead would turn one broken
    /// resource into a dozen unrelated decoding failures. `FixtureCorpusTests` is what reports it properly.
    static func payload(_ fixture: Fixture) -> Data {
        do {
            return try fixture.data()
        } catch {
            preconditionFailure("The fixture \(fixture.rawValue).json is not in the bundle: \(error)")
        }
    }

    // MARK: - Session

    /// A syntactically real access token: three base64url segments, the middle one carrying the claims
    /// ``AccessToken`` reads.
    ///
    /// Unsigned — the segment where a signature goes holds a literal. Nothing in the client verifies one
    /// (it holds no key, and the server is what decides a token is acceptable), so a fake signature here
    /// exercises exactly what a real one would.
    ///
    /// - Parameters:
    ///   - expiresIn: seconds of life from now. Negative for an already-dead token; under
    ///     `AccessToken.refreshWindow` for one the client should refresh before using.
    ///   - securityEpoch: the `sec` claim, or `nil` to leave it out.
    static func accessToken(expiresIn: TimeInterval = 900, securityEpoch: Int? = 3) -> String {
        let exp = Int(Date().addingTimeInterval(expiresIn).timeIntervalSince1970)
        let claims = securityEpoch.map { #"{"exp":\#(exp),"sec":\#($0)}"# } ?? #"{"exp":\#(exp)}"#
        return "\(base64URL(#"{"alg":"HS256","typ":"JWT"}"#)).\(base64URL(claims)).not-a-signature"
    }

    /// A `200` body in the shape `POST /v1/auth/login` and `/refresh` answer with.
    static func tokenPair(access: String, refresh: String) -> Data {
        Data(#"{"accessToken":"\#(access)","refreshToken":"\#(refresh)"}"#.utf8)
    }

    /// A coordinator that is signed in, over a fixture transport.
    ///
    /// Signed in by actually signing in, rather than by setting a flag: `isSignedIn` is `private(set)` and
    /// the point of the shell's tests is what the *real* sequence leaves behind. Both stores are in-memory,
    /// so no suite writes a credential to the machine it runs on.
    @MainActor
    static func signedInSession() async throws -> SessionCoordinator {
        let kept = InMemoryTokenStore()
        let transport = FixtureTransport(stubs: [
            // Minted rather than taken from the corpus: `session-tokens.json` carries an `exp` in 2100 so that
            // the *shape* is stable, and a session test needs a token with a live clock in it.
            Endpoint.login: .response(
                status: 200,
                body: tokenPair(access: accessToken(), refresh: "refresh-1")
            ),
            Endpoint.me: .response(status: 200, body: payload(.meVerified)),
            Endpoint.logout: .response(status: 200, body: payload(.logoutAcknowledged)),
        ])
        let session = SessionCoordinator(
            client: client(transport, refreshTokens: kept),
            keptStore: kept,
            transientStore: InMemoryTokenStore()
        )
        try await session.signIn(email: identity.email, password: "a-long-password", keepMeSignedIn: false)
        return session
    }

    /// The claims a token carries, read back the way the server would read them — so a test can assert
    /// on what was *presented* rather than on what the client believes it holds.
    static func claims(inJWT token: String) throws -> [String: Int] {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { throw ClaimsUnreadable.notThreeSegments }
        var encoded = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = encoded.count % 4
        if remainder > 0 { encoded += String(repeating: "=", count: 4 - remainder) }
        guard let payload = Data(base64Encoded: encoded) else { throw ClaimsUnreadable.notBase64URL }
        return try JSONDecoder().decode([String: Int].self, from: payload)
    }

    enum ClaimsUnreadable: Error { case notThreeSegments, notBase64URL }

    private static func base64URL(_ json: String) -> String {
        Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Renders through the real environment rather than touching `body`.
    ///
    /// Views here read `ThemeManager` from `@Environment`, so poking at `body` would trap on a missing
    /// object and prove nothing about the real hierarchy. This is a smoke test by design — pinned
    /// snapshots arrive with the snapshot harness (issue #9).
    @MainActor
    static func render(_ view: some View) -> UIImage? {
        ImageRenderer(content: view.hwTheme().frame(width: 390, height: 300)).uiImage
    }

    /// The size a view actually wants at a phone's width, with the height left to the content.
    ///
    /// The measuring counterpart of ``render(_:)``, which pins the height and so cannot tell a label that
    /// wrapped from one that was cut off. Width is fixed because that is the constraint a phone imposes;
    /// height is not, because growing downwards is exactly what copy in a longer language must be free to
    /// do. Doubled copy that comes back the same height as single copy has been truncated.
    @MainActor
    static func measure(_ view: some View) -> CGSize? {
        ImageRenderer(content: view.hwTheme().frame(width: 390)).uiImage?.size
    }
}
