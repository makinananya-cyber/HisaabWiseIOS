import Foundation

/// The app's one HTTP client, and the owner of the session.
///
/// An `actor` because ADR-0007 gives it mutable session state to own: the in-memory access token and the
/// single-flight refresh task. Both are here now, and the isolation is what makes single-flight
/// expressible without a lock.
///
/// ADR-0010 — **no environment awareness and no default base URL.** The URL is a required
/// initialiser argument, injected at the composition root from build configuration, so a test can
/// point the client at a fixture without a build configuration existing and nothing in this target
/// knows what "staging" means.
///
/// **Every request that leaves here carries the same four properties**, set in ``send`` and
/// nowhere else, because each of them is one place away from being twelve:
///
/// - `Accept-Language`, from ``LanguageSource``. The server converts *and formats* money honouring it
///   (ADR-0003), so a missing header is not a localisation blemish — it is a figure in the wrong
///   language that the client has no formatter to correct.
/// - The cache bypass. Invariant 8 makes a HIT on per-user data a breach; every route this client
///   serves is per-user, so the bypass is the default rather than a per-route opt-out, and it holds
///   for the write verbs too. ``URLSessionTransport`` removes the cache outright as the other half.
/// - `Accept: application/json`. The one response shape the client can decode.
/// - `Authorization`, whenever there is a session to present it from. A property of the *request*
///   rather than of the caller, which is why ``Authorization`` defaults to ``Authorization/session``:
///   the mistake a default has to make impossible is forgetting to authenticate a per-user route, and
///   the cost of the other direction — a bearer token on a route that ignores it — is nothing.
///
/// **The session, in one place.** A 401 is answered by refreshing and retrying once; concurrent 401s
/// join one shared refresh, because rotation revokes the family when an already-revoked token is
/// presented and several refreshes racing is therefore a silent logout (ADR-0007). Read
/// ``refreshed(replacing:)`` for that mechanism; it is the most load-bearing twenty lines in the app.
actor APIClient {
    /// Whether a request presents the session.
    ///
    /// Two cases rather than a path list. ADR-0022 rejected a per-endpoint table for `Idempotency-Key`
    /// on the grounds that a table falls out of step with the routes, and the same holds here with an
    /// extra edge: `POST /v1/auth/logout` is an auth route that *does* need the session, so a
    /// `/v1/auth/` prefix rule would be wrong on its first exception.
    enum Authorization: Sendable {
        /// Presents the access token, refreshing first if it is absent or nearly expired, and answers a
        /// `401` by refreshing and retrying once.
        case session

        /// Presents nothing. Sign-in and refresh, where a `401` means "wrong password" or "this family
        /// is revoked" — never "your access token expired" — so the refresh machinery must stay out of
        /// the way rather than recursing into itself.
        case anonymous
    }

    private let baseURL: URL
    private let transport: any Transport
    private let language: any LanguageSource
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// Where the refresh token lives. `var` because "Keep me signed in" is read at sign-in, not at
    /// composition: the graph hands over the persistent store, and ``beginSession(_:storingRefreshTokenIn:)``
    /// swaps in the in-memory one when the box was left unchecked (ADR-0007).
    private var refreshTokens: any TokenStore

    /// **Never persisted** (ADR-0007). It lives for the life of the isolate and is re-minted from the
    /// refresh token after that.
    private var accessToken: AccessToken?

    /// The one refresh in flight, or `nil`. Everything single-flight rests on this being read and written
    /// only inside the actor.
    private var refreshInFlight: Task<AccessToken, any Error>?

    /// Yields once each time the session ends because the **server** refused it — a definitive `401` on
    /// refresh, which is the family-revoked case, or a `401` with nothing left to refresh with.
    ///
    /// A stream rather than a callback the client is handed, because a collaborator injected here would
    /// be a second seam and tests would start exercising a double of our own design (ADR-0013). It is a
    /// fact the client publishes; `SessionCoordinator` is the one thing that listens.
    ///
    /// **A local sign-out does not yield.** The caller of ``endSession()`` already knows.
    nonisolated let sessionEnded: AsyncStream<Void>
    private nonisolated let sessionEndedSignal: AsyncStream<Void>.Continuation

    init(
        baseURL: URL,
        transport: any Transport,
        language: any LanguageSource,
        refreshTokens: any TokenStore
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.language = language
        self.refreshTokens = refreshTokens
        (sessionEnded, sessionEndedSignal) = AsyncStream.makeStream()
    }

    // MARK: - Reads

    /// Performs a `GET` and decodes the body.
    ///
    /// Throws ``APIError/offline`` when the network did not answer, ``APIError/server(status:code:)``
    /// when it answered unsuccessfully, ``APIError/malformedResponse`` when the body did not decode, and
    /// ``APIError/unauthenticated`` when the request needed a session and there is none left.
    func get<Response: Decodable & Sendable>(
        _ path: String,
        authorization: Authorization = .session,
        as type: Response.Type
    ) async throws -> Response {
        try await perform(.get, path, body: nil, idempotencyKey: nil, authorization: authorization) {
            try self.decoder.decode(Response.self, from: $0)
        }
    }

    /// Performs a `GET` presenting the session and answers with the body **undecoded**.
    ///
    /// One caller, and it is the reason this exists rather than a convenience: `GET /v1/me/export` is the UAE
    /// PDPL access right, and what it returns is every collection this system holds about one person, streamed
    /// (Technical Spec §5). Decoding it would mean the client owning a schema for all eleven; re-encoding it to
    /// save would hand the user *this client's* idea of their data instead of the server's — which is the rule
    /// `ContentLoader` already follows about storing bytes rather than values.
    ///
    /// It goes through ``perform`` like every other request, so it carries the four properties and answers a
    /// `401` by refreshing once. What it does **not** go through is ``content(at:ifNoneMatch:)``, which is
    /// anonymous and cacheable: a per-user response may never be read from a cache (invariant 8), and an
    /// export is the most per-user response there is.
    func bytes(at path: String) async throws -> Data {
        try await perform(.get, path, body: nil, idempotencyKey: nil, authorization: .session) { $0 }
    }

    /// What a conditional `GET` on a cacheable content route answered with.
    ///
    /// `304` is a **success** here rather than a failure, which is why this cannot go through
    /// ``get(_:authorization:as:)``: that path treats anything outside `200..<300` as an error and has a
    /// decodable body to produce. A not-modified answer has no body at all — the bytes the caller wants are
    /// the ones it already has.
    enum ContentResponse: Sendable, Equatable {
        /// The stored copy is current. Nothing was downloaded.
        case notModified
        /// New bytes, and the ETag to revalidate them with next time. The ETag may be absent: a server that
        /// sends none is one whose content cannot be revalidated, which costs a download rather than
        /// correctness.
        case fetched(data: Data, etag: String?)
    }

    /// Fetches a cacheable content resource, revalidating with `If-None-Match` when there is an ETag to send.
    ///
    /// **Anonymous, and that is the invariant rather than a convenience** (invariant 8): the only responses
    /// this app may store are the ones identical for every user, and registration needs the reference lists
    /// before a session exists. A route that needed the session would be per-user by definition and could not
    /// come through here.
    ///
    /// Raw `Data` out rather than a decoded value, because the caller stores the bytes: decoding here and
    /// re-encoding to write would put the client's idea of the payload on disk rather than the server's, and
    /// the next ETag would be revalidating something that never arrived.
    func content(at path: String, ifNoneMatch etag: String?) async throws -> ContentResponse {
        let (data, response) = try await respond(
            .get, path, body: nil, idempotencyKey: nil, bearer: nil, ifNoneMatch: etag
        )

        if response.statusCode == 304 { return .notModified }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.server(status: response.statusCode, code: errorCode(in: data))
        }
        return .fetched(data: data, etag: response.value(forHTTPHeaderField: "ETag"))
    }

    // MARK: - Writes

    /// Performs a `POST` and decodes the body.
    ///
    /// **Every `POST` carries an `Idempotency-Key`**, generated here unless the caller supplies one.
    /// The backend accepts the header "where retries are plausible (expense create)", and making it a
    /// property of the verb rather than of a path list means expense create cannot be the one call
    /// that forgets it — there is no per-endpoint table to fall out of step with the routes.
    ///
    /// A caller that wants **one key per user intent** passes its own and reuses it across attempts;
    /// the generated default is one key per call. That distinction costs nothing today, because
    /// ADR-0019 removed the write queue and with it every automatic retry: nothing in this app sends
    /// the same write twice on its own. It is the caller-supplied form that will matter when a
    /// "try again" button sits in front of a write (#18).
    ///
    /// - Returns: the response body. Writes return the **updated screen payload** (ADR-0020), so a
    ///   screen re-renders from server truth instead of patching its own copy.
    func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body,
        idempotencyKey: String = UUID().uuidString,
        authorization: Authorization = .session,
        as type: Response.Type
    ) async throws -> Response {
        try await perform(
            .post,
            path,
            body: try encoder.encode(body),
            idempotencyKey: idempotencyKey,
            authorization: authorization
        ) {
            try self.decoder.decode(Response.self, from: $0)
        }
    }

    /// Performs a `PUT` and decodes the body.
    ///
    /// No `Idempotency-Key`: a `PUT` replaces a value, so sending it twice lands the caller in the
    /// same state as sending it once. A key here would be ceremony that implies otherwise.
    func put<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body,
        as type: Response.Type
    ) async throws -> Response {
        try await perform(
            .put,
            path,
            body: try encoder.encode(body),
            idempotencyKey: nil,
            authorization: .session
        ) {
            try self.decoder.decode(Response.self, from: $0)
        }
    }

    /// Performs a `DELETE` and decodes the body.
    ///
    /// A response type is required rather than optional for the ADR-0020 reason: a delete returns the
    /// screen payload the deletion produced. A `DELETE` with nothing to decode would be a route that
    /// leaves the client to guess what the list looks like now.
    func delete<Response: Decodable & Sendable>(
        _ path: String,
        as type: Response.Type
    ) async throws -> Response {
        try await perform(
            .delete,
            path,
            body: nil,
            idempotencyKey: nil,
            authorization: .session
        ) {
            try self.decoder.decode(Response.self, from: $0)
        }
    }

    // MARK: - The session

    /// Whether the client still has something to authenticate with.
    ///
    /// Asked by ``SessionCoordinator`` at launch, and again after any request, so that "am I signed in"
    /// has one answer rather than a copy the coordinator keeps and has to keep in step.
    var hasSession: Bool {
        get async {
            if accessToken != nil { return true }
            do {
                return try await storedRefreshToken() != nil
            } catch {
                // A store that cannot be read is not a store that is empty, and this question has no way
                // to say so. It answers "yes" — a session that may still be there is not one to discard,
                // and the next request will find out for certain.
                return true
            }
        }
    }

    /// Takes a freshly signed-in session, storing the refresh token where the checkbox said to.
    ///
    /// **The outgoing store is cleared first.** Signing in with the box unchecked, having previously
    /// signed in with it checked, must not leave the old refresh token in the Keychain — that is a live
    /// 60-day credential for a session the user asked not to keep.
    ///
    /// Non-throwing on purpose. A Keychain that refuses the write costs the user persistence across
    /// launches; failing the sign-in that has *already succeeded* on the server would cost them the
    /// session as well, and would make a storage problem look like a credentials problem.
    func beginSession(_ tokens: SessionTokens, storingRefreshTokenIn store: any TokenStore) async {
        try? await refreshTokens.clear()
        refreshTokens = store
        accessToken = tokens.accessToken
        try? await store.save(refreshToken: tokens.refreshToken)
    }

    /// Ends the session deliberately: revokes it server-side where it can, then clears it locally.
    ///
    /// The remote revoke is best-effort. A user who taps "log out" on a dead network has still logged
    /// out — leaving them signed in until the network returns would be the app arguing with them — and
    /// the refresh token expires on its own in 60 days.
    ///
    func endSession() async {
        await refreshIfNearExpiry()

        if let refreshToken = try? await storedRefreshToken(),
           let body = try? encoder.encode(SignOutRequest(refreshToken: refreshToken)) {
            // ``send`` directly rather than ``perform``, so this cannot go through the refresh machinery.
            // A `401` here means the server had already ended the session — which is what the caller
            // wants — and routing it through the retry path would refresh, discover the family revoked,
            // and **signal a hard logout for a logout the user asked for**. The signal exists to tell the
            // app about a session it did not end itself.
            //
            // It presents whatever token is in hand, after the refresh above: the point of that ordering
            // is that the token this revokes is the one the store now holds, not one already rotated away.
            // Without it the server refuses the revoke, the *new* refresh token stays valid for 60 days,
            // and the logout reports success having revoked nothing.
            _ = try? await send(
                .post,
                Endpoint.logout,
                body: body,
                idempotencyKey: UUID().uuidString,
                bearer: accessToken?.raw
            ) {
                try self.decoder.decode(Acknowledgement.self, from: $0)
            }
        }
        await clearSession(signalling: false)
    }

    /// Refreshes now if the access token is absent or nearly expired; does nothing otherwise.
    ///
    /// Step 1 of ADR-0008's foreground sequence, and the reason the `401` path stays rare. Non-throwing:
    /// a foreground hook has no screen to render a failure on, and every outcome that matters — the
    /// session ending — arrives through ``sessionEnded`` instead.
    func refreshIfNearExpiry() async {
        guard accessToken.map({ $0.isNearExpiry() }) ?? true else { return }
        guard await hasSession else { return }
        _ = try? await refreshed(replacing: accessToken)
    }

    // MARK: - The one request

    /// The verbs the client speaks.
    ///
    /// Not `private`, and `CaseIterable`, so the suite that asserts the properties above can
    /// enumerate *these* rather than keep a copy of the list. A fifth verb added here then fails to
    /// compile the test's exhaustive `switch` instead of silently arriving uncovered.
    enum Method: String, CaseIterable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    /// Authorises, sends, and — on a `401` — refreshes once and sends again.
    ///
    /// **The retry is once, and only on a `401`.** A second failure propagates: a loop here would turn a
    /// server that has decided against this session into a request storm, and the honest report of "the
    /// server will not accept this" is the one the taxonomy already has a state for.
    ///
    /// - Parameter read: how the body becomes a value. A closure rather than a `Decodable` type parameter,
    ///   because one request in the app deliberately does not decode: `GET /v1/me/export` answers with bytes
    ///   the client hands to a file rather than a shape it owns (``bytes(at:)``). The alternative was a second
    ///   path through the retry logic, and the retry logic is the twenty lines that must not have two copies.
    private func perform<Response: Sendable>(
        _ method: Method,
        _ path: String,
        body: Data?,
        idempotencyKey: String?,
        authorization: Authorization,
        reading read: @escaping (Data) throws -> Response
    ) async throws -> Response {
        guard case .session = authorization else {
            return try await send(
                method, path, body: body, idempotencyKey: idempotencyKey, bearer: nil, reading: read
            )
        }

        // The same request, twice: once as sent and once as retried. A local function rather than the
        // six arguments written out twice, so the two attempts cannot come to differ in anything but the
        // token they present — which is the only thing that should differ.
        func attempt(presenting bearer: String?) async throws -> Response {
            try await send(
                method, path, body: body, idempotencyKey: idempotencyKey, bearer: bearer, reading: read
            )
        }

        // May be `nil`: the client does not gate a request on its own belief about whether it has a
        // session. It presents what it has and lets the server decide (invariant 10) — which is also
        // what keeps a signed-out app's request reaching the transport and failing honestly instead of
        // failing on a guess.
        let presented = try await sessionToken()

        do {
            return try await attempt(presenting: presented?.raw)
        } catch let error as APIError where error.isUnauthorized {
            // A `401` on a token the clock says is fresh is not a bug: it is the `securityEpoch` case
            // (backend ADR-0005) — a password change or a "sign out other devices" elsewhere invalidated
            // the token mid-life. Refreshing on the *server's* answer rather than only on the clock is
            // what makes that a prompt sign-out instead of fifteen minutes of failures.
            return try await attempt(presenting: try await refreshed(replacing: presented).raw)
        }
    }

    /// The stored refresh token, with the one rule that governs reading it.
    ///
    /// **A store that could not be read is not a store that is empty.** A Keychain protected by
    /// `AfterFirstUnlock` cannot be read before the first unlock after a reboot; reading that as "no
    /// session" would sign the user out for having restarted their phone. It is offline — the session
    /// survives and the request can be tried again — and this is the one place that says so, because three
    /// callers that each had their own `catch` would be three chances for one of them to say otherwise.
    private func storedRefreshToken() async throws -> String? {
        do {
            return try await refreshTokens.refreshToken()
        } catch {
            throw APIError.offline
        }
    }

    /// The token to present, refreshing first when it is absent or nearly expired (ADR-0007).
    private func sessionToken() async throws -> AccessToken? {
        if let accessToken, !accessToken.isNearExpiry() { return accessToken }
        guard try await storedRefreshToken() != nil else { return accessToken }

        return try await refreshed(replacing: accessToken)
    }

    /// **The single-flight refresh.** At most one refresh is in progress per client, whatever the number
    /// of callers that need one.
    ///
    /// Rotation revokes the whole family when an already-revoked token is presented (backend ADR-0005).
    /// So several concurrent refreshes are not a wasted round trip — the losers present the token the
    /// winner just spent, the family is revoked, and **the user is silently logged out**. It reproduces
    /// mainly on slow networks, which is this app's target context.
    ///
    /// Two guards, for the two ways several callers arrive:
    ///
    /// - **Overlapping.** A refresh is already in flight, so this caller awaits *that* task rather than
    ///   starting one. Reading and writing `refreshInFlight` only inside the actor is what makes this a
    ///   check without a lock.
    /// - **Staggered.** The refresh already finished before this caller's `401` came back. Its token has
    ///   been replaced, so there is nothing to refresh — retrying with the current one is the whole
    ///   answer, and refreshing again would spend the token the first caller just received.
    ///
    /// - Parameter presented: the token this caller sent, or `nil` if it had none. Compared by its raw
    ///   string, so "has the session moved on since I asked?" is answered by the token itself rather
    ///   than by a generation counter that could disagree with it.
    private func refreshed(replacing presented: AccessToken?) async throws -> AccessToken {
        if let current = accessToken, current.raw != presented?.raw, !current.isNearExpiry() {
            return current
        }
        if let refreshInFlight {
            return try await refreshInFlight.value
        }

        // Unstructured on purpose: it must outlive the caller that started it. A caller whose screen goes
        // away mid-refresh has its task cancelled, and the joiners' refresh must not go with it.
        let task = Task { try await self.rotateTokens() }
        refreshInFlight = task
        defer { refreshInFlight = nil }
        return try await task.value
    }

    /// Spends the stored refresh token for a new pair. Called only from ``refreshed(replacing:)``, and
    /// only ever once at a time.
    private func rotateTokens() async throws -> AccessToken {
        guard let stored = try await storedRefreshToken() else {
            // Nothing to refresh with, on a request that needed a session. Whatever the app believed, the
            // session is over.
            await clearSession(signalling: true)
            throw APIError.unauthenticated
        }

        let rotated: SessionTokens
        do {
            rotated = try await send(
                .post,
                Endpoint.refresh,
                body: try encoder.encode(RefreshRequest(refreshToken: stored)),
                // Keyed like every other `POST` (ADR-0022), and this is the `POST` the rule was written
                // for: a refresh that reached the server and whose *response* was lost would, on a retry
                // without a key, present a token the server has already spent — and reuse revokes the
                // whole family. One key per rotation attempt, since nothing here retries automatically.
                idempotencyKey: UUID().uuidString,
                bearer: nil
            ) {
                try self.decoder.decode(SessionTokens.self, from: $0)
            }
        } catch let error as APIError where error.isUnauthorized {
            // Definitive: the server has refused this refresh token. Either the family was revoked — by a
            // password change, a `logout-all`, or a reuse the backend caught — or it has expired. There is
            // no recovery that does not involve the user's password, so the session ends here.
            await clearSession(signalling: true)
            throw APIError.unauthenticated
        }
        // Every other outcome **keeps the session**. A transport failure is offline (ADR-0007), and a 5xx
        // is the server having a bad minute; signing the user out for either is the same bug from the
        // other side.

        accessToken = rotated.accessToken
        // Best-effort: losing the *new* refresh token costs the session at the next rotation, but failing
        // the request that prompted this would cost it now, and the access token in hand is good for
        // fifteen minutes either way.
        try? await refreshTokens.save(refreshToken: rotated.refreshToken)
        return rotated.accessToken
    }

    /// Drops everything that identifies the session, locally.
    ///
    /// - Parameter signalling: whether to tell ``sessionEnded``. `true` when the *server* ended it and
    ///   the app has to find out; `false` when the user did, because the caller already knows.
    private func clearSession(signalling: Bool) async {
        accessToken = nil
        refreshInFlight = nil
        try? await refreshTokens.clear()
        if signalling { sessionEndedSignal.yield() }
    }

    /// Builds the request, sends it, and turns the outcome into a value or an ``APIError``.
    ///
    /// Every verb above funnels through ``respond`` — which is what makes "each of the four properties is set
    /// once" true rather than aspirational — and this adds the two rules that apply only to a *decodable*
    /// answer: a non-2xx status is an error, and a body that will not decode is `malformedResponse`.
    private func send<Response: Sendable>(
        _ method: Method,
        _ path: String,
        body: Data?,
        idempotencyKey: String?,
        bearer: String?,
        reading read: (Data) throws -> Response
    ) async throws -> Response {
        let (data, response) = try await respond(
            method, path, body: body, idempotencyKey: idempotencyKey, bearer: bearer
        )

        guard (200..<300).contains(response.statusCode) else {
            throw APIError.server(status: response.statusCode, code: errorCode(in: data))
        }

        do {
            return try read(data)
        } catch {
            throw APIError.malformedResponse
        }
    }

    /// The one place a request is built and sent. **It judges nothing** — the status comes back untouched,
    /// because ``content(at:ifNoneMatch:)`` and ``send`` disagree about what `304` means and only one of them
    /// can be right for both.
    ///
    /// - Parameter etag: sent as `If-None-Match`. Only the cacheable content routes have one (invariant 8).
    private func respond(
        _ method: Method,
        _ path: String,
        body: Data?,
        idempotencyKey: String?,
        bearer: String?,
        ifNoneMatch etag: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let acceptLanguage = await language.acceptLanguage

        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let bearer {
            // The token exactly as issued, signature and unread claims included. The `sec` claim
            // (backend ADR-0005) rides along here; re-encoding the claims the client happens to read
            // would drop it along with the signature.
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            return try await transport.send(request)
        } catch is CancellationError {
            // A cancelled task is not a network condition. Swallowing it here would tell a user who
            // navigated away that they are offline, and would break structured concurrency.
            throw CancellationError()
        } catch {
            // ADR-0007 — a transport failure preserves the session. It is offline, not failed, and
            // never a reason to sign anyone out.
            throw APIError.offline
        }
    }

    /// Reads `{error: {code}}`. The envelope's `message` is never decoded, so no code path can
    /// display it (ADR-0016).
    private func errorCode(in data: Data) -> ErrorCode {
        struct Envelope: Decodable {
            struct Failure: Decodable { let code: ErrorCode }
            let error: Failure
        }
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
            return .unknown
        }
        return envelope.error.code
    }
}
