#if DEBUG
import Foundation

/// View models wired over a fixture transport, for previews.
///
/// ADR-0013 — previews build a **real** view model over `FixtureTransport` rather than being handed a
/// ready-made model, so what Xcode renders is what the app does and a fixture that drifts from the API
/// breaks a test instead of quietly rotting a preview.
///
/// These live here rather than beside the views because assembling a client is not a view's business:
/// `LayeringTests` asserts that no file under `Views/` mentions `APIClient` or `Transport`, and a
/// preview helper is not an exemption from that.
extension HomeViewModel {
    /// The standing default preview: a user paid in rupees, a month with spending in it.
    ///
    /// Defect D1 was a hardcoded `AED 8,000` on Home. Against this fixture such a figure is visible in
    /// Xcode at design time rather than waiting for the regression test.
    @MainActor
    static var previewINRSalary: HomeViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.homeINR)))
    }

    /// A brand-new account: the grey ring, a zero meter, and one way forward.
    @MainActor
    static var previewFirstRun: HomeViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.homeFirstRun)))
    }

    /// Offline, which must not render as a failure.
    @MainActor
    static var previewOffline: HomeViewModel {
        preview(stubbing: .notConnected)
    }

    /// A `501` — the state every unwritten screen endpoint answers with until the backend has one, and a
    /// *failure* rather than an absence.
    @MainActor
    static var previewNotImplemented: HomeViewModel {
        preview(stubbing: .response(status: 501, body: Data()))
    }

    @MainActor
    private static func preview(stubbing outcome: FixtureTransport.Outcome) -> HomeViewModel {
        let language = LanguageManager(selected: .english)
        let client = APIClient(
            baseURL: URL(string: "https://fixtures.invalid")!,
            transport: FixtureTransport(stubs: [
                Endpoint.screenHome: outcome,
                // The tip pool, so **Show me another** works in a preview. Served from the corpus, because a
                // preview that could not cycle would be a preview of a control that does nothing.
                Endpoint.contentTips: .response(status: 200, body: TestPayload.bytes(.tips)),
            ]),
            // An explicit language rather than the device's: a preview's `Accept-Language` should
            // not depend on the Mac Xcode is running on.
            language: language,
            // No session, and nothing on the device: a preview renders the stub above, and one that
            // could refresh would be a preview that reaches the Keychain of the machine drawing it.
            refreshTokens: InMemoryTokenStore()
        )
        return HomeViewModel(
            client: client,
            // In memory, so drawing a preview leaves nothing in the Caches directory of the machine drawing it.
            content: ContentLoader(client: client, store: InMemoryContentStore())
        )
    }
}

extension ExpensesViewModel {
    /// The standing default preview: the design's own month, in rupees — the same month ``HomeViewModel/previewINRSalary``
    /// draws, so the two screens tell one story about one month.
    @MainActor
    static var previewINR: ExpensesViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.expensesINR)))
    }

    /// The wants budget passed: the bar in its danger colours, the percentage over 100, and `isOver` saying so in
    /// words as well.
    @MainActor
    static var previewOverBudget: ExpensesViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.expensesOverBudget)))
    }

    /// A brand-new month: every total zero, seven categories, and nothing logged in any of them.
    @MainActor
    static var previewFirstRun: ExpensesViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.expensesFirstRun)))
    }

    /// Offline, which must not render as a failure.
    @MainActor
    static var previewOffline: ExpensesViewModel {
        preview(stubbing: .notConnected)
    }

    /// A `501` — the state every unwritten screen endpoint answers with until the backend has one.
    @MainActor
    static var previewNotImplemented: ExpensesViewModel {
        preview(stubbing: .response(status: 501, body: Data()))
    }

    @MainActor
    private static func preview(stubbing outcome: FixtureTransport.Outcome) -> ExpensesViewModel {
        let language = LanguageManager(selected: .english)
        let client = APIClient(
            baseURL: URL(string: "https://fixtures.invalid")!,
            transport: FixtureTransport(stubs: [
                Endpoint.screenExpenses: outcome,
                // The pick lists, so a preview of the Transport form can actually open one. Served from the
                // corpus, because a preview of a picker with no options is a preview of a dead control.
                Endpoint.contentPicklists: .response(status: 200, body: TestPayload.bytes(.picklists)),
                // **Every write answers with the screen again** (ADR-0020), so pressing Add in a preview shows
                // what pressing Add does rather than a failure state.
                Endpoint.expenses: .response(status: 200, body: TestPayload.bytes(.expensesINR)),
            ]),
            language: language,
            refreshTokens: InMemoryTokenStore()
        )
        return ExpensesViewModel(
            client: client,
            content: ContentLoader(client: client, store: InMemoryContentStore())
        )
    }
}

