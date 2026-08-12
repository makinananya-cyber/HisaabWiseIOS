import Foundation

/// What `{c}` becomes in editorial content — `₹` or `AED `, with the symbol-spacing rule already applied.
///
/// **The one string operation the client performs on content, and it is a replacement rather than a format**
/// (ADR-0003, ADR-0016). The amounts printed beside the token are *illustrative* — a tip's "save {c}500 a month"
/// and a lesson's worked example are figures the writer chose, not the reader's own money — so they are never
/// converted and never re-spelled. All the client does is put the reader's own symbol where the writer left a
/// hole.
///
/// **It is a type because the token and the content come from different responses.** Editorial content is
/// cacheable and identical for everybody (`GET /v1/curriculum`, `GET /v1/content/tips`), so it cannot carry one
/// reader's currency; the per-user screen payload carries the token (``LearnScreen/currencyToken``,
/// `HomeScreen.Tip.currencyToken`). Joining them is therefore the same shape of join as Learn's own — a lookup
/// that introduces no figure — and having one owner is what keeps the spacing rule from being re-derived beside
/// each caller.
struct CurrencyToken: Sendable, Hashable, Decodable {
    /// The hole the content leaves, verbatim, exactly as the content rules require it to be shipped.
    static let placeholder = "{c}"

    /// The symbol and its spacing, from the server — `₹`, or `AED ` with the trailing space already decided.
    let token: String

    init(token: String) {
        self.token = token
    }

    /// Decoded from the bare string the payload carries, so the wire form is `"currencyToken": "₹"` rather than
    /// an object wrapping one field.
    init(from decoder: any Decoder) throws {
        token = try decoder.singleValueContainer().decode(String.self)
    }

    /// `text` with every `{c}` replaced.
    func resolve(_ text: String) -> String {
        text.replacingOccurrences(of: Self.placeholder, with: token)
    }
}
