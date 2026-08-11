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
