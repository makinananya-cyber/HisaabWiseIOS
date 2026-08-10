import Foundation

/// A monetary value exactly as the server holds it, together with the string the server formatted
/// for display.
///
/// ADR-0003 — **the server converts and formats; the client renders.** What this type deliberately
/// does *not* have is the point of it: no formatter, no conversion, no rounding, no symbol spacing,
/// no `Double`. Defects D10, D11, and D16 were each produced by one such rule living in two places,
/// so the client is structurally unable to hold the second copy.
///
/// It has **no arithmetic at all**, and that is now unconditional. ADR-0003 carved out one exception
/// — summing the ``minor`` units of the app's own *pending* entries for the offline badge — but
/// ADR-0019 removed offline writes, so the badge that was the operator's only caller no longer
/// exists. There is nothing left that needs to add two `Money` values.
struct Money: Sendable, Hashable, Decodable {
    /// An integer count of the currency's smallest unit — fils, cents. Never a float: summing
    /// entries and taking percentages of doubles makes an exactly-at-goal month non-deterministic
    /// (Product Spec §4.1).
    ///
    /// Legitimately negative for `net`, which is unclamped where `saved` clamps at zero (§4.2).
    let minor: Int

    /// The currency the value was authored in. Money is stored as authored; there is no storage
    /// base (§4.1).
    let currency: CurrencyCode

    /// The currency's number of minor-unit digits, taken from the payload — 2 for most, 3 for
    /// KWD/BHD/OMR, 0 for JPY/KRW. Read, never assumed.
    let exponent: Int

    /// The pre-formatted, localised, symbol-spaced string the server produced honouring
    /// `Accept-Language`. **The only thing the client renders for a monetary value.**
    let display: String

    private enum CodingKeys: String, CodingKey {
        case minor, currency, exponent, display
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.minor = try container.decode(Int.self, forKey: .minor)
        self.currency = try container.decode(CurrencyCode.self, forKey: .currency)

        let exponent = try container.decode(Int.self, forKey: .exponent)
        guard Self.supportedExponents.contains(exponent) else {
            throw MoneyDecodingError.unsupportedExponent(exponent)
        }
        self.exponent = exponent

        let display = try container.decode(String.self, forKey: .display)
        guard !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // A blank display string is unrecoverable rather than cosmetic: the client has no
            // formatter to fall back to, and inventing one is what ADR-0003 forbids.
            throw MoneyDecodingError.missingDisplayString
        }
        self.display = display
    }

    /// ISO 4217 minor-unit digits run 0…4 (0 for JPY, 3 for KWD, 4 for CLF). Anything outside that
    /// misstates the magnitude by orders of magnitude, so it is rejected rather than rendered.
    private static let supportedExponents = 0...4
}

/// Why a monetary payload was refused. Every case is a refusal to guess.
enum MoneyDecodingError: Error, Equatable, Sendable {
    /// Defect D15 — an unknown code is an error, never a conversion at rate 1.0.
    case unknownCurrency(String)
    case unsupportedExponent(Int)
    case missingDisplayString
}