extension LearnViewModel {
    /// The standing default preview: the same reader ``HomeViewModel/previewINRSalary`` describes — a four-day
    /// streak, 120 XP, two lessons done, and a part-answered third.
    @MainActor
    static var previewInProgress: LearnViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.learnInProgress)))
    }

    /// A reader who has opened nothing: one lesson available, fourteen locked, and the **START** badge on the first.
    @MainActor
    static var previewFirstRun: LearnViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.learnFirstRun)))
    }

    /// Every lesson finished, and therefore **no badge anywhere** — the state a screen that assumed a cursor draws
    /// wrongly, which is why it is previewable.
    @MainActor
    static var previewComplete: LearnViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.learnComplete)))
    }

    /// Offline, which must not render as a failure.
    @MainActor
    static var previewOffline: LearnViewModel {
        preview(stubbing: .notConnected, curriculum: .notConnected)
    }

    /// A `501` — the state every unwritten screen endpoint answers with until the backend has one.
    @MainActor
    static var previewNotImplemented: LearnViewModel {
        preview(stubbing: .response(status: 501, body: Data()))
    }

    /// - Parameter curriculum: what the cacheable half answers with. It defaults to the corpus's own curriculum
    ///   even for the failure previews, because that is the shape of the real thing: the curriculum is served from
    ///   the store while the per-user half is what a bad minute takes away (ADR-0019). The offline preview
    ///   overrides it, since a first-ever launch with no connection has nothing stored either.
    @MainActor
    private static func preview(
        stubbing outcome: FixtureTransport.Outcome,
        curriculum: FixtureTransport.Outcome = .response(status: 200, body: TestPayload.bytes(.curriculum))
    ) -> LearnViewModel {
        let language = LanguageManager(selected: .english)
        let client = APIClient(
            baseURL: URL(string: "https://fixtures.invalid")!,
            transport: FixtureTransport(stubs: [
                Endpoint.screenLearn: outcome,
                Endpoint.curriculum: curriculum,
            ]),
            language: language,
            refreshTokens: InMemoryTokenStore()
        )
        return LearnViewModel(
            client: client,
            // In memory, so drawing a preview leaves nothing in the Caches directory of the machine drawing it.
            content: ContentLoader(client: client, store: InMemoryContentStore())
        )
    }
}

