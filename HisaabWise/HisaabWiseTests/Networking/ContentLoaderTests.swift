import Foundation
@testable import HisaabWise
import Testing

/// ADR-0009's content store, joined up: read from disk, revalidate with the ETag, download only what changed.
///
/// Every claim here is about **requests**, not about return values. A loader that fetched the whole list every time
/// would return the right answer and be wrong; one that never revalidated would also return the right answer, until
/// a dial code changed. So the assertions count what reached the transport and read what it was asked.
@Suite("The content loader")
struct ContentLoaderTests {
    @MainActor
    private static func loader(
        _ transport: FixtureTransport,
        store: any ContentStore = InMemoryContentStore()
    ) -> ContentLoader {
        ContentLoader(client: TestBench.client(transport), store: store)
    }

    private static let countriesPath = Endpoint.path(for: .countries)

    private static var countries: Data { TestBench.payload(.referenceCountries) }

    // MARK: - The first fetch

    @Test("a first load fetches, stores the bytes, and stores the ETag they came with")
    func aFirstLoadFetchesAndStores() async throws {
        let store = InMemoryContentStore()
        let transport = FixtureTransport(
            stubs: [Self.countriesPath: try .ok(.referenceCountries, etag: "\"v1\"")]
        )
        let loader = await Self.loader(transport, store: store)

        let list = try await loader.load(.countries, as: CountryList.self)

        #expect(list.countries.count == 251)
        #expect(try await store.data(for: .countries) == Self.countries)
        #expect(try await store.etag(for: .countries) == "\"v1\"")

        // Unconditional, because there was nothing to be conditional about.
        let request = try #require(await transport.recordedRequests.first)
        #expect(request.headers["If-None-Match"] == nil)
        // And anonymous — a cacheable route is by definition not per-user (invariant 8).
        #expect(request.headers["Authorization"] == nil)
    }

    // MARK: - Revalidation

    /// **The whole point of the ETag.** The second load sends `If-None-Match`, the server answers `304`, and the
    /// bytes come off the disk.
    @Test("a second load revalidates with the ETag and reads a 304 from the store")
    func aSecondLoadRevalidates() async throws {
        let store = InMemoryContentStore()
        let transport = FixtureTransport(sequences: [
            Self.countriesPath: [try .ok(.referenceCountries, etag: "\"v1\""), .notModified],
        ])
        let loader = await Self.loader(transport, store: store)

        _ = try await loader.load(.countries, as: CountryList.self)
        let second = try await loader.load(.countries, as: CountryList.self)

        #expect(second.countries.count == 251)
        #expect(await transport.requestCount(for: Self.countriesPath) == 2)

        let revalidation = try #require(await transport.recordedRequests.last)
        #expect(revalidation.headers["If-None-Match"] == "\"v1\"")
    }

    /// A `200` on revalidation replaces both halves together. An ETag that outlived its bytes is the one state
    /// that makes revalidation lie, which is why `save` takes them in one call.
    @Test("changed content replaces the bytes and the ETag together")
    func changedContentReplacesBoth() async throws {
        let store = InMemoryContentStore()
        let changed = Data(#"{"questions":[{"id":"sq01","text":"Changed"}]}"#.utf8)
        let transport = FixtureTransport(sequences: [
            Endpoint.path(for: .securityQuestions): [
                try .ok(.referenceSecurityQuestions, etag: "\"v1\""),
                .response(status: 200, body: changed, headers: ["ETag": "\"v2\""]),
            ],
        ])
        let loader = await Self.loader(transport, store: store)

        #expect(try await loader.load(.securityQuestions, as: SecurityQuestionList.self).questions.count == 14)
        let second = try await loader.load(.securityQuestions, as: SecurityQuestionList.self)

        #expect(second.questions.map(\.text) == ["Changed"])
        #expect(try await store.data(for: .securityQuestions) == changed)
        #expect(try await store.etag(for: .securityQuestions) == "\"v2\"")
    }

    /// A server that sends no ETag cannot be revalidated against, so the stored one is **removed** rather than
    /// left behind — a stale ETag would earn `304`s for bytes it no longer describes.
    @Test("a response with no ETag clears the stored one")
    func aResponseWithoutAnETagClearsTheStoredOne() async throws {
        let store = InMemoryContentStore()
        let transport = FixtureTransport(sequences: [
            Self.countriesPath: [
                try .ok(.referenceCountries, etag: "\"v1\""),
                .response(status: 200, body: Self.countries),
            ],
        ])
        let loader = await Self.loader(transport, store: store)

        _ = try await loader.load(.countries, as: CountryList.self)
        _ = try await loader.load(.countries, as: CountryList.self)

        #expect(try await store.etag(for: .countries) == nil)
    }

    // MARK: - Offline

    /// **A read may be served offline; a write may not** (ADR-0019). A user opening registration in a lift sees the
    /// currency list they saw yesterday — and cannot submit, which is a different rule in a different place.
    @Test("an offline load with something stored returns the stored copy")
    func offlineFallsBackToTheStore() async throws {
        let store = InMemoryContentStore(seeded: [.countries: Self.countries])
        let transport = FixtureTransport(stubs: [Self.countriesPath: .notConnected])
        let loader = await Self.loader(transport, store: store)

        let list = try await loader.load(.countries, as: CountryList.self)

        #expect(list.countries.count == 251)
    }

    @Test("an offline load with nothing stored fails, because there is nothing to draw")
    func offlineWithNothingStoredFails() async throws {
        let transport = FixtureTransport(stubs: [Self.countriesPath: .notConnected])
        let loader = await Self.loader(transport)

        await #expect(throws: APIError.offline) {
            try await loader.load(.countries, as: CountryList.self)
        }
    }

