/// The `/v1` paths the app calls.
///
/// One owner per path. The literal was previously repeated by the view model, the composition root, and
/// the preview helpers, which is three places for one string to drift in. Tests deliberately keep their
/// own literals so that a path change fails a test rather than being silently agreed to.
enum Endpoint {
    /// The budget engine's own endpoint — the only place 50/30/20, `saved`, and the goal verdict are computed
    /// (invariant 3).
    ///
    /// **No screen reads it any more** (ADR-0020). Home did, and a screen that composes four responses is a
    /// screen that derives the join; the engine now feeds `GET /v1/screens/home` server-side. It stays declared
    /// because the engine still has one exposure point and the invariant still names it.
    static let budget = "/v1/budget"

    // MARK: - Screens

    /// `GET /v1/screens/home` — **the single request Home makes** (ADR-0020). Everything on the screen arrives
    /// computed: the "% of pay" readout, the meter percentage, the goal verdict, the selected tip, the streak,
    /// and the article teasers.
    static let screenHome = "/v1/screens/home"

    /// `GET /v1/screens/expenses` — **the single read Expenses makes** (ADR-0020, #18). The monthly summary and
    /// its three-way split, the wants-bar state, every per-category running total, and each entry's
    /// "Today / Yesterday / N days ago" label all arrive computed — the client sums nothing and owns no
    /// calendar.
    static let screenExpenses = "/v1/screens/expenses"

    /// `GET /v1/screens/learn` — **the per-user half of Learn** (ADR-0020, ADR-0034): the streak, the XP, which
    /// lesson is next, every lesson's unlock state, and the two counts each progress ring is drawn from.
    ///
    /// Learn is the one screen that reads a second endpoint, and ``curriculum`` is it. That is not an exception to
    /// "one read per screen" — it is invariant 8 deciding where the seam goes: the curriculum is the same bytes for
    /// everybody and is stored with an ETag, while everything here is per-user and bypasses every cache. The client
    /// joins the two **by lesson id**, which is a lookup rather than a calculation.
    static let screenLearn = "/v1/screens/learn"

    // MARK: - Learn

    /// `POST /v1/learn/lessons/{id}/complete` — a finished lesson, with **one result per question** (#20).
    ///
    /// The client grades for responsiveness and this is what makes that safe (invariant 10): the submission
    /// carries which step each answer belonged to and whether it was right, the server recomputes the XP from
    /// them, and it **refuses** an impossible one — a lesson whose predecessor is unfinished, a result naming a
    /// step that is not a question, a question answered twice. A `422` is therefore a definite failure rather
    /// than something to retry differently.
    ///
    /// Answers with the **completion payload** (``LessonCompletion``), which carries the updated Learn screen
    /// inside it (ADR-0020) — so the XP, the accuracy, and the streak the reader is shown all arrive computed and
    /// the map behind the player re-renders from server truth rather than from a client patch.
    static func lessonCompletion(lessonID: String) -> String {
        "\(learnLessons)/\(pathSegment(lessonID))/complete"
    }

    /// The collection the completion route hangs off. Declared so that a parameterised route is still a path the
    /// fixture corpus can be checked against — the same reason ``articles`` is declared.
    static let learnLessons = "/v1/learn/lessons"

    /// `POST /v1/learn/progress` — how far into a lesson the reader got, so an interrupted run is not lost.
    ///
    /// **The same facts as a completion, reported early**: which step they reached and how each question went. The
    /// server decides what that means for the ring (`LessonProgress.filledSegments`), which is why the client
    /// sends the results rather than the count — a count would be the client working out a figure the screen then
    /// draws (ADR-0020).
    ///
    /// Answers with the updated Learn screen payload, and a failure is **nobody's problem**: the reader has left
    /// the lesson, there is no queue (ADR-0019), and a partial position that did not save costs them the tail of
    /// one run rather than anything they earned.
    static let learnProgress = "/v1/learn/progress"

    // MARK: - Expenses

    /// `POST /v1/expenses` — one new entry in a `log` category.
    ///
    /// **The `Idempotency-Key` route the header was written for.** `APIClient.post` keys every `POST`, and this
    /// is the one whose caller supplies its own: the Add button mints a key per *user intent* and reuses it
    /// across retries, so a write that reached the server and lost its response is not filed twice (ADR-0022).
    ///
    /// Answers with the **updated screen payload** (ADR-0020), so the totals re-render from server truth
    /// instead of the client patching its own copy — which is how a per-category total and a monthly summary
    /// come to disagree.
    static let expenses = "/v1/expenses"

    /// `DELETE /v1/expenses/{id}` — one entry, removed. Answers with the updated screen payload.
    ///
    /// The id comes from a payload, so it goes through ``pathSegment(_:)`` for the reason
    /// `ContentResource.forArticle(id:)` sanitises an article's: `appending(path:)` does not escape a slash,
    /// and an id containing one would send this request somewhere else entirely.
    static func expense(id: String) -> String { "\(expenses)/\(pathSegment(id))" }

    /// `PUT /v1/expenses/fixed/{categoryId}` — a `fixed` category's monthly amount. Rent, today.
    ///
    /// Keyed by **category** rather than named `rent`, so a second fixed cost is a payload change rather than a
    /// route. Declared as its collection so the fixture corpus can be checked against a parameterised route.
    static let fixedCosts = "/v1/expenses/fixed"

    static func fixedCost(categoryID: String) -> String { "\(fixedCosts)/\(pathSegment(categoryID))" }

    /// `PUT /v1/expenses/lines/{categoryId}` — a `lines` category's whole set of bills, replaced.
    ///
    /// One request for the whole set, because that is the gesture the design has — see ``BillLinesUpdate``.
    static let billLines = "/v1/expenses/lines"

