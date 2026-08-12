import Foundation

/// The currency a figure is **typed in**, with the two labels a field draws around it.
///
/// Money is stored exactly as authored, in the currency it was authored in — there is no storage base
/// (Product Spec §4.1 **[FIX]**). So this is not presentation trivia: it is what the client sends alongside
/// the minor units, and it is the server's answer to "what currency is this user entering figures in" rather
/// than a guess assembled from a locale.
///
/// **Two callers, which is why it is a type of its own.** It was `ExpensesScreen.EntryCurrency` while the
/// amount field was the only figure anybody typed (#18); Account's salary box is the second (#23), and it
/// needs the same four fields for the same reason. A second nested copy would have been two shapes for one
/// contract — the thing `Components` has a rule against and a payload has no rule about, so this is that rule
/// applied one layer down.
///
/// The wire shape is unchanged by the move: the fields are named the same and sit in the same place in each
/// payload, so nothing in the corpus was re-authored to promote it.
struct AuthoringCurrency: Sendable, Hashable, Decodable {
    let code: CurrencyCode

    /// `.amount .cur` / `.money-sym` — `₹`, `AED`, `د.إ`. Decoration around a number being typed, never
    /// formatting: what comes *back* is formatted by the server (ADR-0003).
    let symbol: String

    /// `.amount .code` / `.money-code` — the ISO code beside the field.
    let displayCode: String

    /// The currency's minor-unit digits — 2 for most, 3 for KWD/BHD/OMR, 0 for JPY/KRW.
    ///
    /// Here for the reason ADR-0031 had to ask the currency reference list for one: a dinar typed `1.234` is
    /// 1234 minor units, not 123, and reading two decimal places for every currency is right 157 times out
    /// of 160.
    let exponent: Int
}
