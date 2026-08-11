import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// Sign in: the three [FIX]es, the store the token lands in, and what the screen is allowed to say.
///
/// The interesting claims are about *what is refused and how it is described*, which is why the failure is a
/// value: "the copy never says whether the account exists" and "a tunnel is not a wrong password" are things a
/// test can state about `SignInFailure` and cannot state about a rendered sentence.
@Suite("Sign in")
@MainActor
struct SignInTests {
    /// A view model over a transport the test programmes, with in-memory stores so no suite writes a credential
    /// to the machine it runs on. Both stores come back, because *which* one got the token is the criterion.
    private struct Harness {
        let viewModel: SignInViewModel
        let kept: InMemoryTokenStore
        let transient: InMemoryTokenStore
        let transport: FixtureTransport
    }

    private func harness(
        _ stubs: [String: FixtureTransport.Outcome],
        keptRefreshToken: String? = nil
    ) -> Harness {
        let kept = InMemoryTokenStore(refreshToken: keptRefreshToken)
        let transient = InMemoryTokenStore()
        let transport = FixtureTransport(stubs: stubs)
        let session = SessionCoordinator(
            client: TestBench.client(transport, refreshTokens: kept),
            keptStore: kept,
            transientStore: transient
        )
        return Harness(
            viewModel: SignInViewModel(session: session),
            kept: kept,
            transient: transient,
            transport: transport
        )
    }

    private static func accepted() -> [String: FixtureTransport.Outcome] {
        [
            Endpoint.login: .response(
                status: 200,
                body: TestBench.tokenPair(access: TestBench.accessToken(), refresh: "refresh-1")
            ),
            Endpoint.me: .response(status: 200, body: TestBench.payload(.meVerified)),
        ]
    }

