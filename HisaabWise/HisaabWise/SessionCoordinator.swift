import Observation

/// Whether anyone is signed in, and the three moments that change the answer: launch, sign-in, and
/// sign-out — plus the foreground sequence that keeps an already-answered "yes" honest.
///
/// **It lives at the app root, beside `AppEnvironment` and `AppConfig`, rather than in a layer.** Not an
/// oversight and not a fifth MVVM box: it owns no screen, so it is not a view model, and every layer
/// below it would be the wrong home for something the whole app reads. The root is where the app-wide
/// objects already are.
///
/// **It maps no errors, and cannot.** Turning an `APIError` into a `LoadState` has exactly one owner
/// (`BaseViewModel.load()`, asserted by `StateTaxonomyTests`), and the session owner is deliberately not
/// a second: what it needs from a failed request is not a state to render but the answer to "is there
/// still a session", which it asks the client. A screen renders the failure; this decides who is signed
/// in.
///
/// **`onForeground()` is a method, not an observer** (ADR-0008). A type that watched `scenePhase` itself
/// would put the sequence's ordering — refresh *then* revalidate — beyond the reach of a test, and the
/// ordering is the part that matters: revalidating first would spend the first request discovering an
/// expired token.
@MainActor
@Observable
final class SessionCoordinator {
    /// What ``RootView`` branches on: the tabs, or Landing.
    private(set) var isSignedIn = false

    /// Who is signed in, as far as the last revalidation knows. `nil` while signed out, and also while
    /// signed in on a network that has not answered yet — the session does not wait on it.
    private(set) var user: SessionUser?

    private let client: APIClient

    /// Where a kept session's refresh token goes: the Keychain, in the app.
    ///
    /// Not `private`: the graph's choice of store is the acceptance criterion, and a test that cannot see
    /// which store was handed over can only assert that *some* store received a token.
    let keptStore: any TokenStore

    /// Where an unkept one goes: memory, so it ends with the process (ADR-0007). Held rather than made
    /// per sign-in, because "ends at app termination" and "ends when this object goes away" are the same
    /// lifetime and one object is easier to assert about.
    let transientStore: any TokenStore

    /// Watches for the session ending underneath the app — a refresh the server refused, discovered by
    /// whichever screen's request happened to be in flight (ADR-0007).
    ///
    /// The coordinator's *own* requests do not need this; they reconcile with the client directly, which
    /// is what makes the common path deterministic. This covers the other callers.
    ///
    /// Held rather than discarded so the lifetime is visible, and nothing cancels it: it captures the
    /// **stream** rather than the client, so the client is free to be released, and releasing it finishes
    /// the stream and ends this loop. `[weak self]` is what keeps that from being a retain cycle in the
    /// other direction.
    private var sessionEndWatch: Task<Void, Never>?

    init(client: APIClient, keptStore: any TokenStore, transientStore: any TokenStore) {
        self.client = client
        self.keptStore = keptStore
        self.transientStore = transientStore

        let signals = client.sessionEnded
        sessionEndWatch = Task { [weak self] in
            for await _ in signals {
                self?.sessionDidEnd()
            }
        }
    }

    /// Picks up a session the Keychain kept across launches.
    ///
    /// It does not ask the store; it asks the client, which owns both halves of the answer — the access
    /// token it holds in memory and the refresh token behind the store. Two places that could each
    /// believe something about whether a session exists is one place too many.
    func restore() async {
        guard await client.hasSession else { return }
        isSignedIn = true
        await revalidate()
    }

    /// Signs in, and stores the refresh token where the checkbox said to (ADR-0007).
    ///
    /// - Parameter keepMeSignedIn: checked, the token goes to the Keychain and the session survives a
    ///   relaunch; unchecked, it stays in memory and ends at app termination. This is the whole of the
    ///   off-state Product Spec §3.2 left undefined.
    ///
    /// - Throws: whatever the sign-in request threw, unchanged. The auth screen (#14) is what turns a
    ///   refused password into copy; deciding that here would put the mapping in two places.
    func signIn(email: String, password: String, keepMeSignedIn: Bool) async throws {
        let tokens = try await client.post(
            Endpoint.login,
            body: SignInRequest(email: email, password: password),
            authorization: .anonymous,
            as: SessionTokens.self
        )

        await client.beginSession(
            tokens,
            storingRefreshTokenIn: keepMeSignedIn ? keptStore : transientStore
        )
        isSignedIn = true
        await revalidate()
    }

    /// Registers, and signs the new account in.
    ///
    /// **One request** (#15's [FIX]): the client holds all three steps in memory and sends them together, so no
    /// half-built account exists to resume. It answers with the same token pair a login does, which is why
    /// registration lands the user on Home rather than back at sign-in.
    ///
    /// The refresh token goes to the **Keychain**: somebody who has just created an account has not been offered
    /// a "keep me signed in" choice, and sending them to a sign-in screen they have never used would be the
    /// worst possible first minute. ADR-0007's choice belongs to sign-in, where it is asked.
    ///
    /// - Throws: whatever the request threw, unchanged — the screen turns an email collision into a field error,
    ///   and this is not a second place that maps errors.
    func register(_ request: RegistrationRequest) async throws {
        let tokens = try await client.post(
            Endpoint.register,
            body: request,
            authorization: .anonymous,
            as: SessionTokens.self
        )

        await client.beginSession(tokens, storingRefreshTokenIn: keptStore)
        isSignedIn = true
        await revalidate()
    }

    /// Ends the session because the user asked. Revokes it server-side where it can, and locally always.
    func signOut() async {
        await client.endSession()
        sessionDidEnd()
    }

    /// ADR-0008's foreground sequence, in order: refresh if near expiry, then revalidate the identity.
    ///
    /// The drain that used to sit between them is gone with the write queue (ADR-0019), and the content
    /// ETag revalidation that used to follow arrives with the content store (ADR-0009). What remains is
    /// the pair whose order matters, and the reason it does: revalidating first would spend the request
    /// discovering an expired token.
    ///
    /// Step 2 is what clears the "verify your email" banner after the user verified in Safari and came
    /// back (ADR-0010) — a state change the app did not cause and would otherwise never notice.
    func onForeground() async {
        guard isSignedIn else { return }
        await client.refreshIfNearExpiry()
        await revalidate()
    }

    /// Re-reads the identity, and reconciles with the client afterwards.
    ///
    /// Failures are swallowed rather than surfaced, and nothing here distinguishes them: a foreground
    /// hook has no screen to render a state on, and there is no failure of *this* request that should
    /// change who is signed in. What can change it is the session having ended underneath — which is a
    /// question for the client, not an error code to interpret.
    private func revalidate() async {
        do {
            user = try await client.get(Endpoint.me, as: SessionUser.self)
        } catch {
            // Offline, a 5xx, a cancelled task: the session is untouched by all three.
        }

        let sessionSurvived = await client.hasSession
        if !sessionSurvived {
            sessionDidEnd()
        }
    }

    private func sessionDidEnd() {
        user = nil
        isSignedIn = false
    }
}
