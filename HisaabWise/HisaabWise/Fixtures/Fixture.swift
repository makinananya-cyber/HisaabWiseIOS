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

    /// `GET /v1/screens/home` — the whole screen in one response (ADR-0020, #17).
    ///
    /// **Its `saved` is byte-identical to ``budgetINR``'s**, and that is the D1 regression test's anchor: the
    /// screen payload is assembled from the budget engine, so a figure that differs between the two means the
    /// assembly derived rather than read. `FixtureCorpusTests` asserts the two agree.
    case homeINR = "home-inr"

    /// `GET /v1/screens/home` for an account with nothing logged — the grey ring, a zero meter, and no streak.
    ///
    /// A *response*, not an absence: "no categories" and "a new account" are the same empty array and different
    /// screens, so the payload says which (`spending.isFirstRun`).
    case homeFirstRun = "home-first-run"

    /// `GET /v1/screens/expenses` — the whole screen in one response (ADR-0020, ADR-0033, #18), **and what
    /// every Expenses write answers with**.
    ///
    /// One payload claiming four paths, which is ADR-0020's write rule expressed as a fixture: a create, a
    /// delete, a rent update, and a bills update all return the updated screen, so a corpus with a separate
    /// body per write would be four chances to describe a contract that has one shape.
    ///
    /// **It is the same month as ``homeINR``**, down to the display string: `₹5,539` spent, over the design's
    /// own figures. `FixtureCorpusTests` asserts the two agree, because Home's donut and Expenses' summary read
    /// one budget engine (invariant 3) and a difference between them is a screen that has summed something.
    case expensesINR = "expenses-inr"

    /// `GET /v1/screens/expenses` for an account with nothing logged — every total zero, no entries, no bills,
    /// and no rent carried forward.
    ///
    /// A *response*, not an absence: the seven categories are structural and are all present. What is empty is
    /// each of their lists, which is what the design's `.empty` box is for.
    case expensesFirstRun = "expenses-first-run"

    /// `GET /v1/screens/expenses` with the **wants bar past its allowance** — `isOver`, and a percentage over
    /// 100 beside a fill that has clamped at 1.
    ///
    /// The over state is one of this screen's acceptance criteria and it is a *verdict* the server sends, so it
    /// needs a payload that carries one. Kept as a third file rather than assembled in a test, for the reason
    /// the corpus exists at all: a screen drawing the over state has to be previewable.
    case expensesOverBudget = "expenses-over-budget"

    /// `GET /v1/screens/learn` — the standing default, and **the same reader ``homeINR`` describes**: a four-day
    /// streak, 120 XP, and "Needs vs. Wants" next (#19).
    ///
    /// That agreement is load-bearing in the way the Home/Expenses pair is: Home's mini-card and Learn's stats read
    /// one streak and one XP total, so a difference between the two payloads is one of the two assemblies having
    /// worked something out. `FixtureCorpusTests` asserts it, down to the lesson the two point at.
    ///
    /// The state itself is the design's own shape: the two lessons before the cursor completed, the cursor
    /// **part-answered** so a ring has some arcs lit and some not, and everything after it locked.
    case learnInProgress = "learn-in-progress"

    /// `GET /v1/screens/learn` for an account that has opened nothing: one lesson available, fourteen locked, no
    /// streak, and no XP.
    ///
    /// **The sequential-unlock rule at its starting position**, which is the one arrangement where "the lesson
    /// before it" has no lesson before it — the design's `i === 0 || isDone(prev)`.
    case learnFirstRun = "learn-first-run"

    /// `GET /v1/screens/learn` with every lesson finished, and therefore **no `nextLesson` at all**.
    ///
    /// Absent rather than pointing at a sixteenth lesson, which is the only honest answer and the one a screen
    /// that assumed a cursor would crash on. Kept as a third file for the reason ``expensesOverBudget`` is: a state
    /// with its own layout has to be previewable.
    case learnComplete = "learn-complete"

    /// `POST /v1/learn/lessons/u1l3/complete` — **the lesson ``learnInProgress`` points at, finished** (#20).
    ///
    /// The pair with ``lessonRevisited`` is defect D13 as two payloads. This one is a **first** completion: three of
    /// `u1l3`'s four questions right, so 50 XP (three tens and the twenty-point bonus), 75% accuracy, and the
    /// streak grown from four days to five. Its embedded screen is the one the map re-renders from — `u1l3`
    /// completed with a full ring, `u2l1` open and named as the cursor, and the XP total moved from 120 to 170.
    ///
    /// The accuracy is deliberately **not** 100%: a screen drawing a figure it computed from its own results would
    /// look right against a perfect run and wrong against this one.
    case lessonCompleted = "lesson-completed"

    /// `POST /v1/learn/lessons/u1l1/complete` for a lesson that was **already finished** — and it earns nothing.
    ///
    /// **Defect D13's own shape** (Product Spec §7): the design adds the XP on every run, so replaying an easy
    /// lesson farms points. Here `xpEarned` is `0` and the embedded screen's XP total is byte-identical to
    /// ``learnInProgress``'s — which is what makes "a replay earns no XP" a numeric assertion rather than a
    /// reading of a headline.
    case lessonRevisited = "lesson-revisited"

    /// `GET /v1/curriculum` — **5** units, **15** lessons, **124** steps (58 teach + 66 question), answer keys
    /// intact.
    ///
    /// The counts are the acceptance test the workspace's content rules set, so the corpus carries the whole
    /// curriculum rather than a sample: the unit map draws all fifteen nodes at once, and the lesson player (#20) is
    /// written against these very steps. The prototype's own "115 steps" comment is stale — `CurriculumTests`
    /// asserts 124 **exactly**, not as a range.
    case curriculum

    /// `GET /v1/content/picklists` — **22** transport modes and **20** "Other" types.
    ///
    /// The counts are the acceptance test the workspace's content rules set, so the corpus holds both lists
    /// whole: the transport list clears `HWPickerSheet`'s twelve-row search threshold by ten, and a trimmed
    /// sample would be a sheet whose search box had never been exercised.
    case picklists

    /// `GET /v1/content/tips` — all **49** tips, `{c}` tokens verbatim, emphasis as markdown.
    ///
    /// The count is the acceptance test the workspace's content rules set, so the corpus carries the whole pool:
    /// **Show me another** cycles through it, and a trimmed sample would be a control that ran out.
    case tips

    /// `GET /v1/content/articles/scams` — one article body, with every block the design's structure has: a
    /// heading, paragraphs, a key-value list, numbered steps, a callout, and sources.
    case articleScams = "article-scams"

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

    /// The `/v1` paths this fixture is a response for — usually one, and **empty** in two cases.
    /// ``moneyExponents`` is a corpus of values rather than a payload; and where several fixtures are
    /// alternative payloads for *one* path, only one may claim it, because ``FixtureTransport/serving(_:)``
    /// refuses two fixtures for one path and the second would otherwise answer every request with the wrong
    /// month.
    ///
    /// This is what makes coverage checkable rather than asserted: `FixtureCorpusTests` reads every path out
    /// of `Endpoint.swift` and requires each to be claimed here.
    var endpoints: [String] {
        switch self {
        case .budgetINR, .budgetAED, .budgetDrifted: [Endpoint.budget]
        case .homeINR, .homeFirstRun: [Endpoint.screenHome]
        // **Four paths, one set of bytes**, which is ADR-0020's write rule as a fixture: the read and all three
        // writes answer with the same screen payload. `serving(_:)` refuses two fixtures for one path, so only
        // one of the three Expenses payloads may claim them — the standing default does, and the other two are
        // stubbed explicitly by whichever test or preview wants that month.
        case .expensesINR:
            [Endpoint.screenExpenses, Endpoint.expenses, Endpoint.fixedCosts, Endpoint.billLines]
        case .expensesFirstRun, .expensesOverBudget: []
        // Same rule as the Expenses trio: three payloads for one path, and only one may claim it (see below).
        //
        // **Two paths, one set of bytes**, which is ADR-0020's write rule again: `POST /v1/learn/progress` answers
        // with the updated Learn screen, so the read and the interim write have one shape between them. The
        // completion write does not, and that is the one asymmetry — it answers with the *celebration* and carries
        // the screen inside it (``LessonCompletion``).
        case .learnInProgress: [Endpoint.screenLearn, Endpoint.learnProgress]
        case .learnFirstRun, .learnComplete: []
        // The lesson the standing Learn payload's cursor sits on, and a replay of one already finished. Only the
        // first claims a path, because `serving(_:)` refuses two fixtures for one route and these two are
        // alternative answers to the same *kind* of request rather than to the same lesson.
        case .lessonCompleted: [Endpoint.lessonCompletion(lessonID: "u1l3")]
        case .lessonRevisited: []
        case .curriculum: [Endpoint.curriculum]
        case .tips: [Endpoint.contentTips]
        case .picklists: [Endpoint.contentPicklists]
        case .articleScams: [Endpoint.articleBody(id: "scams")]
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