    private static func refused() -> [String: FixtureTransport.Outcome] {
        [Endpoint.login: .response(status: 401, body: Data(#"{"error":{"code":"UNAUTHENTICATED"}}"#.utf8))]
    }

    private func fill(_ viewModel: SignInViewModel, password: String = "a-long-password") {
        viewModel.email = "neeraj@example.ae"
        viewModel.password = password
    }

    // MARK: - The [FIX]es

    /// Product Spec §3.2 — the identifier is the **email**. The design asks for a username at sign-in and
    /// registration never collects one, so there is nothing for a username to be (invariant 4).
    @Test("the identifier is an email, and the word username appears nowhere")
    func theIdentifierIsEmail() throws {
        for file in ["Views/SignInView.swift", "ViewModels/SignInViewModel.swift"] {
            let code = try SourceTree.codeLines(of: SourceTree.appSources.appending(path: file))
            #expect(
                !code.contains { $0.localizedCaseInsensitiveContains("username") },
                "\(file) still names a username — the identifier is the email (Product Spec §3.2)"
            )
        }
        let view = try SourceTree.codeLines(of: SourceTree.appSources.appending(path: "Views/SignInView.swift"))
        #expect(view.contains { $0.contains("keyboardType: .emailAddress") })
        #expect(view.contains { $0.contains("textContentType: .emailAddress") })
    }

    /// Invariant 4 — 8+ characters everywhere, where the design's sign-in accepted 6.
    @Test("a password under eight characters is refused before the request")
    func shortPasswordsAreRefusedLocally() async throws {
        #expect(SignInViewModel.minimumPasswordLength == 8)
        let harness = harness([:])
        fill(harness.viewModel, password: "sevench")

        await harness.viewModel.signIn()

        #expect(harness.viewModel.failure(for: .password) == .passwordTooShort)
        // Nothing was sent: a request the client already knows will fail is a round trip the user waits for.
        #expect(await harness.transport.recordedRequests.isEmpty)
    }

    @Test("seven characters is short and eight is not")
    func theBoundaryIsEight() async throws {
        let short = harness(Self.accepted())
        fill(short.viewModel, password: "1234567")
        await short.viewModel.signIn()
        #expect(short.viewModel.failure(for: .password) == .passwordTooShort)

        let long = harness(Self.accepted())
        fill(long.viewModel, password: "12345678")
        await long.viewModel.signIn()
        #expect(long.viewModel.failure(for: .password) == nil)
    }

    @Test("empty boxes are named individually, before anything is sent")
    func emptyBoxesAreNamedIndividually() async throws {
        let harness = harness([:])

        await harness.viewModel.signIn()

        #expect(harness.viewModel.failure(for: .email) == .emailMissing)
        #expect(harness.viewModel.failure(for: .password) == .passwordMissing)
        #expect(await harness.transport.recordedRequests.isEmpty)
    }

    /// **The client does not police the shape of an address.** Every regex is wrong about somebody's real email,
    /// and the server checks it anyway — so an odd address is sent and the *server* refuses it.
    @Test("an unusual address is sent rather than rejected locally")
    func addressShapeIsTheServersBusiness() async throws {
        let harness = harness(Self.refused())
        harness.viewModel.email = "not-obviously-an-address"
        harness.viewModel.password = "a-long-password"

        await harness.viewModel.signIn()

        #expect(await harness.transport.requestCount(for: Endpoint.login) == 1)
        #expect(harness.viewModel.failure(for: .email) == nil)
    }

    // MARK: - Which store the token lands in

    /// ADR-0007's whole distinction, and #14's criterion: checked goes to the Keychain, unchecked to memory.
    @Test("keep me signed in decides the store", arguments: [true, false])
    func theCheckboxChoosesTheStore(_ keep: Bool) async throws {
        let harness = harness(Self.accepted())
        fill(harness.viewModel)
        harness.viewModel.keepMeSignedIn = keep

        await harness.viewModel.signIn()

        #expect(harness.viewModel.failures.isEmpty)
        #expect(try await harness.kept.refreshToken() == (keep ? "refresh-1" : nil))
        #expect(try await harness.transient.refreshToken() == (keep ? nil : "refresh-1"))
    }

    @Test("the box is checked to begin with, as the design draws it")
    func theBoxStartsChecked() {
        #expect(harness([:]).viewModel.keepMeSignedIn)
    }

    // MARK: - What a refusal says

    @Test("a 401 renders a field error rather than a screen failure")
    func aRefusalIsAFieldError() async throws {
        let harness = harness(Self.refused())
        fill(harness.viewModel)

        await harness.viewModel.signIn()

        #expect(harness.viewModel.failure(for: .password) == .credentialsRefused)
        #expect(harness.viewModel.formFailure == nil)
    }

    /// **The response must not leak whether an account exists.** Every reason the server can refuse collapses to
    /// one failure with one sentence — a "no account with that email" would turn the form into an address checker.
    @Test("every refusal reason produces the same failure and the same sentence")
    func refusalsAreIndistinguishable() throws {
        let reasons: [APIError] = [
            .unauthenticated,
            .server(status: 401, code: ErrorCode(rawValue: "NO_SUCH_ACCOUNT")),
            .server(status: 401, code: ErrorCode(rawValue: "WRONG_PASSWORD")),
            .server(status: 403, code: ErrorCode(rawValue: "EMAIL_NOT_VERIFIED")),
            // The statuses the first version of this mapping let through: it listed the refusals rather than the
            // faults, so anything else carried its own copy and told an attacker the address was unknown.
            .server(status: 404, code: ErrorCode(rawValue: "NO_SUCH_ACCOUNT")),
            .server(status: 409, code: ErrorCode(rawValue: "NO_SUCH_ACCOUNT")),
            .server(status: 422, code: ErrorCode(rawValue: "INVALID_EMAIL")),
        ]

        let failures = reasons.map { SignInViewModel.failure(for: $0) }

        #expect(failures.allSatisfy { $0 == .credentialsRefused })
        #expect(Set(failures.map { SignInView.copy(for: $0)?.key ?? "" }).count == 1)
    }

    /// The other side of that rule: a *fault* is not a refusal, because telling somebody "wrong password" when
    /// the server fell over sends them to reset a password that was right.
    @Test("a server fault, a rate limit, and a client bug are not refusals")
    func faultsAreNotRefusals() {
        for status in [500, 502, 429, 400] {
            let failure = SignInViewModel.failure(for: APIError.server(status: status, code: .rateLimited))
            #expect(failure != .credentialsRefused, "\(status) reads as a wrong password")
        }
    }

    /// A tunnel is not a wrong password: unreachable is its own failure, is not counted as a refusal, and is
    /// never rendered as a fault (ADR-0004).
    @Test("a transport failure is unreachable, keeps the device as it was, and is not a refusal")
    func offlineIsNotARefusal() async throws {
        // **Seeded**, because the criterion is that a transport failure does *not clear a stored session* — and
        // an empty store would pass that assertion while proving nothing.
        let harness = harness([Endpoint.login: .notConnected], keptRefreshToken: "an-existing-session")
        fill(harness.viewModel)

        await harness.viewModel.signIn()

        #expect(harness.viewModel.formFailure == .unreachable)
        #expect(harness.viewModel.failure(for: .password) == nil)
        #expect(harness.viewModel.refusals == 0)
        #expect(!harness.viewModel.suggestsSupport)
        #expect(try await harness.kept.refreshToken() == "an-existing-session")
        // The same sentence the rest of the app uses for a dead network.
        #expect(SignInView.copy(for: .unreachable)?.key == "state.offline")
    }

    @Test("support is suggested after three refusals, and never gates the request")
    func supportIsSuggestedAfterThree() async throws {
        let harness = harness(Self.refused())
        fill(harness.viewModel)

        for attempt in 1...SignInViewModel.refusalsBeforeSupport {
            await harness.viewModel.signIn()
            #expect(harness.viewModel.suggestsSupport == (attempt >= SignInViewModel.refusalsBeforeSupport))
        }

        // **The count never gates the request.** Server-side backoff is authoritative; a client that locked its
        // own user out would be a client a reinstall unlocks (#14).
        #expect(await harness.transport.requestCount(for: Endpoint.login) == 3)
        await harness.viewModel.signIn()
        #expect(await harness.transport.requestCount(for: Endpoint.login) == 4)
    }

    /// ADR-0015 — the account is inside its grace period, and that is a flow rather than a failure.
    @Test("a pending deletion is its own failure, not a generic one")
    func pendingDeletionIsDistinct() async throws {
        let body = Data(#"{"error":{"code":"ACCOUNT_PENDING_DELETION"}}"#.utf8)
        let harness = harness([Endpoint.login: .response(status: 403, body: body)])
        fill(harness.viewModel)

        await harness.viewModel.signIn()

        #expect(harness.viewModel.formFailure == .pendingDeletion)
        // Not a refusal: the credentials were right, so support is not suggested for it either.
        #expect(harness.viewModel.refusals == 0)
        #expect(SignInView.copy(for: .pendingDeletion)?.key == "signin.pendingDeletion.title")
        #expect(SignInView.copy(for: .pendingDeletion)?.key != SignInView.copy(for: .credentialsRefused)?.key)
    }

    // MARK: - The copy

    @Test("every failure has copy, and none of it is the server's")
    func everyFailureHasCopy() throws {
        let failures: [SignInFailure] = [
            .emailMissing, .passwordMissing, .passwordTooShort,
            .credentialsRefused, .pendingDeletion, .unreachable, .refused(.rateLimited),
        ]

        try CatalogueCopy.expectEnglishCopy(forKeys: failures.compactMap { SignInView.copy(for: $0)?.key })
        // No failure, no sentence: an empty string would draw an empty error row.
        #expect(SignInView.copy(for: nil) == nil)
    }

    @Test("the screen's own copy is in the String Catalogue")
    func screenCopyExists() throws {
        try CatalogueCopy.expectEnglishCopy(forKeys: [
            "signin.title.first", "signin.title.second", "signin.subtitle",
            "signin.email.label", "signin.password.label",
            "signin.keepSignedIn", "signin.forgot", "signin.action",
            "signin.register.prompt", "signin.register.action",
            "signin.error.support", "signin.pendingDeletion.action",
            "component.field.revealPassword",
        ])
    }

    @Test("clearing one field's failure leaves the others alone")
    func clearingOneFailureLeavesTheRest() async throws {
        let harness = harness([:])
        await harness.viewModel.signIn()
        #expect(harness.viewModel.failures.count == 2)

        harness.viewModel.clearFailure(for: .email)

        #expect(harness.viewModel.failure(for: .email) == nil)
        #expect(harness.viewModel.failure(for: .password) == .passwordMissing)
    }

    /// Which failure belongs beside which box. The criterion is *field-level* errors, and this is what stops a
    /// wrong password being drawn under the email.
    @Test("each failure is drawn where it belongs")
    func failuresKnowTheirField() {
        #expect(SignInFailure.emailMissing.field == .email)
        #expect(SignInFailure.passwordMissing.field == .password)
        #expect(SignInFailure.passwordTooShort.field == .password)
        #expect(SignInFailure.credentialsRefused.field == .password)
        // The three that belong to the form rather than to a box.
        #expect(SignInFailure.unreachable.field == nil)
        #expect(SignInFailure.pendingDeletion.field == nil)
        #expect(SignInFailure.refused(.rateLimited).field == nil)
    }

    // MARK: - It renders

    @Test("the screen renders")
    func itRenders() {
        let view = SignInView(
            session: SessionCoordinator(
                client: TestBench.client(FixtureTransport()),
                keptStore: InMemoryTokenStore(),
                transientStore: InMemoryTokenStore()
            ),
            onForgotPassword: {},
            onRegister: {},
            onRestoreAccount: {}
        )

        #expect(TestBench.render(view) != nil)
    }

    /// Not a `BaseView`, for the reason Landing is not: this screen writes, and `BaseViewModel` is one read and
    /// the mapping of its outcome.
    @Test("sign-in has no LoadState")
    func signInHasNoLoadState() throws {
        let view = try SourceTree.codeLines(of: SourceTree.appSources.appending(path: "Views/SignInView.swift"))
        let viewModel = try SourceTree.codeLines(
            of: SourceTree.appSources.appending(path: "ViewModels/SignInViewModel.swift")
        )

        #expect(!view.contains { $0.contains(": BaseView") })
        #expect(!viewModel.contains { $0.contains("BaseViewModel") })
        #expect(!viewModel.contains { $0.contains("LoadState") })
    }
}