extension ReportsViewModel {
    /// The standing default preview: the design's own six closed months, in rupees — one of each verdict, and
    /// two of the six met their goal.
    @MainActor
    static var previewArchive: ReportsViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.reportsINR)))
    }

    /// Two year groups with a total each, which is the only arrangement in which "grouped by year" is visible.
    @MainActor
    static var previewTwoYears: ReportsViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.reportsTwoYears)))
    }

    /// An account whose first month has not closed yet. **The whole screen is the empty state** here, unlike
    /// Home's first run — so this preview draws `StateView`, which is the point of having it.
    @MainActor
    static var previewEmpty: ReportsViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.reportsEmpty)))
    }

    /// Offline, which must not render as a failure.
    @MainActor
    static var previewOffline: ReportsViewModel {
        preview(stubbing: .notConnected)
    }

    /// A `501` — the state every unwritten screen endpoint answers with until the backend has one.
    @MainActor
    static var previewNotImplemented: ReportsViewModel {
        preview(stubbing: .response(status: 501, body: Data()))
    }

    @MainActor
    private static func preview(stubbing outcome: FixtureTransport.Outcome) -> ReportsViewModel {
        ReportsViewModel(
            client: APIClient(
                baseURL: URL(string: "https://fixtures.invalid")!,
                transport: FixtureTransport(stubs: [
                    Endpoint.screenReports: outcome,
                    // February's own detail, so that opening a row in a preview draws the month rather than a
                    // failure state (#22). Both archive fixtures list the month, and only this one has a payload.
                    Endpoint.screenReportsMonth(monthKey: "2026-02"):
                        .response(status: 200, body: TestPayload.bytes(.reportsMonthINR)),
                ]),
                // An explicit language rather than the device's: a preview's `Accept-Language` should not
                // depend on the Mac Xcode is running on.
                language: LanguageManager(selected: .english),
                refreshTokens: InMemoryTokenStore()
            )
        )
    }
}

extension ReportsMonthViewModel {
    /// The standing default: February 2026, the month the archive's own first bar describes.
    @MainActor
    static var previewFebruary: ReportsMonthViewModel {
        preview(monthKey: "2026-02", stubbing: .response(status: 200, body: TestPayload.bytes(.reportsMonthINR)))
    }

    /// **The same month, read in dirhams.** Every figure converted through the rates pinned at close; the verdict,
    /// the percentage, and the meter's position untouched (invariant 7).
    @MainActor
    static var previewDirhams: ReportsMonthViewModel {
        preview(monthKey: "2026-02", stubbing: .response(status: 200, body: TestPayload.bytes(.reportsMonthAED)))
    }

    /// A closed month with nothing logged in it: the empty ring, seven empty panels, and a split bar that is
    /// mostly surplus. Kept as a preview because it is a state with its own layout.
    @MainActor
    static var previewQuiet: ReportsMonthViewModel {
        preview(monthKey: "2025-11", stubbing: .response(status: 200, body: TestPayload.bytes(.reportsMonthQuiet)))
    }

    /// Offline, which must not render as a failure.
    @MainActor
    static var previewOffline: ReportsMonthViewModel {
        preview(monthKey: "2026-02", stubbing: .notConnected)
    }

    /// A `501` — the state every unwritten screen endpoint answers with until the backend has one.
    @MainActor
    static var previewNotImplemented: ReportsMonthViewModel {
        preview(monthKey: "2026-02", stubbing: .response(status: 501, body: Data()))
    }

    @MainActor
    private static func preview(
        monthKey: String,
        stubbing outcome: FixtureTransport.Outcome
    ) -> ReportsMonthViewModel {
        ReportsMonthViewModel(
            monthKey: monthKey,
            client: APIClient(
                baseURL: URL(string: "https://fixtures.invalid")!,
                transport: FixtureTransport(
                    stubs: [Endpoint.screenReportsMonth(monthKey: monthKey): outcome]
                ),
                // An explicit language rather than the device's: a preview's `Accept-Language` should not depend
                // on the Mac Xcode is running on.
                language: LanguageManager(selected: .english),
                refreshTokens: InMemoryTokenStore()
            )
        )
    }
}

extension LessonPlayerViewModel {
    /// A run on the first teaching page of `u1l1` — four pages of prose, then four questions.
    @MainActor
    static var previewTeaching: LessonPlayerViewModel {
        preview(lessonID: "u1l1")
    }

    /// The same lesson's first question, answered **right**: the mint footer, the praise line, and the explanation.
    @MainActor
    static var previewAnsweredRight: LessonPlayerViewModel {
        answered(lessonID: "u1l1", step: 4, correctly: true)
    }

