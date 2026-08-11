import Foundation

/// The content store on disk, in Caches.
///
/// **Caches rather than Application Support**, deliberately: every resource here is re-fetchable, so the system
/// may evict it under pressure and nothing is lost but a round trip. Putting re-fetchable bytes in a backed-up
/// directory is how an app's backup grows for no reason.
///
/// ETags live beside the data as their own tiny files rather than in `UserDefaults`, so a resource is one atomic
/// pair of files that `clear()` can remove together — an ETag in a different store outliving its data is the one
/// state that makes revalidation lie.
actor FileContentStore: ContentStore {
    /// `…/Caches/HisaabWiseContent`. Named, so the directory is recognisable in a sysdiagnose and removable
    /// without touching anything else the app owns.
    static let directoryName = "HisaabWiseContent"

    private let directory: URL

    /// - Parameter container: the Caches directory to sit in. Injected so a test can point it at a temporary
    ///   directory and leave nothing behind on the machine it runs on (ADR-0013).
    init(container: URL? = nil) {
        let caches = container ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appending(path: Self.directoryName)
    }

    func data(for resource: ContentResource) async throws -> Data? {
        try? Data(contentsOf: file(for: resource))
    }

    func etag(for resource: ContentResource) async throws -> String? {
        guard let data = try? Data(contentsOf: etagFile(for: resource)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ data: Data, etag: String?, for resource: ContentResource) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Atomic, so a process killed mid-write leaves the previous list rather than half of the new one.
        try data.write(to: file(for: resource), options: .atomic)

        let etagFile = etagFile(for: resource)
        if let etag {
            try Data(etag.utf8).write(to: etagFile, options: .atomic)
        } else {
            // No ETag means the next fetch must be unconditional; a stale one left behind would make it
            // conditional against bytes it no longer describes.
            try? FileManager.default.removeItem(at: etagFile)
        }
    }

    func remove(_ resource: ContentResource) async throws {
        // Both halves, together, for the reason `save` writes them together: an ETag that outlives its data is the
        // one state that makes revalidation lie.
        try? FileManager.default.removeItem(at: file(for: resource))
        try? FileManager.default.removeItem(at: etagFile(for: resource))
    }

    func clear() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(for resource: ContentResource) -> URL {
        directory.appending(path: resource.fileName)
    }

    private func etagFile(for resource: ContentResource) -> URL {
        directory.appending(path: "\(resource.key).etag")
    }
}
