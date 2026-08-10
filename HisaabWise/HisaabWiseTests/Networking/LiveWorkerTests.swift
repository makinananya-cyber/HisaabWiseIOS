import Foundation
@testable import HisaabWise
import Testing

/// The one suite that talks to a real server.
///
/// It goes through the whole production chain — the `.xcconfig`'s `HW_API_BASE_URL`, the `Info.plist`
/// key, ``AppConfig``, ``URLSessionTransport``, ``APIClient``, and real decoding — against
/// `wrangler dev` running the backend in this workspace. Nothing else in the suite can tell you that
/// the base URL survived the build, that App Transport Security permits the loopback request, or that
/// the backend's error envelope is the shape the client decodes.
///
/// **Skipped, not failed, when the Worker is not running.** A developer with no backend started, and a
/// CI job with no Worker, both see it skip; the condition names how to start one. That is the trade a
/// live test has to make to be allowed to exist — the alternative is a suite that is red for reasons
/// that are nobody's bug.
///
/// The two things it knows about the server are **contract**, not internals: `GET /health` answers
/// `{"status":"ok"}`, and an unknown route answers `{error: {code, message}}` (Technical Spec §5). If
/// either changes, this repo *should* go red.
@Suite(
    "A real request against wrangler dev",
    .enabled(
        """
        No Worker is answering on the Debug base URL. Start one from HisaabWiseBackend with \
        `npx wrangler dev` to run these.
        """
    ) { await LiveWorker.isAnswering }
)
struct LiveWorkerTests {
    /// `GET /health` — the shallow operational check, which does no database work and so needs no
    /// `MONGODB_URI` to answer. Deliberately not a `/v1` route: those return `501` until the contract
    /// ticket lands, and a `501` would prove the transport works without proving decoding does.
    private struct Health: Decodable, Equatable, Sendable {
        let status: String
    }

    @MainActor
    private func client() throws -> APIClient {
        APIClient(
            baseURL: try LiveWorker.baseURL(),
            transport: URLSessionTransport(),
            language: LanguageManager(selected: .english),
            // No session, deliberately: the two routes below are unauthenticated, and a live suite that
            // could refresh would be a live suite that could sign somebody out.
            refreshTokens: InMemoryTokenStore()
        )
    }

    @Test("decodes what the Worker actually answered")
    @MainActor
    func decodesARealResponse() async throws {
        let health = try await client().get(LiveWorker.healthPath, as: Health.self)

        #expect(health == Health(status: "ok"))
    }

    @Test("reads the backend's error envelope, and does not call a 404 offline")
    @MainActor
    func anUnknownRouteIsAServerError() async throws {
        // The envelope contract, verified against the server rather than against a fixture of it: the
        // client keeps the code, drops the message (ADR-0016), and reports it as a server failure —
        // never as `offline`, which is the distinction the whole taxonomy rests on.
        let client = try client()

        await #expect(throws: APIError.server(status: 404, code: ErrorCode(rawValue: "NOT_FOUND"))) {
            try await client.get("/no-such-route", as: Health.self)
        }
    }
}

/// The probe behind the condition on ``LiveWorkerTests``.
enum LiveWorker {
    static let healthPath = "/health"

    /// The base URL **this build** was configured with, read the way the app reads it.
    ///
    /// `Bundle.main` is the host app for a hosted test bundle, so this is the real `Info.plist` the real
    /// `.xcconfig` produced — the one place a test names `Bundle.main`, and the reason the live suite is
    /// an assertion about the build configuration too: if `HW_API_BASE_URL` ever stops reaching the
    /// plist, this throws rather than quietly probing somewhere else.
    static func baseURL() throws -> URL {
        try AppConfig(infoDictionary: Bundle.main.infoDictionary ?? [:]).apiBaseURL
    }

    /// Whether a Worker answers `GET /health` right now.
    ///
    /// Its own short-timeout session rather than ``URLSessionTransport``: the point is to decide quickly
    /// whether to run the suite, and a developer with no backend should wait two seconds for that
    /// answer, not thirty.
    static var isAnswering: Bool {
        get async {
            guard let url = try? baseURL().appending(path: healthPath) else { return false }

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 2
            configuration.waitsForConnectivity = false

            do {
                let (_, response) = try await URLSession(configuration: configuration).data(from: url)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        }
    }
}