    /// And answered **wrong**: a heart gone, the coral footer, and the right answer named.
    @MainActor
    static var previewAnsweredWrong: LessonPlayerViewModel {
        answered(lessonID: "u1l1", step: 4, correctly: false)
    }

    /// `u1l1`'s numeric question, open — the box with the reader's own currency symbol beside it.
    @MainActor
    static var previewNumeric: LessonPlayerViewModel {
        walk(preview(lessonID: "u1l1"), to: 6, correctly: true)
    }

    /// Three wrong answers, which is the out-of-hearts dialog.
    @MainActor
    static var previewOutOfHearts: LessonPlayerViewModel {
        walk(preview(lessonID: "u3l3"), to: nil, correctly: false)
    }

    /// A player over the corpus's own curriculum and Learn payload, on the lesson `lessonID` names.
    ///
    /// **It goes through `LearnMap`**, which is where the join lives: a preview handed a lesson without its unit
    /// would be a preview of a screen the app cannot reach.
    @MainActor
    private static func preview(lessonID: String) -> LessonPlayerViewModel {
        let client = APIClient(
            baseURL: URL(string: "https://fixtures.invalid")!,
            transport: FixtureTransport(stubs: [
                // Answered, so that finishing a lesson in a preview draws the celebration rather than a failure.
                Endpoint.lessonCompletion(lessonID: lessonID):
                    .response(status: 200, body: TestPayload.bytes(.lessonCompleted)),
            ]),
            language: LanguageManager(selected: .english),
            refreshTokens: InMemoryTokenStore()
        )
        return LessonPlayerViewModel(
            material: previewMaterial(lessonID: lessonID),
            client: client,
            onScreenUpdate: { _ in }
        )
    }

    /// Walks to `step` and answers it, so the two feedback states are previewable without a running app.
    @MainActor
    private static func answered(lessonID: String, step: Int, correctly: Bool) -> LessonPlayerViewModel {
        let player = walk(preview(lessonID: lessonID), to: step, correctly: correctly)
        answerCurrentStep(of: player, correctly: correctly)
        player.primaryAction()
        return player
    }

    /// Runs the player forward — **answering each question on the way**, and stopping if a press moves nothing.
    ///
    /// **The guard is why this is a function.** The first version pressed the button in a `while player.run.index <
    /// step` loop, which spins for ever the moment the walk crosses a question: an unanswered one is not
    /// `isReadyToCheck`, so the press does nothing and the index never moves. `u1l1`'s numeric step sits behind two
    /// single-choice ones, so "The player — a typed answer" hung Xcode rather than drawing anything. Review caught it.
    ///
    /// - Parameter step: where to stop, or `nil` for "as far as the run goes" — which for a wrong-answer walk is the
    ///   third heart.
    @MainActor
    @discardableResult
    private static func walk(
        _ player: LessonPlayerViewModel,
        to step: Int?,
        correctly: Bool
    ) -> LessonPlayerViewModel {
        while player.run.index < (step ?? player.run.stepCount), !player.run.isOutOfHearts {
            let before = player.run.index
            answerCurrentStep(of: player, correctly: correctly)
            player.primaryAction()
            if player.run.index == before {
                // A press that changed nothing means the step cannot be answered from here — stop rather than spin.
                player.primaryAction()
                if player.run.index == before { break }
            }
        }
        return player
    }

    /// Answers whatever question the player is standing on, or does nothing on a teaching page.
    @MainActor
    private static func answerCurrentStep(of player: LessonPlayerViewModel, correctly: Bool) {
        switch player.run.step {
        case .singleChoice(let question), .multiSelect(let question):
            let chosen = correctly
                ? question.answers
                : Array(question.options.indices.filter { !question.answers.contains($0) }.prefix(1))
            for option in chosen { player.choose(option) }
        case .numeric(let question):
            player.type(correctly ? question.answerText : "\(question.answer + 1)")
        case .teach, nil:
            break
        }
    }

