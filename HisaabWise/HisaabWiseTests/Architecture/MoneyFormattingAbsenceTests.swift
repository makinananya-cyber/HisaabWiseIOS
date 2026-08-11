import Testing

/// ADR-0003 — the server converts *and* formats. Defects D10, D11, and D16 were each produced by one
/// rule living in two places, so the client must be unable to hold the second copy. `Money` has no
/// formatting API, and these assertions are what stop one being added quietly.
@Suite("Absence of a money formatter")
struct MoneyFormattingAbsenceTests {
    /// **`Double` is banned for *money*, and three non-monetary uses now exist.** `HomeScreen.Category.share`,
    /// `Savings.position`, and `ExpensesScreen.Wants.fill` are fractions a chart turns into an angle, a pin into a
    /// position, and a bar into a width — geometry the server computed (ADR-0020), not amounts. In each case the
    /// figure the user *reads* arrives separately as a formatted string, which is the test the exemption has to
    /// pass: the fraction and the percentage must not be able to round differently.
    ///
    /// The ban is worth keeping for everything else, so the scan names the three fields rather than dropping
    /// `Double`: a fourth has to be argued for here.
    private static let geometryFields = [
        "let share: Double", "let position: Double", "let fill: Double",
    ]

    @Test("the model layer holds no number formatting and no floating-point money")
    func modelsHoldNoFormattingMachinery() throws {
        for file in try SourceTree.swiftFiles(in: "Models") {
            let code = try SourceTree.codeLines(of: file)
                .filter { line in !Self.geometryFields.contains { line.contains($0) } }

            for symbol in ["NumberFormatter", "FormatStyle", "Decimal", "Double", "Float"] {
                #expect(
                    code.first { $0.contains(symbol) } == nil,
                    """
                    Models/\(file.lastPathComponent) references \(symbol) — the server formats money and the \
                    client never holds a monetary float (ADR-0003). The only exemptions are the two geometry \
                    fractions named in `geometryFields`.
                    """
                )
            }
        }
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
