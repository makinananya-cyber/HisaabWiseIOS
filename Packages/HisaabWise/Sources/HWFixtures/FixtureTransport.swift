#if DEBUG
import Foundation
import HWNetworking

/// A `Transport` that answers from canned HTTP payloads and programmable failures.
///
/// ADR-0013 — fixtures are **HTTP payloads, not pre-built domain objects**, so a test and a preview
/// exercise the same decoding the app does. Going through a transport is less ergonomic than handing
/// a view a ready-made model, and that cost is accepted deliberately: it is what keeps a fixture that
/// has drifted from the API failing a test rather than quietly rotting a preview.
///
/// `#if DEBUG` throughout — this never compiles into a release binary.
public actor FixtureTransport: Transport {
    /// What the transport should do when a request arrives.
    public enum Outcome: Sendable {
        /// The server answered. Any status code, including a failure the client must interpret.
        case response(status: Int, body: Data)
        /// The network did not answer.
        case failure(any Error & Sendable)

        /// A `200` carrying a fixture file's bytes.
        public static func ok(_ fixture: Fixture) throws -> Outcome {
            .response(status: 200, body: try fixture.data())
        }

        /// The failure a device in a tunnel produces.
        public static var notConnected: Outcome {
            .failure(URLError(.notConnectedToInternet))
        }
    }

    /// A request as it reached the transport. A struct rather than the `URLRequest` itself so that a
    /// test asserts on the handful of things that matter and gets a readable failure when they differ.
    public struct RecordedRequest: Sendable, Hashable {
        public let method: String
        public let path: String
        public let headers: [String: String]
        public let cachePolicy: URLRequest.CachePolicy

        init(_ request: URLRequest) {
            self.method = request.httpMethod ?? "GET"
            self.path = request.url?.path() ?? ""
            self.headers = request.allHTTPHeaderFields ?? [:]
            self.cachePolicy = request.cachePolicy
        }
    }

    private var queue: [Outcome]
    private let stubs: [String: Outcome]
    private var recorded: [RecordedRequest] = []

    /// - Parameters:
    ///   - queue: Outcomes served in order, one per request, before any stub is consulted. This is
    ///     how a test drives a *sequence* — a `401` then a success, say.
    ///   - stubs: Outcomes keyed by request path, serving every request to that path.
    public init(queue: [Outcome] = [], stubs: [String: Outcome] = [:]) {
        self.queue = queue
        self.stubs = stubs
    }

    /// Every request the transport has seen, in order. The count is what proves single-flight
    /// refresh: exactly one refresh reaches the transport however many callers saw a `401`.
    public var recordedRequests: [RecordedRequest] { recorded }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let recordedRequest = RecordedRequest(request)
        recorded.append(recordedRequest)

        let outcome: Outcome
        if !queue.isEmpty {
            outcome = queue.removeFirst()
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

public enum FixtureTransportError: Error, Equatable, Sendable {
    /// A request arrived that the test did not programme an answer for.
    case noOutcome(path: String)
    case malformedStub(path: String)
}
#endif
