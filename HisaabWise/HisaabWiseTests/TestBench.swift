import Foundation
import SwiftUI
import UIKit
@testable import HisaabWise

/// The two pieces of scaffolding every suite here needs, in one place.
///
/// Both were copied between suites before: the fixture base URL five times and the `ImageRenderer`
/// incantation twice. Neither is interesting enough to be worth reading twice, and a render size that
/// drifted between suites would make two suites disagree about what "renders" means.
enum TestBench {
    /// Where a client under test points. Deliberately unresolvable: a test that reached the network
    /// should fail, not succeed slowly.
    static let baseURL = URL(string: "https://fixtures.invalid")!

    static func client(_ transport: some Transport) -> APIClient {
        APIClient(baseURL: baseURL, transport: transport)
    }

    /// Renders through the real environment rather than touching `body`.
    ///
    /// Views here read `ThemeManager` from `@Environment`, so poking at `body` would trap on a missing
    /// object and prove nothing about the real hierarchy. This is a smoke test by design — pinned
    /// snapshots arrive with the snapshot harness (issue #9).
    @MainActor
    static func render(_ view: some View) -> UIImage? {
        ImageRenderer(content: view.hwTheme().frame(width: 390, height: 300)).uiImage
    }
}
