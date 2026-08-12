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
