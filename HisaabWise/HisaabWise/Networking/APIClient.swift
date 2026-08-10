import Foundation

/// The app's one HTTP client.
///
/// An `actor` because ADR-0007 gives it mutable session state to own — the in-memory access token
/// and the single-flight refresh task. Neither exists yet; the isolation is here from the first
/// commit so that adding them is not a concurrency migration.
///
/// ADR-0010 — **no environment awareness and no default base URL.** The URL is a required
/// initialiser argument, injected at the composition root from build configuration, so a test can
/// point the client at a fixture without a build configuration existing and nothing in this target
/// knows what "staging" means.
///
/// **Every request that leaves here carries the same three properties**, set in ``perform`` and
/// nowhere else, because each of them is one place away from being twelve:
///
/// - `Accept-Language`, from ``LanguageSource``. The server converts *and formats* money honouring it
///   (ADR-0003), so a missing header is not a localisation blemish — it is a figure in the wrong
///   language that the client has no formatter to correct.
/// - The cache bypass. Invariant 8 makes a HIT on per-user data a breach; every route this client
///   serves is per-user, so the bypass is the default rather than a per-route opt-out, and it holds
///   for the write verbs too. ``URLSessionTransport`` removes the cache outright as the other half.
/// - `Accept: application/json`. The one response shape the client can decode.
actor APIClient {
    private let baseURL: URL
    private let transport: any Transport
    private let language: any LanguageSource
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL, transport: any Transport, language: any LanguageSource) {
        self.baseURL = baseURL
        self.transport = transport
        self.language = language
    }

    // MARK: - Reads

    /// Performs a `GET` and decodes the body.
    ///
    /// Throws ``APIError/offline`` when the network did not answer, ``APIError/server(status:code:)``
    /// when it answered unsuccessfully, and ``APIError/malformedResponse`` when the body did not
    /// decode.
    func get<Response: Decodable & Sendable>(
        _ path: String,
        as type: Response.Type
    ) async throws -> Response {
        try await perform(.get, path, body: nil, idempotencyKey: nil, as: type)
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
        as type: Response.Type
    ) async throws -> Response {
        try await perform(
            .post,
            path,
            body: try encoder.encode(body),
            idempotencyKey: idempotencyKey,
            as: type
        )
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
        try await perform(.put, path, body: try encoder.encode(body), idempotencyKey: nil, as: type)
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
        try await perform(.delete, path, body: nil, idempotencyKey: nil, as: type)
    }

    // MARK: - The one request

    /// The verbs the client speaks.
    ///
    /// Not `private`, and `CaseIterable`, so the suite that asserts the three properties above can
    /// enumerate *these* rather than keep a copy of the list. A fifth verb added here then fails to
    /// compile the test's exhaustive `switch` instead of silently arriving uncovered.
    enum Method: String, CaseIterable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    /// Builds the request, sends it, and turns the outcome into a value or an ``APIError``.
    ///
    /// Every verb above funnels through here, which is what makes "each of the three properties is
    /// set once" true rather than aspirational.
    private func perform<Response: Decodable & Sendable>(
        _ method: Method,
        _ path: String,
        body: Data?,
        idempotencyKey: String?,
        as type: Response.Type
    ) async throws -> Response {
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

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            // A cancelled task is not a network condition. Swallowing it here would tell a user who
            // navigated away that they are offline, and would break structured concurrency.
            throw CancellationError()
        } catch {
            // ADR-0007 — a transport failure preserves the session. It is offline, not failed, and
            // never a reason to sign anyone out.
            throw APIError.offline
        }

        guard (200..<300).contains(response.statusCode) else {
            throw APIError.server(status: response.statusCode, code: errorCode(in: data))
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.malformedResponse
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
