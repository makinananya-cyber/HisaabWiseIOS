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
actor APIClient {
    private let baseURL: URL
    private let transport: any Transport
    private let decoder = JSONDecoder()

    init(baseURL: URL, transport: any Transport) {
        self.baseURL = baseURL
        self.transport = transport
    }

    /// Performs a `GET` and decodes the body.
    ///
    /// Throws ``APIError/offline`` when the network did not answer, ``APIError/server(status:code:)``
    /// when it answered unsuccessfully, and ``APIError/malformedResponse`` when the body did not
    /// decode.
    func get<Response: Decodable & Sendable>(
        _ path: String,
        as type: Response.Type
    ) async throws -> Response {
        // `Accept-Language` is what makes the server's display strings localised (ADR-0003). It is
        // set with the rest of the localisation work; `URLSession` supplies the system value in the
        // meantime.
        var request = URLRequest(url: baseURL.appending(path: path))
        // Invariant 8 — a cache HIT on per-user data is a data breach, not a performance win. Every
        // route this client serves is per-user, so the bypass is the default rather than a per-route
        // opt-out. Cacheable content goes through the content store instead (ADR-0009).
        request.cachePolicy = .reloadIgnoringLocalCacheData

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
