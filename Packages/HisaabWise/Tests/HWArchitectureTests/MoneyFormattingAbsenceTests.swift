import Testing

/// ADR-0003 — the server converts *and* formats. Defects D10, D11, and D16 were each produced by one
/// rule living in two places, so the client must be unable to hold the second copy. `Money` has no
/// formatting API, and these assertions are what stop one being added quietly.
@Suite("Absence of a money formatter")
struct MoneyFormattingAbsenceTests {
    @Test("HWCore holds no number formatting and no floating-point money")
    func coreHoldsNoFormattingMachinery() throws {
        try PackageTree.expectAbsent(
            ["NumberFormatter", "FormatStyle", "Decimal", "Double", "Float"],
            from: ["HWCore"],
            because: "the server formats money and the client never holds a monetary float (ADR-0003)"
        )
    }

    @Test("nothing in the package formats a currency")
    func nothingFormatsCurrency() throws {
        try PackageTree.expectAbsent(
            ["NumberFormatter", ".currency(code:", "currencyCode ="],
            from: PackageTree.libraryTargets,
            because: "only the server formats money (ADR-0003)"
        )
    }
}