    /// A `500` is not a reason to discard a list that is still perfectly good, which is the same rule as offline
    /// and worth asserting separately: a server having a bad minute is the case somebody would handle differently.
    @Test("a server fault with something stored returns the stored copy")
    func aServerFaultFallsBackToTheStore() async throws {
        let store = InMemoryContentStore(seeded: [.currencies: TestBench.payload(.referenceCurrencies)])
        let transport = FixtureTransport(
            stubs: [Endpoint.path(for: .currencies): .response(status: 500, body: Data())]
        )
        let loader = await Self.loader(transport, store: store)

        #expect(try await loader.load(.currencies, as: CurrencyList.self).currencies.count == 160)
    }

    // MARK: - Recovery

    /// A stored file that will not decode is **forgotten and re-fetched**. Leaving it in place would make the
    /// failure permanent: the ETag would keep earning `304`s for bytes nothing can read.
    @Test("a corrupt stored file is discarded and fetched again, and the other resources survive")
    func aCorruptStoreIsRecoveredFrom() async throws {
        let store = InMemoryContentStore(seeded: [
            .countries: Data("not json".utf8),
            // A perfectly good neighbour. It used to be collateral damage: the loader called `clear()`, which on
            // disk is one `removeItem(at: directory)`, so one unreadable payload took the offline fallback for all
            // three lists with it.
            .currencies: TestBench.payload(.referenceCurrencies),
        ])
        try await store.save(Data("not json".utf8), etag: "\"stale\"", for: .countries)
        let transport = FixtureTransport(sequences: [
            Self.countriesPath: [.notModified, try .ok(.referenceCountries, etag: "\"v2\"")],
        ])
        let loader = await Self.loader(transport, store: store)

        let list = try await loader.load(.countries, as: CountryList.self)

        #expect(list.countries.count == 251)
        // Two requests: the conditional one that earned the `304`, and the unconditional retry after the stored
        // bytes turned out to be unreadable.
        #expect(await transport.requestCount(for: Self.countriesPath) == 2)
        #expect(try await store.etag(for: .countries) == "\"v2\"")
        #expect(
            try await store.data(for: .currencies) == TestBench.payload(.referenceCurrencies),
            "recovering from one unreadable resource deleted another one's stored copy"
        )
    }

    /// **An ETag is only ever sent alongside the bytes it describes.**
    ///
    /// The state this guards against is real: `Caches` is evictable, and nothing promises the system removes a
    /// resource's two files as a pair — so an ETag can outlive its data. Sending it then would ask "has this
    /// changed since v1?" about bytes the client no longer has, and a truthful `304` would leave the screen with
    /// nothing to draw.
    ///
    /// It needs a store that can be in that state, so there is one below — the only double in this suite, and it
    /// exists to reach a state the real stores are built to make unreachable.
    @Test("an ETag whose bytes were evicted is not sent")
    func anOrphanedETagIsNotSent() async throws {
        let store = HalfEvictedStore(etag: "\"ghost\"")
        let transport = FixtureTransport(
            stubs: [Self.countriesPath: try .ok(.referenceCountries, etag: "\"v1\"")]
        )
        let loader = await Self.loader(transport, store: store)

        #expect(try await loader.load(.countries, as: CountryList.self).countries.count == 251)

        // One request, and unconditional: the orphaned ETag was left out rather than sent.
        let requests = await transport.recordedRequests
        #expect(requests.count == 1)
        #expect(requests.first?.headers["If-None-Match"] == nil)
        // And the pair is whole again afterwards.
        #expect(try await store.data(for: .countries) == Self.countries)
        #expect(try await store.etag(for: .countries) == "\"v1\"")
    }

    /// The other half of that: a server that answers `304` to a request carrying **no** `If-None-Match` is
    /// answering a question nobody asked, and the loader asks again rather than returning nothing.
    @Test("a 304 nobody asked for is recovered from, not returned as an empty list")
    func anUnaskedNotModifiedIsRecoveredFrom() async throws {
        let transport = FixtureTransport(sequences: [
            Self.countriesPath: [.notModified, try .ok(.referenceCountries, etag: "\"v1\"")],
        ])
        let loader = await Self.loader(transport)

        #expect(try await loader.load(.countries, as: CountryList.self).countries.count == 251)
        #expect(await transport.requestCount(for: Self.countriesPath) == 2)
    }

    /// A store holding an ETag whose data has gone: what an eviction can leave behind, and nothing else in the
    /// app can produce.
    private actor HalfEvictedStore: ContentStore {
        private var storedETag: String?
        private var storedData: Data?

        init(etag: String) {
            storedETag = etag
        }

        func data(for resource: ContentResource) async throws -> Data? { storedData }
        func etag(for resource: ContentResource) async throws -> String? { storedETag }

        func save(_ data: Data, etag: String?, for resource: ContentResource) async throws {
            storedData = data
            storedETag = etag
        }

        func remove(_ resource: ContentResource) async throws {
            storedData = nil
            storedETag = nil
        }

        func clear() async throws {
            storedData = nil
            storedETag = nil
        }
    }

    /// A payload this version of the app cannot read is still **saved**, so the next version revalidates from it
    /// rather than downloading it again — and this version reports the failure honestly instead of drawing an
    /// empty picker.
    @Test("a fresh payload that will not decode is a malformed response, not an empty list")
    func anUndecodablePayloadIsReported() async throws {
        let transport = FixtureTransport(
            stubs: [Self.countriesPath: .response(status: 200, body: Data(#"{"nope":[]}"#.utf8))]
        )
        let loader = await Self.loader(transport)

        await #expect(throws: APIError.malformedResponse) {
            try await loader.load(.countries, as: CountryList.self)
        }
    }

    // MARK: - Invariant 8

    /// **Cacheable means not per-user.** Every resource the store can hold is the same bytes for everybody, which
    /// is precisely why it may be stored — and the three that exist are all under `/v1/content`.
    @Test("every content resource is a cacheable route and nothing else is")
    func everyResourceIsCacheable() {
        for resource in ContentResource.allCases {
            #expect(Endpoint.path(for: resource).hasPrefix("/v1/content"), "\(resource) is not a content route")
        }

        // And the paths that must bypass every cache have no resource, so nothing can put one in the store.
        let cacheable = Set(ContentResource.allCases.map { Endpoint.path(for: $0) })
        for perUser in [Endpoint.me, Endpoint.budget, Endpoint.login, Endpoint.refresh, Endpoint.register] {
            #expect(!cacheable.contains(perUser))
        }
    }

    /// The store writes to **Caches**, because every resource in it is re-fetchable — putting re-fetchable bytes
    /// somewhere backed up grows an iCloud backup for no reason.
    @Test("the file store keeps content in Caches, under its own directory")
    func theFileStoreLivesInCaches() async throws {
        let container = URL.temporaryDirectory.appending(path: "hw-content-\(UInt32.random(in: 0..<UInt32.max))")
        defer { try? FileManager.default.removeItem(at: container) }
        let store = FileContentStore(container: container)

        try await store.save(Self.countries, etag: "\"v1\"", for: .countries)

        let directory = container.appending(path: FileContentStore.directoryName)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "countries.json").path()))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "countries.etag").path()))
        #expect(try await store.data(for: .countries) == Self.countries)
        #expect(try await store.etag(for: .countries) == "\"v1\"")

        try await store.clear()

        #expect(try await store.data(for: .countries) == nil)
        #expect(try await store.etag(for: .countries) == nil)
    }
}