    /// The unit, the lesson, and the currency token, joined out of the corpus exactly as the screen joins them.
    ///
    /// It **traps** on a corpus that cannot produce them, for `TestPayload.bytes(_:)`'s reason: a missing or
    /// drifted fixture is a bundle assembled wrong rather than a preview state worth drawing.
    @MainActor
    static func previewMaterial(lessonID: String) -> LearnMap.Material {
        do {
            let map = LearnMap(
                curriculum: try Fixture.curriculum.decode(Curriculum.self),
                progress: try Fixture.learnInProgress.decode(LearnScreen.self)
            )
            guard let material = map.material(forLessonID: lessonID) else {
                preconditionFailure("The corpus's curriculum has no lesson \(lessonID)")
            }
            return material
        } catch {
            preconditionFailure("The Learn corpus no longer decodes: \(error)")
        }
    }
}

extension LessonCompletionViewModel {
    /// A first completion: 50 XP earned, 75% accuracy, and the streak grown to five days.
    @MainActor
    static var previewCompleted: LessonCompletionViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.lessonCompleted)))
    }

    /// A **replay**, which earns nothing (defect D13) — the headline says so and the XP tile reads zero.
    @MainActor
    static var previewRevisited: LessonCompletionViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.lessonRevisited)))
    }

    /// No connection: the lesson has not counted, there is nothing queued, and the retry is the reader's
    /// (ADR-0019).
    @MainActor
    static var previewOffline: LessonCompletionViewModel {
        preview(stubbing: .notConnected)
    }

    /// The server refusing the submission — a `422`, which is a definite failure rather than something to retry
    /// differently (invariant 10).
    @MainActor
    static var previewRefused: LessonCompletionViewModel {
        preview(stubbing: .response(status: 422, body: Data(#"{"error":{"code":"VALIDATION_FAILED"}}"#.utf8)))
    }

    @MainActor
    private static func preview(stubbing outcome: FixtureTransport.Outcome) -> LessonCompletionViewModel {
        let lessonID = "u1l3"
        let client = APIClient(
            baseURL: URL(string: "https://fixtures.invalid")!,
            transport: FixtureTransport(stubs: [Endpoint.lessonCompletion(lessonID: lessonID): outcome]),
            language: LanguageManager(selected: .english),
            refreshTokens: InMemoryTokenStore()
        )
        return LessonCompletionViewModel(
            lessonID: lessonID,
            // Four questions, three of them right — the run the completion payload describes.
            results: (4...7).map { LessonRun.QuestionResult(stepIndex: $0, isCorrect: $0 != 7) },
            client: client,
            onScreenUpdate: { _ in }
        )
    }
}

extension ArticleViewModel {
    /// The scams article, which carries every block the structure has.
    @MainActor
    static var previewScams: ArticleViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.articleScams)))
    }

    /// Offline **with nothing stored** — the state the content store's fallback exists to make rare, and the one
    /// worth previewing because it is the only one that shows.
    @MainActor
    static var previewOffline: ArticleViewModel {
        preview(stubbing: .notConnected)
    }

    @MainActor
    private static func preview(stubbing outcome: FixtureTransport.Outcome) -> ArticleViewModel {
        let language = LanguageManager(selected: .english)
        let client = APIClient(
            baseURL: URL(string: "https://fixtures.invalid")!,
            transport: FixtureTransport(stubs: [Endpoint.articleBody(id: "scams"): outcome]),
            language: language,
            refreshTokens: InMemoryTokenStore()
        )
        return ArticleViewModel(
            id: "scams",
            content: ContentLoader(client: client, store: InMemoryContentStore())
        )
    }
}

