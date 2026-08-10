import Foundation
import HWFixtures
import HWNetworking
import Testing

/// The transport is the app's only seam, so the fixture implementation of it has to be trustworthy in
/// its own right — a test that silently passes because the transport invented an answer is worse than
/// no test.
@Suite("FixtureTransport")
struct FixtureTransportTests {
    private func request(_ path: String) -> URLRequest {
        URLRequest(url: URL(string: "https://fixtures.invalid")!.appending(path: path))
    }

    @Test("refuses a request nobody programmed an answer for")
    func unprogrammedRequestThrows() async {
        let transport = FixtureTransport()

        await #expect(throws: FixtureTransportError.noOutcome(path: "/v1/budget")) {
            try await transport.send(request("/v1/budget"))
        }
    }

    @Test("serves a stub to every request for that path")
    func stubServesRepeatedly() async throws {
        let transport = FixtureTransport(stubs: ["/v1/budget": .response(status: 200, body: Data("{}".utf8))])

        for _ in 0..<3 {
            let (_, response) = try await transport.send(request("/v1/budget"))
            #expect(response.statusCode == 200)
        }
        #expect(await transport.recordedRequests.count == 3)
    }

    @Test("drains the queue in order, before consulting stubs")
    func queueTakesPrecedenceAndDrains() async throws {
        // Driving a *sequence* is what a refresh test needs: a 401, then a success. The queue is that
        // mechanism, and it has to run out rather than repeat.
        let transport = FixtureTransport(
            queue: [
                .response(status: 401, body: Data("{}".utf8)),
                .response(status: 204, body: Data("{}".utf8)),
            ],
            stubs: ["/v1/budget": .response(status: 200, body: Data("{}".utf8))]
        )

        let statuses = try await [
            transport.send(request("/v1/budget")).1.statusCode,
            transport.send(request("/v1/budget")).1.statusCode,
            transport.send(request("/v1/budget")).1.statusCode,
        ]

        #expect(statuses == [401, 204, 200])
    }

    @Test("throws the programmed failure")
    func failureIsThrown() async {
        let transport = FixtureTransport(stubs: ["/v1/budget": .notConnected])

        await #expect(throws: URLError(.notConnectedToInternet)) {
            try await transport.send(request("/v1/budget"))
        }
    }

    @Test("records the method, path, and headers of every request")
    func recordsRequests() async throws {
        let transport = FixtureTransport(stubs: ["/v1/budget": .response(status: 200, body: Data("{}".utf8))])
        var authorised = request("/v1/budget")
        authorised.setValue("Bearer token", forHTTPHeaderField: "Authorization")

        _ = try await transport.send(authorised)

        let recorded = try #require(await transport.recordedRequests.first)
        #expect(recorded.method == "GET")
        #expect(recorded.path == "/v1/budget")
        #expect(recorded.headers["Authorization"] == "Bearer token")
    }

    @Test("every fixture in the corpus is present and is valid JSON")
    func everyFixtureLoads() throws {
        // ADR-0013 — one corpus, two consumers. A fixture that has been renamed or broken fails here
        // rather than rotting a preview nobody opens.
        for fixture in Fixture.allCases {
            let data = try fixture.data()
            #expect(!data.isEmpty, "\(fixture.rawValue) is empty")
            #expect(throws: Never.self) {
                try JSONSerialization.jsonObject(with: data)
            }
        }
    }
}
