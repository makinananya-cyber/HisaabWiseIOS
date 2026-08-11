@testable import HisaabWise
import Testing

/// Reading a figure the user typed, and writing one back into a field they will edit.
///
/// **The failure mode here is a 100× error**, which is why the rule has its own type and its own suite. The
/// separator on a `.decimalPad` is the *device region's* and no other: on a German or Brazilian phone there is no
/// `.` key at all, so a comma is the only way to express fils. Treating it as grouping files an expense a hundred
/// times too large, and the user cannot see that they typed it correctly.
///
/// It is not client-side money arithmetic (ADR-0003): it converts nothing and rounds no rate. It reads one number
/// before that number has ever been to a server.
@Suite("TypedAmount")
struct TypedAmountTests {
    // MARK: - Reading what was typed

    @Test("a plain figure is scaled by the currency's exponent", arguments: [
        (text: "8000", exponent: 2, minor: 800_000),
        (text: "8000", exponent: 3, minor: 8_000_000),
        // JPY and KRW have no minor unit at all, so the figure is the figure.
        (text: "8000", exponent: 0, minor: 8_000),
        (text: "1", exponent: 2, minor: 100),
    ])
    func aPlainFigure(_ testCase: (text: String, exponent: Int, minor: Int)) {
        #expect(TypedAmount.minor(from: testCase.text, exponent: testCase.exponent) == testCase.minor)
    }

    /// **The last separator decides, by what follows it.** `8,000` is eight thousand; `8000,50` and `8000.50` are
    /// both eight thousand and fifty. A separator followed by more places than the currency carries was grouping
    /// after all.
    @Test("the last separator decides whether it groups or separates the fraction", arguments: [
        (text: "8,000", minor: 800_000),
        (text: "8.000", minor: 800_000),
        (text: "8000.50", minor: 800_050),
        (text: "8000,50", minor: 800_050),
        // One and a half, which is what a decimal-comma reader means by it.
        (text: "1,5", minor: 150),
        (text: "1.5", minor: 150),
        // Grouped *and* fractional.
        (text: "1,234.56", minor: 123_456),
        (text: "1.234,56", minor: 123_456),
    ])
    func theSeparatorRule(_ testCase: (text: String, minor: Int)) {
        #expect(TypedAmount.minor(from: testCase.text, exponent: 2) == testCase.minor, "\(testCase.text)")
    }

    /// **A dinar typed `1.234` is 1234 minor units, not 123.** Three-digit currencies are why the exponent is read
    /// from the payload rather than assumed — right for 157 of the 160 and wrong for KWD, BHD, and OMR.
    @Test("a three-digit currency reads three decimal places")
    func aThreeDigitCurrency() {
        #expect(TypedAmount.minor(from: "1.234", exponent: 3) == 1_234)
        // The same string at two decimal places is a different figure, which is the whole point.
        #expect(TypedAmount.minor(from: "1.234", exponent: 2) == 1_234_00 / 100 * 100)
        #expect(TypedAmount.minor(from: "1.234", exponent: 2) == 123_400)
    }

    /// **Any digit script.** `Character.isNumber` accepts Eastern Arabic-Indic digits and `Int` does not, so a
    /// figure the user did type would otherwise be refused as "not a figure".
    @Test("a figure typed in Eastern Arabic-Indic digits is read")
    func easternArabicIndicDigits() {
        #expect(TypedAmount.minor(from: "٨٠٠٠", exponent: 2) == 800_000)
        #expect(TypedAmount.minor(from: "٥٢٠", exponent: 2) == 52_000)
    }

    /// Every caller refuses zero, and the design's own message is "Enter an amount greater than zero." So `nil`
    /// covers both "nothing typed" and "nothing worth sending".
    @Test("anything that is not a positive figure is nil", arguments: [
        "", " ", "abc", "0", "0.00", "0,0", ".", ","
    ])
    func nothingIsNil(_ text: String) {
        #expect(TypedAmount.minor(from: text, exponent: 2) == nil, "\(text)")
    }

