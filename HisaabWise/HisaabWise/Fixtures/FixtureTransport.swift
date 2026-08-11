#if DEBUG
import Foundation

/// A `Transport` that answers from canned HTTP payloads and programmable failures.
///
/// ADR-0013 — fixtures are **HTTP payloads, not pre-built domain objects**, so a test and a preview
/// exercise the same decoding the app does. Going through a transport is less ergonomic than handing
/// a view a ready-made model, and that cost is accepted deliberately: it is what keeps a fixture that
/// has drifted from the API failing a test rather than quietly rotting a preview.
///
/// `#if DEBUG` throughout — this never compiles into a release binary.
actor FixtureTransport: Transport {
    /// What the transport should do when a request arrives.
    enum Outcome: Sendable {
        /// The server answered. Any status code, including a failure the client must interpret.
        case response(status: Int, body: Data)
        /// The network did not answer.
        case failure(any Error & Sendable)

        /// A `200` carrying a fixture file's bytes.
        static func ok(_ fixture: Fixture) throws -> Outcome {
            .response(status: 200, body: try fixture.data())
        }

        /// The failure a device in a tunnel produces.
        static var notConnected: Outcome {
            .failure(URLError(.notConnectedToInternet))
        }
    }

    /// A request as it reached the transport. A struct rather than the `URLRequest` itself so that a
    /// test asserts on the handful of things that matter and gets a readable failure when they differ.
    struct RecordedRequest: Sendable, Hashable {
        let method: String
        let path: String
        let headers: [String: String]
        let cachePolicy: URLRequest.CachePolicy
        /// The encoded body, so a write's payload is asserted as bytes on the wire rather than as the
        /// value that went in. A `POST` whose body the client dropped would otherwise look identical
        /// to one it sent.
        let body: Data?

        init(_ request: URLRequest) {
            self.method = request.httpMethod ?? "GET"
            self.path = request.url?.path() ?? ""
            self.headers = request.allHTTPHeaderFields ?? [:]
            self.cachePolicy = request.cachePolicy
            self.body = request.httpBody
        }
    }

    private var queue: [Outcome]
    private var sequences: [String: [Outcome]]
    private let stubs: [String: Outcome]
    private var recorded: [RecordedRequest] = []

    /// How many requests to hold before answering any of them, or `0` for none.
    ///
    /// The one thing a test about **concurrency** cannot get from stubs: several requests genuinely in
    /// flight at the same moment. Without it, "three callers across one token expiry" is at the
    /// scheduler's mercy — the three may serialise, the second then presents the token the first already
    /// refreshed into, and the test passes or fails on timing rather than on behaviour.
    ///
    /// One-shot: once the count is reached everything is released and nothing is held again, so the
    /// retries that follow are not caught by it.
    private var holdingFor: Int
    private var held: [CheckedContinuation<Void, Never>] = []

    /// - Parameters:
    ///   - queue: Outcomes served in order, one per request, before anything else is consulted. This is
    ///     how a test drives a *sequence* — a `401` then a success, say.
    ///   - sequences: Outcomes keyed by path and served in order **per path**, which is what `queue`
    ///     cannot do: with several requests in flight at once, the order they reach the transport is not
    ///     the order the test wrote them in, and a global queue then answers the wrong caller. A path
    ///     whose sequence has run out falls through to `stubs`.
    ///   - stubs: Outcomes keyed by request path, serving every request to that path.
    ///   - holdingFirst: hold this many requests until all of them have arrived, then answer them all and
    ///     stop holding. How a test puts requests genuinely in flight together.
    init(
        queue: [Outcome] = [],
        sequences: [String: [Outcome]] = [:],
        stubs: [String: Outcome] = [:],
        holdingFirst holdingFor: Int = 0
    ) {
        self.queue = queue
        self.sequences = sequences
        self.stubs = stubs
        self.holdingFor = holdingFor
    }

    /// A transport that answers each fixture's own endpoints with that fixture's bytes.
    ///
    /// The ergonomic half of ADR-0013: a fixture knows which paths it is a response for
    /// (``Fixture/endpoints``), so a caller says *which payloads* it wants served rather than repeating the
    /// path-to-file mapping. `FixtureTransport.serving([.budgetINR, .meVerified])` is the whole of a
    /// signed-in Home.
    ///
    /// - Throws: ``FixtureError`` if a file is missing, so a typo fails loudly rather than becoming a
    ///   `noOutcome` thrown from somewhere unrelated later — and
    ///   ``FixtureTransportError/twoFixturesForOnePath(path:)`` if two of the fixtures answer the same path.
    ///   Two payloads for one endpoint is a caller that meant a *sequence* (`meUnverified` then `meVerified`,
    ///   say), and quietly letting the last one win would answer every request with the wrong half of it.
    static func serving(_ fixtures: [Fixture]) throws -> FixtureTransport {
        var stubs: [String: Outcome] = [:]
        for fixture in fixtures {
            let outcome = try Outcome.ok(fixture)
            for path in fixture.endpoints {
                guard stubs[path] == nil else { throw FixtureTransportError.twoFixturesForOnePath(path: path) }
                stubs[path] = outcome
            }
        }
        return FixtureTransport(stubs: stubs)
    }

    /// Every request the transport has seen, in order. The count is what proves single-flight
    /// refresh: exactly one refresh reaches the transport however many callers saw a `401`.
    var recordedRequests: [RecordedRequest] { recorded }

    /// How many requests reached a given path. The single-flight assertion, said plainly.
    func requestCount(for path: String) -> Int {
        recorded.count { $0.path == path }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let recordedRequest = RecordedRequest(request)
        recorded.append(recordedRequest)

        if holdingFor > 0 {
            if recorded.count < holdingFor {
                // The closure runs before the suspension, so appending inside the actor is safe.
                await withCheckedContinuation { held.append($0) }
            } else {
                let waiting = held
                held = []
                holdingFor = 0
                for continuation in waiting { continuation.resume() }
            }
        }

        let outcome: Outcome
        if !queue.isEmpty {
            outcome = queue.removeFirst()
        } else if var sequence = sequences[recordedRequest.path], !sequence.isEmpty {
            outcome = sequence.removeFirst()
            sequences[recordedRequest.path] = sequence
        } else if let stubbed = stubs[recordedRequest.path] {
            outcome = stubbed
        } else {
            // Silently returning an empty `200` here would let a test pass while asserting nothing.
            throw FixtureTransportError.noOutcome(path: recordedRequest.path)
        }

        switch outcome {
        case .failure(let error):
            throw error
        case .response(let status, let body):
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: status,
                      httpVersion: "HTTP/1.1",
                      headerFields: ["Content-Type": "application/json"]
                  )
            else {
                throw FixtureTransportError.malformedStub(path: recordedRequest.path)
            }
            return (body, response)
        }
    }
}

enum FixtureTransportError: Error, Equatable, Sendable {
    /// A request arrived that the test did not programme an answer for.
    case noOutcome(path: String)
    case malformedStub(path: String)
    /// Two fixtures in one `serving(_:)` call answer the same path. See that method for why it refuses.
    case twoFixturesForOnePath(path: String)
}
#endif
