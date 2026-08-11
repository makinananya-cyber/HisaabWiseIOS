import Foundation

/// One of the design's 251 countries, for the dial-code picker.
///
/// **Server-served, never compiled in** (ADR-0009). The list is editorial reference content: it changes when a
/// country's dial code does, which is not a reason to ship an app update.
struct Country: Sendable, Hashable, Decodable, Identifiable {
    /// ISO 3166-1 alpha-2. The identity, and what a phone number is stored against.
    let code: String
    /// `+971`, with the plus, as the design carries it and as E.164 wants it.
    let dialCode: String
    let name: String

    var id: String { code }
}

/// One of the 160 ISO-4217 currencies the display-currency picker offers.
struct Currency: Sendable, Hashable, Decodable, Identifiable {
    /// ISO 4217. The identity — and the only part that goes on the wire, because a symbol is presentation.
    let code: String
    let name: String
    /// `د.إ`, `₹`, `$`. Drawn beside a figure in the picker, never used to *format* one: formatting is the
    /// server's (ADR-0003).
    let symbol: String

    var id: String { code }
}

/// One of the 14 security questions.
///
/// **The identity is the opaque id, never the English text** — Product Spec §4.3 **[FIX]**. A question stored
/// by its wording cannot be reworded, cannot be translated, and cannot be compared across languages; and the
/// answer is hashed against the *question* it belongs to, so the pairing has to survive a copy edit.
struct SecurityQuestion: Sendable, Hashable, Decodable, Identifiable {
    /// `sq01`…`sq14`.
    let id: String
    let text: String
}

// MARK: - The payloads they arrive in

/// `GET /v1/content/reference/countries`.
///
/// **An envelope rather than a bare array**, and that is the shape agreed with the backend: a top-level JSON array
/// has nowhere to put anything else, so a list that later needs a version, a count, or a `generatedAt` becomes a
/// breaking change on the day it needs one. The cost is one wrapper type per list.
struct CountryList: Sendable, Decodable {
    let countries: [Country]
}

/// `GET /v1/content/reference/currencies`.
struct CurrencyList: Sendable, Decodable {
    let currencies: [Currency]
}

/// `GET /v1/content/security-questions` — the 14-question bank.
struct SecurityQuestionList: Sendable, Decodable {
    let questions: [SecurityQuestion]
}
