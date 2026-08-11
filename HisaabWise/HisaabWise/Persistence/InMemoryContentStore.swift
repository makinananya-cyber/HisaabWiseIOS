import Foundation

/// The content store for tests and previews: nothing reaches the disk of the machine it runs on (ADR-0013).
actor InMemoryContentStore: ContentStore {
    private var stored: [ContentResource: (data: Data, etag: String?)] = [:]

    /// - Parameter seeded: resources to start with, so a test can exercise the *cached* path without a fetch.
    init(seeded: [ContentResource: Data] = [:]) {
        stored = seeded.mapValues { (data: $0, etag: nil) }
    }

    func data(for resource: ContentResource) async throws -> Data? { stored[resource]?.data }

    func etag(for resource: ContentResource) async throws -> String? { stored[resource]?.etag }

    func save(_ data: Data, etag: String?, for resource: ContentResource) async throws {
        stored[resource] = (data, etag)
    }

    func remove(_ resource: ContentResource) async throws { stored[resource] = nil }

    func clear() async throws { stored = [:] }
}