    static func billLines(categoryID: String) -> String { "\(billLines)/\(pathSegment(categoryID))" }

    /// One path segment built from a server-supplied id, reduced to what a segment may contain.
    ///
    /// The lesson `ContentResource.forArticle(id:)` records, applied to a route: `URL.appending(path:)` leaves
    /// a `/` alone, so an id carrying one would travel up the path and address a different resource. Characters
    /// outside the set are dropped rather than escaped — an id needing escaping is a server bug worth noticing
    /// rather than papering over.
    private static func pathSegment(_ id: String) -> String {
        id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    // MARK: - Session

    /// Email and password in, a token pair out. Unauthenticated, and a `401` here means "wrong
    /// password" rather than "expired token" — see `APIClient.Authorization`.
    static let login = "/v1/auth/login"

    /// Rotation: the presented refresh token is revoked and a new pair issued. Unauthenticated, because
    /// the refresh token *is* the credential, and because a refresh that went through the session path
    /// would recurse into itself.
    static let refresh = "/v1/auth/refresh"

    /// Revokes the family server-side. **Authenticated** — which is why the two cases of
    /// `APIClient.Authorization` are not a `/v1/auth/` prefix rule; this is the exception that would
    /// break one.
    static let logout = "/v1/auth/logout"

    /// Everything the three registration steps collected, in **one** request (#15). Unauthenticated, and it
    /// answers with a token pair: a new account is signed in.
    static let register = "/v1/auth/register"

    /// The identity revalidation ADR-0008 performs on foreground. Not a screen endpoint (ADR-0020): it
    /// carries who the user is, not what any screen draws.
    static let me = "/v1/me"

    // MARK: - Content

    /// The 251 countries with their dial codes (#15).
    ///
    /// **Cacheable, and the only kind of route that is** (invariant 8): the same bytes for everybody, fetched
    /// anonymously because registration needs them before there is a session. Every per-user route bypasses
    /// every cache; these three are why the distinction exists.
    static let contentCountries = "/v1/content/reference/countries"

    /// The 160 ISO-4217 currencies (#15).
    static let contentCurrencies = "/v1/content/reference/currencies"

    /// The 14-question security bank (#15). Under `/v1/content` rather than `/v1/auth` for the reason above —
    /// the *questions* are public content; the *answers* are verified server-side and never leave it
    /// (invariant 5).
    static let contentSecurityQuestions = "/v1/content/security-questions"

    /// The tip pool — `GET /v1/content/tips`. Cacheable, and the same 49 tips for everybody (invariant 8).
    static let contentTips = "/v1/content/tips"

    /// The two Expenses pick lists — `GET /v1/content/picklists`. 22 transport modes and 20 "Other" types,
    /// cacheable because they are the same 42 options for everybody (invariant 8, ADR-0009).
    ///
    /// Under `/v1/content` rather than beside the expense routes for exactly that reason: an expense is
    /// per-user and must bypass every cache, while the list it was picked from is not.
    static let contentPicklists = "/v1/content/picklists"

    /// The whole curriculum — `GET /v1/curriculum`. 5 units, 15 lessons, 124 steps, answer keys included.
    ///
    /// **Not under `/v1/content`, and it is still cacheable.** Invariant 8 names three cacheable families —
    /// `/v1/content/*`, `/v1/curriculum*`, and `/v1/fx/rates` — so this is the second of them rather than an
    /// exception to the first. It sits on its own root because the curriculum is the *product*: the PDF (#25) and
    /// per-unit or per-locale variants hang off the same path, and burying them under `content` would make
    /// `/v1/content/curriculum/pdf` the address of the app's headline feature.
    static let curriculum = "/v1/curriculum"

    /// One article's body — `GET /v1/content/articles/scams`.
    ///
    /// **Separate from the screen payload, and cacheable** (invariant 8, ADR-0020): the teasers are per-user
    /// enough to sit inside Home's response, but a body is editorial content that is identical for everybody, and
    /// folding it in would make it per-user and throw the cache away.
    ///
    /// A function rather than a constant, so the collection path has one owner. ``articles`` is what the corpus's
    /// coverage scan reads.
    ///
    /// It goes through `ContentResource.forArticle(id:)`, so the path and the cache key are built from the same
    /// sanitised string — see that method for the collision separate sanitising produced.
    static func articleBody(id: String) -> String { path(for: .forArticle(id: id)) }

    /// The collection the article bodies hang off. Declared so that a parameterised route is still a path the
    /// fixture corpus can be checked against.
    static let articles = "/v1/content/articles"

    /// The path a cacheable resource is fetched from.
    ///
    /// Here rather than on `ContentResource` itself, which lives in `Models` and must not know what a route is
    /// (`LayeringTests`). The resource is an identity — a file name and a cache key; the path is this layer's.
    static func path(for resource: ContentResource) -> String {
        switch resource {
        case .countries: contentCountries
        case .currencies: contentCurrencies
        case .securityQuestions: contentSecurityQuestions
        case .tips: contentTips
        case .picklists: contentPicklists
        case .curriculum: curriculum
        // The id here has already been through `ContentResource.forArticle(id:)`, which is the only way to build the
        // case — so this is the *sanitised* id, and the file name and the path cannot differ.
        case .article(let id): "\(articles)/\(id)"
        }
    }

    // MARK: - Preferences

    /// The stored language preference. `PUT`, because the request replaces a value rather than adding one
    /// — which is also why it carries no `Idempotency-Key`.
    ///
    /// A route the client invented, recorded in `CONTEXT.md`'s table of changes this repo requires
    /// elsewhere. Its reason for existing is email: the header tells the server what to format *this*
    /// response in, and nothing about a message composed six hours later (ADR-0024).
    static let language = "/v1/me/language"
}
