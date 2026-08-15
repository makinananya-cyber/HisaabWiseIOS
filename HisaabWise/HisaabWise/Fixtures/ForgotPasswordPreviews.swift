#if DEBUG
import Foundation

/// The recovery form in each of its three states, for the previews.
///
/// Here rather than beside the view for the reason `RegistrationPreviews` gives: assembling a client is not a
/// view's business, and `LayeringTests` asserts that no file under `Views/` names `APIClient` or `Transport`.
///
/// **Every state is reached by driving the object**, not by setting private state — the questions arrive over a
/// `FixtureTransport` exactly as they do in the app, so a preview stops rendering if the real path stops working
/// (ADR-0013).
extension ForgotPasswordViewModel {
    /// Step 1, empty.
    @MainActor
    static var preview: ForgotPasswordViewModel {
        ForgotPasswordViewModel(client: previewClient(serving: [:]))
    }

    /// Step 2, with the two questions the server answered with already loaded.
    ///
    /// Driven through `lookUpQuestions()` rather than assigned, which is why this is `async`: the questions and
    /// the answer boxes that size themselves from them are both consequences of the request.
    @MainActor
    static func previewOnIdentityStep() async -> ForgotPasswordViewModel {
        let payload = """
        {"questions":[
          {"id":"sq01","text":"What was the name of your first pet?"},
          {"id":"sq02","text":"What city were you born in?"}
        ]}
        """
        let model = ForgotPasswordViewModel(
            client: previewClient(
                serving: [Endpoint.forgotPasswordQuestions: .response(status: 200, body: Data(payload.utf8))]
            )
        )
        model.email = "neeraj@example.ae"
        await model.lookUpQuestions()
        return model
    }

    /// A client over a transport that answers the recovery routes with canned bytes.
    @MainActor
    private static func previewClient(serving stubs: [String: FixtureTransport.Outcome]) -> APIClient {
        APIClient(
            baseURL: URL(string: "https://fixtures.invalid")!,
            transport: FixtureTransport(stubs: stubs),
            language: LanguageManager(selected: .english),
            refreshTokens: InMemoryTokenStore()
        )
    }
}
#endif
