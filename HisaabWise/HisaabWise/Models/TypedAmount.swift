import Foundation

/// Reading a figure the user typed, and writing one back into a field they will edit.
///
/// **This is not client-side money arithmetic** (ADR-0003, and the reason it is spelled out here as well as at
/// each caller). It converts nothing, rounds no rate, and applies no symbol spacing: it reads one number a
/// user typed on a keypad, before that number has ever been to a server. Every figure that comes *back* is
/// formatted server-side and rendered from `Money.display`.
///
/// It exists as one type because there are now two callers — registration's salary and goal, and Expenses'
/// amount, rent, and bill lines — and the separator rule below is a 100× error when it is wrong. Two copies
/// of it would be two chances to get it wrong in one of them.
enum TypedAmount {
    /// A typed figure as an integer count of the currency's minor units, or `nil` if what was typed is not a
    /// figure.
    ///
    /// **The separator may be a decimal comma, and getting that wrong is a 100× error.** `.decimalPad` offers
    /// the *device region's* separator and no other, so on a German or Brazilian phone there is no `.` key at
    /// all and a comma is the only way to express fils. Treating it as grouping would read `8000,50` as
    /// `800050` and file an expense a hundred times too large.
    ///
    /// So the **last** separator decides, by what follows it. Up to `exponent` digits and it separates the
    /// fraction: `8000,50` and `8000.50` are both eight thousand and fifty, and `1,5` is one and a half, which
    /// is what a decimal-comma reader means by it.
    ///
    /// More than `exponent` digits and it can only be grouping — **but only if the whole string is actually
    /// grouped**, which is the correction review found. Treating any over-long run as grouping read `8000.505`
    /// as eight million: `8,000` is grouped and `8000.505` is not, and what tells them apart is that a grouped
    /// figure has one to three digits before its first separator and exactly three after every one. So `1.234`
    /// is 1234 at exponent 2 and `8000.505` is **refused** — a thousand-fold error is not something to guess
    /// at, and a refusal is something the user can see and correct.
    ///
    /// **Any digit script.** `Character.isNumber` accepts Eastern Arabic-Indic digits and `Int` does not, so
    /// `٨٠٠٠` would otherwise be refused as "not a figure" — a figure the user did type. Each digit is read
    /// through `wholeNumberValue`, which knows every script.
    ///
    /// - Parameter exponent: the currency's minor-unit digits — 2 for most, 3 for KWD/BHD/OMR, 0 for JPY/KRW.
    ///   Read from the payload, never assumed: a dinar typed `1.234` is 1234 minor units and reading two
    ///   places would file 123.
    /// - Returns: the minor units, or `nil` for anything that is not an unambiguous positive figure. Zero is
    ///   `nil` — every caller refuses it, and the design's own message is "Enter an amount greater than zero."
    static func minor(from text: String, exponent: Int) -> Int? {
        guard exponent >= 0 else { return nil }

        // The runs of digits between the separators, in order. Everything below is a question about their shape.
        var runs: [String] = [""]
        for character in text {
            if let value = character.wholeNumberValue, character.isNumber {
                runs[runs.count - 1].append("\(value)")
            } else if character == "." || character == "," {
                runs.append("")
            }
        }

        let digits = runs.joined()
        guard !digits.isEmpty, let whole = Int(digits) else { return nil }

        let fraction: Int
        if runs.count == 1 {
            fraction = 0
        } else if let tail = runs.last, tail.count <= exponent {
            fraction = tail.count
        } else if isGrouped(runs) {
            // Every separator was a thousands separator, so all the digits belong to the whole number.
            fraction = 0
        } else {
            // A fraction with more places than the currency has, in a figure that is not grouped. Neither
            // reading is safe and they differ by a factor of a thousand.
            return nil
        }

        var scaled = whole
        for _ in 0..<(exponent - fraction) {
            let (product, overflowed) = scaled.multipliedReportingOverflow(by: 10)
            // A figure that cannot be represented is not a figure. Trapping on a number somebody typed would
            // be a crash reachable from the keypad.
            guard !overflowed else { return nil }
            scaled = product
        }
        return scaled > 0 ? scaled : nil
    }

    /// Whether the runs read as a **grouped whole number** — `8,000` and `1,234,567`, but not `8000.505`.
    ///
    /// One to three digits before the first separator and exactly three after every one. That is the test that
    /// tells grouping from a fraction with too many places in it, and without it a mistyped third decimal is a
    /// thousand-fold error the user has no way to see.
    private static func isGrouped(_ runs: [String]) -> Bool {
        guard let first = runs.first, (1...3).contains(first.count) else { return false }
        return runs.dropFirst().allSatisfy { $0.count == 3 }
    }

    /// Minor units back into what a field shows — `800000` at exponent 2 reads `8000`, `800050` reads
    /// `8000.50`.
    ///
    /// **Interpolated rather than formatted, and that is not a style choice.** A formatter would group and
    /// decimal-separate against a locale, and this string goes *into a text field the user then edits*:
    /// `8.000,50` is unparseable by ``minor(from:exponent:)`` on the other side of this file, and every
    /// formatter is kept out of the app anyway (ADR-0003, ADR-0011).
    ///
    /// It is therefore **not a display string**. What a user reads is `Money.display`; this is what they edit.
    static func major(_ minor: Int, exponent: Int) -> String {
        guard exponent > 0 else { return "\(minor)" }

        var divisor = 1
        for _ in 0..<exponent { divisor *= 10 }

        let units = minor / divisor
        let fraction = abs(minor % divisor)
        guard fraction != 0 else { return "\(units)" }

        var digits = "\(fraction)"
        while digits.count < exponent { digits = "0" + digits }
        return "\(units).\(digits)"
    }
}
