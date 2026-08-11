import Foundation

/// ADR-0009's content store, joined up: **read what is on disk, revalidate it with its ETag, and download only
/// when the server says the bytes have changed.**
///
/// The three reference lists registration needs are 251 countries, 160 currencies, and 14 questions — content
/// that changes when a dial code does, which is not a reason to ship an app update, and not something to
/// download again on every visit to the form either. A conditional `GET` costs a `304` and settles both.
///
/// **The bytes are stored, not the decoded values.** A store holding models would be storing this client's idea
/// of the payload; the next revalidation would then be asking about a document that never existed. The store is
/// a cache of responses, which is the only thing an ETag can describe.
///
/// **A read may be served offline; a write may not** (ADR-0019). That is not an exception to the no-offline-
/// writes rule — it is the other side of it. Content is the same for everybody and was already downloaded, so a
/// user opening registration in a lift sees the currency list they saw yesterday. What they cannot do is submit.
actor ContentLoader {
    private let client: APIClient
    private let store: any ContentStore
    private let decoder = JSONDecoder()

    init(client: APIClient, store: any ContentStore) {
        self.client = client
        self.store = store
    }

    /// The resource, decoded — from the network if it has changed, from the disk if it has not.
    ///
    /// - Throws: whatever the request threw, but **only when there is nothing stored to fall back on**. An
    ///   offline device with a stored copy gets the stored copy; an offline device with no stored copy gets
    ///   ``APIError/offline``, which is the honest answer and the one the screen has copy for.
    func load<Value: Decodable & Sendable>(
        _ resource: ContentResource,
        as type: Value.Type
    ) async throws -> Value {
        // **The ETag is read only when the bytes it describes are there.** `Caches` is evictable and nothing
        // promises a resource's two files are removed as a pair, so an ETag can outlive its data — and sending an
        // orphaned one asks "has this changed since v1?" about bytes this client no longer has. A truthful `304`
        // would then leave the screen with nothing to draw.
        let stored = try? await store.data(for: resource)
        let etag = stored == nil ? nil : try? await store.etag(for: resource)

        let response: APIClient.ContentResponse
        do {
            response = try await client.content(at: Endpoint.path(for: resource), ifNoneMatch: etag)
        } catch {
            // Offline, or a server having a bad minute. Neither is a reason to discard a list that is still
            // perfectly good; both are a reason to fail when there is no list at all.
            guard let stored, let value = try? decoder.decode(Value.self, from: stored) else { throw error }
            return value
        }

        switch response {
        case .notModified:
            guard let stored else {
                // A `304` to a request that carried no `If-None-Match` — the server answering a question nobody
                // asked. Recovering means asking again unconditionally rather than returning nothing, because
                // there is no third option: this client has no bytes for this resource.
                return try await fetch(resource, as: type)
            }
            return try await decode(stored, resource: resource, as: type) {
                try await self.fetch(resource, as: type)
            }

        case .fetched(let data, let etag):
            // Saved before decoding, so a payload this version of the app cannot read is still the payload the
            // next version revalidates from. Best-effort: a full disk costs a download next time, not this
            // screen.
            try? await store.save(data, etag: etag, for: resource)
            return try await decode(data, resource: resource, as: type) { throw APIError.malformedResponse }
        }
    }

    /// Fetches unconditionally, saves, and decodes. The recovery path, and the first-run path.
    private func fetch<Value: Decodable & Sendable>(
        _ resource: ContentResource,
        as type: Value.Type
    ) async throws -> Value {
        let response = try await client.content(at: Endpoint.path(for: resource), ifNoneMatch: nil)
        guard case .fetched(let data, let etag) = response else {
            // `nil` was sent as `If-None-Match`, so a `304` is the server answering a question nobody asked.
            throw APIError.malformedResponse
        }
        try? await store.save(data, etag: etag, for: resource)
        return try await decode(data, resource: resource, as: type) { throw APIError.malformedResponse }
    }

    /// Decodes, and on failure **forgets the stored copy first**.
    ///
    /// A file that will not decode is a file that will not decode next launch either, so leaving it in place
    /// would make the failure permanent — the ETag would keep earning `304`s for bytes nothing can read.
    ///
    /// **One resource, not the store.** This called `clear()` until review, which on disk is one
    /// `removeItem(at: directory)`: a single payload this version of the app could not read deleted the other two
    /// lists and their ETags as well, and with them the offline fallback the store exists for. The three loads run
    /// concurrently, so that was reachable from any one of them.
    private func decode<Value: Decodable & Sendable>(
        _ data: Data,
        resource: ContentResource,
        as type: Value.Type,
        otherwise recover: () async throws -> Value
    ) async rethrows -> Value {
        if let value = try? decoder.decode(Value.self, from: data) { return value }
        try? await store.remove(resource)
        return try await recover()
    }
}