extension AccountViewModel {
    /// The standing default preview: the account the corpus describes, paid in rupees, with a verified address.
    @MainActor
    static var previewINR: AccountViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.accountINR)))
    }

    /// The same account with its email unverified and no phone number — the two branches the standing payload does
    /// not draw.
    @MainActor
    static var previewUnverified: AccountViewModel {
        preview(stubbing: .response(status: 200, body: TestPayload.bytes(.accountUnverified)))
    }

    /// Offline, which must not render as a failure.
    @MainActor
    static var previewOffline: AccountViewModel {
        preview(stubbing: .notConnected)
    }

    /// A `501` — the state every unwritten screen endpoint answers with until the backend has one.
    @MainActor
    static var previewNotImplemented: AccountViewModel {
        preview(stubbing: .response(status: 501, body: Data()))
    }

    @MainActor
    private static func preview(stubbing outcome: FixtureTransport.Outcome) -> AccountViewModel {
        let language = LanguageManager(selected: .english)
        let client = APIClient(
            baseURL: URL(string: "https://fixtures.invalid")!,
            transport: FixtureTransport(stubs: [
                Endpoint.screenAccount: outcome,
                // **Every write answers with the screen again** (ADR-0020), so pressing Save or picking a currency
                // in a preview shows what doing it does rather than a failure state. The dirham payload for the
                // currency change, because a preview of a currency picker that repainted nothing is a preview of a
                // dead control.
                Endpoint.me: .response(status: 200, body: TestPayload.bytes(.accountINR)),
                Endpoint.currency: .response(status: 200, body: TestPayload.bytes(.accountAED)),
                Endpoint.password: .response(status: 200, body: TestPayload.bytes(.accountINR)),
                Endpoint.export: .response(status: 200, body: TestPayload.bytes(.meExport)),
                // The two reference lists the pickers are drawn from, served from the corpus for the reason
                // Expenses' pick lists are: a picker with no options is a dead control.
                Endpoint.path(for: .currencies):
                    .response(status: 200, body: TestPayload.bytes(.referenceCurrencies)),
                Endpoint.path(for: .countries):
                    .response(status: 200, body: TestPayload.bytes(.referenceCountries)),
            ]),
            // An explicit language rather than the device's: a preview's `Accept-Language` should not depend on
            // the Mac Xcode is running on.
            language: language,
            refreshTokens: InMemoryTokenStore()
        )
        // The graph's cycle is closed for the app and not here: a preview has no other four screens to repaint,
        // and an unconnected view model changes the preference and repaints nothing rather than failing.
        return AccountViewModel(
            client: client,
            content: ContentLoader(client: client, store: InMemoryContentStore()),
            language: language,
            session: SessionCoordinator(
                client: client,
                keptStore: InMemoryTokenStore(),
                transientStore: InMemoryTokenStore()
            )
        )
    }
}

extension TabViewModels {
    /// All five tabs over the corpus, with the repaint loop closed exactly as `AppEnvironment` closes it.
    ///
    /// One factory rather than the five-line literal four `RootView` previews were each carrying: a set that
    /// gained a sixth member would otherwise be four edits, and #23 was the ticket that added the fifth.
    @MainActor
    static var preview: TabViewModels {
        let account = AccountViewModel.previewINR
        let models = TabViewModels(
            home: .previewINRSalary,
            expenses: .previewINR,
            learn: .previewInProgress,
            reports: .previewArchive,
            account: account
        )
        account.connect(to: models)
        return models
    }
}

/// A fixture's bytes where a preview cannot throw.
///
/// **It traps**, deliberately, and for the reason `TestBench.payload(_:)` does: a missing fixture file is a bundle
/// assembled wrong, it reproduces in every preview, and returning empty `Data` turns one broken resource into a
/// screen that renders the failure state for no visible reason.
enum TestPayload {
    static func bytes(_ fixture: Fixture) -> Data {
        do {
            return try fixture.data()
        } catch {
            preconditionFailure("The fixture \(fixture.rawValue).json is not in the bundle: \(error)")
        }
    }
}
#endif
