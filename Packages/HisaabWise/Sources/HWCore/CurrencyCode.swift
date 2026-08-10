import Foundation

/// A validated ISO 4217 alpha-3 currency code.
///
/// Defect D15 — the prototype silently converted an unknown code at rate 1.0, reporting a foreign
/// amount as though it were USD. Product Spec §4.1 makes an unknown code an error, so the only way
/// to obtain a `CurrencyCode` is to pass validation.
///
/// Validity is delegated to Foundation's ISO 4217 table rather than a list compiled into the app.
/// The app's own 160-currency picker is server-served editorial content
/// (`content/reference/currencies.json`), and duplicating it here would give it two owners and let
/// the copies drift. Foundation's table is a superset, so nothing the server can legitimately send
/// is rejected.
public struct CurrencyCode: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    /// `nil` for anything that is not a currency the client can be asked to display.
    public init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    private static func isValid(_ code: String) -> Bool {
        // Case is significant. Foundation normalises case when asked whether a code is ISO 4217,
        // so accepting `aed` alongside `AED` would let two spellings of one currency compare
        // unequal and quietly split a total in two.
        guard code.count == 3, code.allSatisfy({ $0.isASCII && $0.isUppercase }) else {
            return false
        }
        // `XXX` means "no currency involved" and `XTS` is reserved for testing. Neither is
        // something a figure can be denominated in, so both are as wrong as an unknown code.
        guard code != "XXX", code != "XTS" else { return false }
        return Locale.Currency(code).isISOCurrency
    }
}

extension CurrencyCode: Decodable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let code = CurrencyCode(rawValue: raw) else {
            throw MoneyDecodingError.unknownCurrency(raw)
        }
        self = code
    }
}
