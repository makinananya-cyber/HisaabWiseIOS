#if DEBUG
import Foundation

/// The fixture corpus: canned HTTP response bodies, read by the decoding tests and by the SwiftUI
/// previews from the same files (ADR-0013). One corpus, two consumers — so drift breaks a test.
enum Fixture: String, CaseIterable, Sendable {
    /// `GET /v1/budget` for a user paid in rupees.
    ///
    /// ADR-0013 makes the INR fixture the **default** preview deliberately: defect D1 was a
    /// hardcoded `AED 8,000` on Home, and against this fixture such a figure is visible in Xcode at
    /// design time rather than waiting for a regression test.
    case budgetINR = "budget-inr"

    /// A corpus of `Money` values spanning the exponents in circulation — 2, 3 (KWD/BHD/OMR), and
    /// 0 (JPY/KRW).
    case moneyExponents = "money-exponents"

    func data() throws -> Data {
        // Resolved against the app bundle rather than `Bundle.main`, so the same call works from the
        // app, from a preview, and from the unit-test bundle hosted inside the app.
        guard let url = Bundle.app.url(forResource: rawValue, withExtension: "json") else {
            throw FixtureError.notFound(name: rawValue)
        }
        return try Data(contentsOf: url)
    }

    func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try JSONDecoder().decode(Value.self, from: try data())
    }
}

enum FixtureError: Error, Equatable, Sendable {
    case notFound(name: String)
}

extension Bundle {
    /// The bundle this app's code was loaded from.
    static let app = Bundle(for: BundleToken.self)
}

/// Exists only to give ``Bundle/app`` a class to locate. Swift has no other way to ask.
private final class BundleToken {}
#endif
