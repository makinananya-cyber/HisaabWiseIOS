import Foundation
import HWCore
import HWFixtures
import Testing

/// ADR-0003 — the server converts *and formats*; `Money` decodes the exact value plus the
/// server-supplied display string and offers no way to compute either.
@Suite("Money decoding")
struct MoneyDecodingTests {
    private let decoder = JSONDecoder()

    private func decodeMoney(_ json: String) throws -> Money {
        try decoder.decode(Money.self, from: Data(json.utf8))
    }

    @Test("decodes minor units, currency, exponent, and the server's display string")
    func decodesTheFullShape() throws {
        let money = try decodeMoney(
            #"{"minor": 800000, "currency": "AED", "exponent": 2, "display": "AED 8,000"}"#
        )

        #expect(money.minor == 800_000)
        #expect(money.currency.rawValue == "AED")
        #expect(money.exponent == 2)
        #expect(money.display == "AED 8,000")
    }

    // The exponent comes from the payload, never from an assumption that money has two decimal
    // places. KWD/BHD/OMR are 3 and JPY/KRW are 0 (Product Spec §4.1).
    @Test("decodes 3-exponent currencies", arguments: ["KWD", "BHD", "OMR"])
    func decodesThreeExponentCurrencies(code: String) throws {
        let money = try decodeMoney(
            #"{"minor": 1234567, "currency": "\#(code)", "exponent": 3, "display": "\#(code) 1,235"}"#
        )

        #expect(money.exponent == 3)
        #expect(money.minor == 1_234_567)
        #expect(money.currency.rawValue == code)
    }

    @Test("decodes 0-exponent currencies", arguments: ["JPY", "KRW"])
    func decodesZeroExponentCurrencies(code: String) throws {
        let money = try decodeMoney(
            #"{"minor": 120000, "currency": "\#(code)", "exponent": 0, "display": "\#(code) 120,000"}"#
        )

        #expect(money.exponent == 0)
        #expect(money.minor == 120_000)
    }

    @Test("carries a negative minor value, because `net` is unclamped")
    func decodesNegativeValues() throws {
        // Product Spec §4.2 — `saved` clamps at zero but `net` carries the truth for an
        // overspending user, so a monetary field is legitimately negative.
        let money = try decodeMoney(
            #"{"minor": -45000, "currency": "AED", "exponent": 2, "display": "-AED 450"}"#
        )

        #expect(money.minor == -45_000)
    }

    // Defect D15 — the prototype silently converted an unknown code at rate 1.0, reporting a
    // foreign amount as though it were USD. An unknown code is an error.
    @Test("rejects an unknown currency code rather than falling back", arguments: ["ZZZ", "QQQ", "AE", "AEDX", ""])
    func rejectsUnknownCurrencyCodes(code: String) throws {
        #expect(throws: MoneyDecodingError.unknownCurrency(code)) {
            try decodeMoney(
                #"{"minor": 100, "currency": "\#(code)", "exponent": 2, "display": "x"}"#
            )
        }
    }

    @Test("rejects a lowercase currency code")
    func rejectsLowercaseCurrencyCode() throws {
        // Foundation normalises case when asked whether a code is ISO 4217, so accepting
        // lowercase would let two spellings of one currency compare unequal.
        #expect(throws: MoneyDecodingError.unknownCurrency("aed")) {
            try decodeMoney(#"{"minor": 100, "currency": "aed", "exponent": 2, "display": "x"}"#)
        }
    }

    @Test("rejects the ISO placeholders for no currency and for testing")
    func rejectsIsoPlaceholders() throws {
        for code in ["XXX", "XTS"] {
            #expect(throws: MoneyDecodingError.unknownCurrency(code)) {
                try decodeMoney(
                    #"{"minor": 100, "currency": "\#(code)", "exponent": 2, "display": "x"}"#
                )
            }
        }
    }

    @Test("rejects an exponent outside the ISO 4217 range")
    func rejectsImplausibleExponent() throws {
        #expect(throws: MoneyDecodingError.unsupportedExponent(-1)) {
            try decodeMoney(#"{"minor": 100, "currency": "AED", "exponent": -1, "display": "x"}"#)
        }
        #expect(throws: MoneyDecodingError.unsupportedExponent(5)) {
            try decodeMoney(#"{"minor": 100, "currency": "AED", "exponent": 5, "display": "x"}"#)
        }
    }

    @Test("rejects an empty display string, since the client has no way to make one")
    func rejectsEmptyDisplayString() throws {
        #expect(throws: MoneyDecodingError.missingDisplayString) {
            try decodeMoney(#"{"minor": 100, "currency": "AED", "exponent": 2, "display": "  "}"#)
        }
    }

    @Test("rejects a payload with no display string at all")
    func rejectsAbsentDisplayString() throws {
        #expect(throws: (any Error).self) {
            try decodeMoney(#"{"minor": 100, "currency": "AED", "exponent": 2}"#)
        }
    }

    @Test("rejects a floating-point minor value")
    func rejectsFloatingPointMinor() throws {
        // §4.1 — never a float: summing entries and taking percentages of doubles makes an
        // exactly-at-goal month non-deterministic.
        #expect(throws: (any Error).self) {
            try decodeMoney(#"{"minor": 100.5, "currency": "AED", "exponent": 2, "display": "x"}"#)
        }
    }

    @Test("decodes every currency in the shared exponent fixture")
    func decodesTheExponentFixture() throws {
        let corpus = try Fixture.moneyExponents.decode([Money].self)

        #expect(corpus.count == 6)
        #expect(corpus.map(\.exponent) == [2, 3, 3, 3, 0, 0])
        #expect(corpus.map(\.currency.rawValue) == ["AED", "KWD", "BHD", "OMR", "JPY", "KRW"])
        #expect(corpus.allSatisfy { !$0.display.isEmpty })
    }
}
