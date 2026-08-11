#if DEBUG
import Foundation

/// The fixture corpus: canned HTTP response bodies, read by the decoding tests and by the SwiftUI
/// previews from the same files (ADR-0013). One corpus, two consumers — so drift breaks a test.
///
/// **Payloads, not domain objects.** Every entry here is bytes as they would arrive from the server, so a
/// preview and a test go through the same decoding the app does. Handing a view a ready-made `BudgetSummary`
/// would be more convenient and would let a fixture drift from the API in silence, which is the whole thing
/// this arrangement exists to prevent.
///
/// **Every fixture says which endpoint it answers**, and `FixtureCorpusTests` reads `Endpoint.swift` to
/// assert that no path in the app is left without one. That is what keeps the corpus honest as endpoints
/// arrive: the coverage is derived from the source rather than from a list somebody remembers to extend.
enum Fixture: String, CaseIterable, Sendable {
    /// `GET /v1/budget` for a user paid in rupees.
    ///
    /// ADR-0013 makes the INR fixture the **default** preview deliberately: defect D1 was a
    /// hardcoded `AED 8,000` on Home, and against this fixture such a figure is visible in Xcode at
    /// design time rather than waiting for a regression test.
    case budgetINR = "budget-inr"

    /// `GET /v1/budget` in dirhams — **and the figure is `AED 8,000`, on purpose.**
    ///
    /// It is the exact number the prototype hardcoded (defect D1), so a screen that has quietly gone back to
    /// hardcoding it looks *right* against this fixture and wrong against every other. Which is why the INR
    /// one is the default and this one is the exception a test reaches for.
    case budgetAED = "budget-aed"

    /// `GET /v1/budget` with a **blank** `income.display` — the corpus's deliberate drift.
    ///
    /// ADR-0013's claim is that a fixture which has drifted from the API breaks a test rather than rotting a
    /// preview. That claim needs one fixture that has drifted, or it is untested; this is it, and
    /// `FixtureCorpusTests` asserts it fails to decode for the reason it should
    /// (``MoneyDecodingError/missingDisplayString``) rather than merely failing.
    ///
    /// **Blank rather than absent, and byte-identical to ``budgetINR`` otherwise.** A missing key fails
    /// through `Decodable`'s generated initialiser and would pass whatever `Money` decided; a blank string is
    /// refused by `Money`'s own guard, which is ADR-0003's rule that the client has no formatter to fall back
    /// on. Keeping every other field means the failure cannot move to a different one as `BudgetSummary`
    /// grows the rest of §5 — which is what a drifted fixture missing six fields would eventually have done.
    case budgetDrifted = "budget-drifted"

    /// A corpus of `Money` values spanning the exponents in circulation — 2, 3 (KWD/BHD/OMR), and
    /// 0 (JPY/KRW).
    case moneyExponents = "money-exponents"

    /// `POST /v1/auth/login` and `POST /v1/auth/refresh` — one shape for both, because rotation means a
    /// refresh answers with exactly what a login does (ADR-0023).
    ///
    /// The access token's `exp` is in **2100**: a canned token cannot carry a moving expiry, and one dated in
    /// the past would make every client that read it refresh immediately. So this fixture is for the *shape* —
    /// the suites that exercise refreshing keep minting tokens with a live clock, and say so.
    case sessionTokens = "session-tokens"

    /// `GET /v1/me` for a user who has verified their email.
    case meVerified = "me-verified"

    /// `GET /v1/me` before verification — the state ADR-0008's foreground revalidation exists to pick up,
    /// since the user verifies in Safari and the app never sees it happen.
    case meUnverified = "me-unverified"

    /// `POST /v1/auth/logout`, which answers with nothing to read (``Acknowledgement``).
    case logoutAcknowledged = "logout-acknowledged"

    /// `PUT /v1/me/language`, agreeing to Arabic.
    case languageArabic = "language-arabic"

    /// `GET /v1/content/reference/countries` — all 251, as the design's own `COUNTRIES` constant carries them.
    ///
    /// **The counts are the acceptance test** (the workspace's content rules), so the corpus holds the whole
    /// list rather than a trimmed sample: a picker built against six countries is a picker whose search box and
    /// scroll position have never been exercised.
    case referenceCountries = "reference-countries"

    /// `GET /v1/content/reference/currencies` — all 160.
    case referenceCurrencies = "reference-currencies"

    /// `GET /v1/content/security-questions` — the 14-question bank, keyed `sq01`…`sq14`.
    ///
    /// The ids are the client's own: the design carries the English text and nothing else, and §4.3 **[FIX]**
    /// makes the id the identity. Recorded in `CONTEXT.md` as a shape the backend has to agree to.
    case referenceSecurityQuestions = "reference-security-questions"

    /// `PUT /v1/me/language`, answering English.
    ///
    /// Both languages are in the corpus because the switch's failure case is a server that answers with a
    /// *different* language than the one asked for (ADR-0024) — so a test needs the other one on the wire, and
    /// generating it at the call site would put a second copy of the shape in the test target.
    case languageEnglish = "language-english"

    /// The `/v1` paths this fixture is a response for — usually one, and **empty** for the entries that are
    /// not a response to anything: ``moneyExponents`` is a corpus of values, not a payload.
    ///
    /// This is what makes coverage checkable rather than asserted: `FixtureCorpusTests` reads every path out
    /// of `Endpoint.swift` and requires each to be claimed here.
    var endpoints: [String] {
        switch self {
        case .budgetINR, .budgetAED, .budgetDrifted: [Endpoint.budget]
        // Two paths, one set of bytes: a refresh answers with a login's shape, which is the whole of
        // ADR-0023's rotation decision expressed as a fixture.
        // Three paths, one set of bytes: a refresh answers with a login's shape (ADR-0023), and so does
        // registration — a new account is signed in by the same token pair (#15).
        case .sessionTokens: [Endpoint.login, Endpoint.refresh, Endpoint.register]
        case .meVerified, .meUnverified: [Endpoint.me]
        case .logoutAcknowledged: [Endpoint.logout]
        case .languageArabic, .languageEnglish: [Endpoint.language]
        case .referenceCountries: [Endpoint.path(for: .countries)]
        case .referenceCurrencies: [Endpoint.path(for: .currencies)]
        case .referenceSecurityQuestions: [Endpoint.path(for: .securityQuestions)]
        case .moneyExponents: []
        }
    }

    func data() throws -> Data {
        // Resolved against the app bundle rather than `Bundle.main`, so the same call works from the
        // app, from a preview, and from the unit-test bundle hosted inside the app.
        guard let url = Bundle.app.url(forResource: rawValue, withExtension: "json") else {
            throw FixtureError.notFound(name: rawValue)
        }
        return try Data(contentsOf: url)
    }

    func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try JSONDecoder().decode(Value.self, from: try data())
    }
}

enum FixtureError: Error, Equatable, Sendable {
    case notFound(name: String)
}

extension Bundle {
    /// The bundle this app's code was loaded from.
    static let app = Bundle(for: BundleToken.self)
}

/// Exists only to give ``Bundle/app`` a class to locate. Swift has no other way to ask.
private final class BundleToken {}
#endif
