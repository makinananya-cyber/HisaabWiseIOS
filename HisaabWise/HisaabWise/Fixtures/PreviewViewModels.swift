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
    /// The standing default preview: a user paid in rupees.
    ///
    /// Defect D1 was a hardcoded `AED 8,000` on Home. Against this fixture such a figure is visible in
    /// Xcode at design time rather than waiting for the regression test.
    @MainActor
    static var previewINRSalary: HomeViewModel {
        preview(stubbing: .response(status: 200, body: (try? Fixture.budgetINR.data()) ?? Data()))
    }

    /// Offline, which must not render as a failure.
    @MainActor
    static var previewOffline: HomeViewModel {
        preview(stubbing: .notConnected)
    }

    @MainActor
    private static func preview(stubbing outcome: FixtureTransport.Outcome) -> HomeViewModel {
        HomeViewModel(
            client: APIClient(
                baseURL: URL(string: "https://fixtures.invalid")!,
                transport: FixtureTransport(stubs: [Endpoint.budget: outcome]),
                // An explicit language rather than the device's: a preview's `Accept-Language` should
                // not depend on the Mac Xcode is running on.
                language: LanguageManager(selected: .english),
                // No session, and nothing on the device: a preview renders the stub above, and one that
                // could refresh would be a preview that reaches the Keychain of the machine drawing it.
                refreshTokens: InMemoryTokenStore()
            )
        )
    }
}
#endif
