import Testing

/// ADR-0003 — the server converts *and* formats. Defects D10, D11, and D16 were each produced by one
/// rule living in two places, so the client must be unable to hold the second copy. `Money` has no
/// formatting API, and these assertions are what stop one being added quietly.
@Suite("Absence of a money formatter")
struct MoneyFormattingAbsenceTests {
    @Test("the model layer holds no number formatting and no floating-point money")
    func modelsHoldNoFormattingMachinery() throws {
        try SourceTree.expectAbsent(
            ["NumberFormatter", "FormatStyle", "Decimal", "Double", "Float"],
            from: ["Models"],
            because: "the server formats money and the client never holds a monetary float (ADR-0003)"
        )
    }

    @Test("nothing in the app formats a currency")
    func nothingFormatsCurrency() throws {
        try SourceTree.expectAbsent(
            ["NumberFormatter", ".currency(code:", "currencyCode ="],
            from: SourceTree.layers,
            because: "only the server formats money (ADR-0003)"
        )
    }
}