    /// **A fraction with too many places, in a figure that is not grouped, is refused.**
    ///
    /// `8000.505` was read as eight million until review: the old rule said any over-long run after the last
    /// separator must be grouping, and `8000` is not a group. The two readings differ by a factor of a thousand,
    /// which is worse than the 100× error the separator rule exists to prevent — so it refuses, and the user sees
    /// the refusal and corrects it.
    @Test("an over-long fraction in an ungrouped figure is refused rather than guessed at", arguments: [
        (text: "8000.505", exponent: 2),
        (text: "8000,505", exponent: 2),
        (text: "1234.5678", exponent: 2),
        (text: "8000.5055", exponent: 3),
    ])
    func anUngroupedOverlongFractionIsRefused(_ testCase: (text: String, exponent: Int)) {
        #expect(
            TypedAmount.minor(from: testCase.text, exponent: testCase.exponent) == nil,
            "\(testCase.text) at exponent \(testCase.exponent)"
        )
    }

    /// And a genuinely grouped figure still reads as one: one to three digits before the first separator, exactly
    /// three after every one.
    @Test("a grouped figure is still read as a whole number", arguments: [
        (text: "1,234,567", minor: 123_456_700),
        (text: "1.234.567", minor: 123_456_700),
        (text: "12,345", minor: 1_234_500),
        (text: "123,456", minor: 12_345_600),
        // Genuinely ambiguous and genuinely grouped: `250.505` is two hundred fifty thousand five hundred five to
        // a decimal-comma reader, and the rule takes the reading the string's *shape* supports. `8000.505` has no
        // such reading — four digits before the first separator — which is what the refusal above rests on.
        (text: "250.505", minor: 25_050_500),
    ])
    func aGroupedFigureIsWhole(_ testCase: (text: String, minor: Int)) {
        #expect(TypedAmount.minor(from: testCase.text, exponent: 2) == testCase.minor, "\(testCase.text)")
    }

    /// A figure that cannot be represented is not a figure. Trapping on a number somebody typed would be a crash
    /// reachable from the keypad — a user holding down `9` gets a refusal, not a report.
    @Test("a figure too large to represent is refused rather than trapping")
    func anUnrepresentableFigureIsRefused() {
        #expect(TypedAmount.minor(from: String(repeating: "9", count: 30), exponent: 2) == nil)
        #expect(TypedAmount.minor(from: "9223372036854775807", exponent: 2) == nil)
    }

    @Test("a negative exponent is refused rather than looping")
    func aNegativeExponentIsRefused() {
        #expect(TypedAmount.minor(from: "100", exponent: -1) == nil)
    }

    // MARK: - Writing one back into a field

    /// **Interpolated rather than formatted**, and that is not a style choice: this string goes *into* a text
    /// field the user then edits, so it has to be readable by `minor(from:exponent:)` on the way back out.
    /// `8.000,50` would not be.
    @Test("minor units become what a field shows", arguments: [
        (minor: 800_000, exponent: 2, text: "8000"),
        (minor: 800_050, exponent: 2, text: "8000.50"),
        (minor: 800_005, exponent: 2, text: "8000.05"),
        (minor: 34_000, exponent: 2, text: "340"),
        (minor: 4_800, exponent: 2, text: "48"),
        (minor: 1_234, exponent: 3, text: "1.234"),
        (minor: 1_204, exponent: 3, text: "1.204"),
        (minor: 8_000, exponent: 0, text: "8000"),
        (minor: 0, exponent: 2, text: "0"),
    ])
    func majorString(_ testCase: (minor: Int, exponent: Int, text: String)) {
        #expect(TypedAmount.major(testCase.minor, exponent: testCase.exponent) == testCase.text)
    }

    /// **The round trip is what the two halves are for**: Utilities' edit mode fills a field from the payload and
    /// reads it back when the user saves, so a figure that survived neither would be silently changed by opening
    /// edit mode and pressing Done.
    @Test("a figure survives being written into a field and read back", arguments: [
        (minor: 800_000, exponent: 2),
        (minor: 800_050, exponent: 2),
        (minor: 34_000, exponent: 2),
        (minor: 14_100, exponent: 2),
        (minor: 1_234, exponent: 3),
        (minor: 8_000, exponent: 0),
    ])
    func theRoundTripIsLossless(_ testCase: (minor: Int, exponent: Int)) {
        let text = TypedAmount.major(testCase.minor, exponent: testCase.exponent)
        #expect(
            TypedAmount.minor(from: text, exponent: testCase.exponent) == testCase.minor,
            "\(testCase.minor) became \"\(text)\""
        )
    }

    /// And registration's two figures still read the way they did before the rule moved out of its view model:
    /// two minor digits, because the currency reference list carries no exponent yet (`CONTEXT.md`).
    @MainActor
    @Test("registration still reads and writes two minor digits")
    func registrationIsUnchanged() {
        #expect(RegistrationViewModel.majorString(800_000) == "8000")
        #expect(RegistrationViewModel.majorString(800_050) == "8000.50")
    }
}
