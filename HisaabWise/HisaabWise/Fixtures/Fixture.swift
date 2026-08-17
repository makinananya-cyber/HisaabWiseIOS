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

    /// `GET /v1/screens/reports` — the standing archive: the design's own six closed months, in the rupees the
    /// rest of the corpus is authored in (ADR-0020, #21).
    ///
    /// **It carries one of each verdict, and two of the six met their goal** — which is §3.6's own count for the
    /// seeded months, and what makes "a hit / near / miss trio renders the server's verdict verbatim" something
    /// a test can ask of the standing payload rather than of a special one.
    ///
    /// The figures are the design's *percentages* rather than its dirhams: salary ₹65,000 to April and ₹70,000
    /// after a raise, with the goal left at ₹13,000 — §4.2's rule that a raise does not move the target, which
    /// the design's own archive quietly breaks by lifting the goal with the salary.
    case reportsINR = "reports-inr"

    /// `GET /v1/screens/reports` across a **year boundary**: December 2025, then January and February 2026.
    ///
    /// Two year groups with different totals, which is the only arrangement in which "grouped by year, with
    /// per-year savings totals" is visible at all — one group proves the header renders and nothing about the
    /// grouping. Three months, one of each verdict, so it is also the compact trio.
    case reportsTwoYears = "reports-two-years"

    /// `GET /v1/screens/reports` for an account whose first month has not closed yet — **no years, no bars**.
    ///
    /// A *response*, not an absence, and the one screen in the app where an empty payload is genuinely
    /// `LoadState.empty`: unlike Home's first run, there is no meter, no tip, and no streak left to draw beside
    /// it. An archive with nothing in it is one sentence.
    case reportsEmpty = "reports-empty"

    /// `GET /v1/screens/reports/2026-02` — **February 2026 in full**, the month the standing archive's first bar
    /// describes (ADR-0037, #22).
    ///
    /// It is that month down to the display string: `₹53,170` spent, `₹11,830` saved, "91% of goal", `near`, and
    /// the same six category shares. `FixtureCorpusTests` asserts the agreement, because the archive row and the
    /// detail are two reads of one closed month — a difference between them is one of the two assemblies having
    /// worked something out (defect D11's shape, and the same anchor the Home/Expenses pair is).
    ///
    /// **Its numbers are the design's own February, re-denominated**: the six category totals keep the
    /// prototype's proportions exactly, and `saved` is what §4.2's residual makes it — `₹65,000 − ₹47,740 −
    /// ₹5,430`. The design stored `saved: 1450` as a literal reconciled against nothing, which is the defect the
    /// residual replaces.
    case reportsMonthINR = "reports-month-inr"

    /// **The same month, read in dirhams** — and the invariant-7 regression test's other half.
    ///
    /// Converted at the month's *pinned* rate set, so every monetary figure differs and **nothing else does**:
    /// the verdict is still `near`, the percentage is still "91% of goal", the meter still sits at `0.91`, and
    /// every segment share is byte-identical. A currency change repaints the month and never changes the story
    /// (Product Spec §3.6, invariant 7).
    ///
    /// It claims no path, because ``reportsMonthINR`` claims that one and `FixtureTransport.serving(_:)` refuses
    /// two fixtures for one route — which is exactly right here: they are two *reads* of one address, and the
    /// test that matters stubs them in sequence.
    case reportsMonthAED = "reports-month-aed"

    /// `GET /v1/screens/reports/2025-11` — **a closed month with nothing logged in it.**
    ///
    /// The state that draws every branch the populated month does not: no donut slices at all (so the empty ring
    /// rather than a chart of one nothing), seven accordion panels each with an empty note, no biggest cost, and
    /// a split bar whose **surplus** segment is the large one — `₹65,000` saved against a `₹13,000` goal, which
    /// is `hit` at 500%.
    ///
    /// **A month no archive in the corpus lists**, and that is not an inconsistency: none of the three archive
    /// payloads has an empty month in it, and the detail and the archive are separate reads. The corpus asserts
    /// they agree where both describe the same month, which is February.
    case reportsMonthQuiet = "reports-month-quiet"

    /// `GET /v1/screens/account` — the whole screen in one response (ADR-0020, ADR-0038, #23), **and what
    /// every Account write answers with**.
    ///
    /// **It is the identity `me-verified.json` describes**, down to the address: `FixtureCorpusTests` asserts the
    /// two agree, because the profile header and the shell's own reading of who is signed in are two reads of one
    /// account — and a difference between them is one of the two having invented a name.
    ///
    /// **The display name is a mononym on purpose.** "Neeraj" has one word in it, so the avatar's initials are
    /// one letter — which is exactly the case the design's `split(/\s+/).slice(0, 2).map(w => w[0])` gets right
    /// by accident and a two-word name would hide. The initials are the server's here (``AccountScreen/Profile``),
    /// and a fixture that never exercised a name the rule is *about* would not be testing that.
    ///
    /// Its salary is the corpus's own ₹65,000 — the figure `home-inr.json`'s "9% of pay" is a share of, and the
    /// one `reports-inr.json` runs its archive on until the raise.
    case accountINR = "account-inr"

    /// **The same account read in dirhams** — what `PUT /v1/me/currency` answers with, and the repaint's other
    /// half.
    ///
    /// Converted at the corpus's one rate, so the salary's `display` **and its `minor`** both differ: a figure
    /// arrives converted at read (ADR-0003), which is why the client sends no monetary value with a currency
    /// change and performs no conversion of its own — it re-reads (§4.1). Everything that is not money is
    /// byte-identical, which is what makes "a currency change repaints and changes nothing else" an assertion
    /// rather than a claim.
    ///
    /// It claims no path, because ``accountINR`` claims them and `FixtureTransport.serving(_:)` refuses two
    /// fixtures for one route — which is exactly right here: they are two *reads* of one address, and the test
    /// that matters stubs them in sequence.
    case accountAED = "account-aed"

    /// `GET /v1/me/export` — the UAE PDPL access right, as bytes.
    ///
    /// **The one fixture in the corpus with no `Decodable` behind it**, and the only one there is nothing to
    /// assert about beyond its being a file: the client never decodes an export (``APIClient/bytes(at:)``), it
    /// writes it out for the user to keep. So what this exercises is the path from a request to a shareable
    /// file, and its shape is the Technical Spec's — one object per collection, which is why a single CSV of
    /// "everything" was rejected there.
    case meExport = "me-export"

    /// `POST /v1/me/password/check` accepting — the wizard's fail-fast step.
    ///
    /// **The body carries nothing worth reading**: the status is the answer, and a refusal arrives as an
    /// `APIError`. It exists as a fixture because the route exists, and an endpoint with no payload behind it is
    /// one a suite writes inline (ADR-0013).
    case passwordCheckOK = "password-check-ok"

    /// `POST /v1/auth/forgot-password/questions` — the two questions an account was set up with.
    ///
    /// The same shape an *unknown* address gets, which is the point of the route: it answers with plausible
    /// decoys rather than an error, so it cannot be asked "does this person have an account".
    case recoveryQuestions = "recovery-questions"

    /// `POST /v1/auth/forgot-password/verify` — the single-use ticket the three factors buy.
    case recoveryTicket = "recovery-ticket"

    /// `POST /v1/auth/reset-password` — a token pair the client deliberately discards.
    ///
    /// A recovery revokes **every** family, so signing this device straight back in would be the one exception
    /// to that rule. The reader goes to the form and uses the password they just chose.
    case recoveryReset = "recovery-reset"

    /// `GET /v1/screens/account` for an account that has **not verified its email and has given no phone
    /// number**.
    ///
    /// Two fields, and both draw a branch the standing payload does not: the banner beside the locked email
    /// (ADR-0031's reminder, on the screen the email belongs to), and a phone that is **absent rather than
    /// empty** — the optional-at-registration case (ADR-0031), which a fixture carrying `""` would have quietly
    /// turned into a number nobody gave.
    case accountUnverified = "account-unverified"

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
    /// whole: the transport list clears `HWOptionList`'s twelve-row search threshold by ten, and a trimmed
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
        // **Five paths, one set of bytes**, which is ADR-0020's write rule as a fixture: the read and all four
        // writes answer with the same screen payload. `serving(_:)` refuses two fixtures for one path, so only
        // one of the three Expenses payloads may claim them — the standing default does, and the other two are
        // stubbed explicitly by whichever test or preview wants that month.
        //
        // `wantsShare` is here for the same reason and is the odd one by address: it is a `/v1/me` route, because
        // the share is the user's setting rather than the month's, and it answers with the Expenses screen because
        // Expenses is where it is set (``WantsShareUpdate``).
        case .expensesINR:
            [
                Endpoint.screenExpenses,
                Endpoint.expenses,
                Endpoint.fixedCosts,
                Endpoint.billLines,
                Endpoint.wantsShare,
            ]
        case .expensesFirstRun, .expensesOverBudget: []
        // Same rule as the Expenses trio: three payloads for one path, and only one may claim it (see below).
        //
        // **Two paths, one set of bytes**, which is ADR-0020's write rule again: `POST /v1/learn/progress` answers
        // with the updated Learn screen, so the read and the interim write have one shape between them. The
        // completion write does not, and that is the one asymmetry — it answers with the *celebration* and carries
        // the screen inside it (``LessonCompletion``).
        case .learnInProgress: [Endpoint.screenLearn, Endpoint.learnProgress]
        case .learnFirstRun, .learnComplete: []
        // Same rule again: three payloads for one path, and only the standing one may claim it.
        case .reportsINR: [Endpoint.screenReports]
        case .reportsTwoYears, .reportsEmpty: []
        // Two months, two addresses — so both may claim one. The dirham payload is the *same* month as the
        // rupee one and therefore the same route, which only one fixture may hold (see ``reportsMonthAED``).
        case .reportsMonthINR: [Endpoint.screenReportsMonth(monthKey: "2026-02")]
        case .reportsMonthQuiet: [Endpoint.screenReportsMonth(monthKey: "2025-11")]
        case .reportsMonthAED: []
        // The lesson the standing Learn payload's cursor sits on, and a replay of one already finished. Only the
        // first claims a path, because `serving(_:)` refuses two fixtures for one route and these two are
        // alternative answers to the same *kind* of request rather than to the same lesson.
        // **Three paths, one set of bytes**, which is ADR-0020's write rule once more: the read, the currency
        // change, and the password change all answer with the updated account screen. `PUT /v1/me` answers with it
        // too and is **not** here — `Endpoint.me` is one path with two verbs, only one fixture may claim a path,
        // and the identity read holds it (``meVerified``). The personal write is stubbed explicitly by whichever
        // test or preview exercises it, exactly as the second Reports month is.
        // `goal` joins the list for the ADR-0020 reason the other writes are here: it answers with the
        // account screen payload, so one set of bytes serves the read and every write that returns it.
        case .accountINR:
            [Endpoint.screenAccount, Endpoint.currency, Endpoint.password, Endpoint.goal]
        case .meExport: [Endpoint.export]
        case .passwordCheckOK: [Endpoint.passwordCheck]
        case .recoveryQuestions: [Endpoint.forgotPasswordQuestions]
        case .recoveryTicket: [Endpoint.forgotPasswordVerify]
        case .recoveryReset: [Endpoint.resetPassword]
        // Same rule as the Expenses trio: three payloads for one path, and only the standing one may claim it.
        case .accountAED, .accountUnverified: []
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
