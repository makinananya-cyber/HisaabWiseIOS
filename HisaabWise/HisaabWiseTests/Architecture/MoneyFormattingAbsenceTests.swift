import Testing

/// ADR-0003 — the server converts *and* formats. Defects D10, D11, and D16 were each produced by one
/// rule living in two places, so the client must be unable to hold the second copy. `Money` has no
/// formatting API, and these assertions are what stop one being added quietly.
@Suite("Absence of a money formatter")
struct MoneyFormattingAbsenceTests {
    /// **`Double` is banned for *money*, and four non-monetary field names are exempt.** `share`, `position`,
    /// `fill`, and `goalPosition` are fractions a chart turns into an angle, a pin into a place, and a bar into
    /// an extent — geometry the server computed (ADR-0020), not amounts. In each case the figure the user
    /// *reads* arrives separately as a formatted string, which is the test the exemption has to pass: the
    /// fraction and the percentage must not be able to round differently.
    ///
    /// Six fields use those four names — `HomeScreen.Category.share`, `Savings.position`,
    /// `ExpensesScreen.Wants.fill`, `ReportsScreen.Bar.fill`, `ReportsScreen.Segment.share`, and
    /// `ReportsScreen.Trend.goalPosition` — and Reports' three deliberately **borrow** the three names that were
    /// already here rather than adding `height` and `width`. That is not tidiness: `height` and `width` are
    /// generic enough that any future `Double` called either would pass this scan in silence, where `share` and
    /// `fill` name a *quantity* and would be a lie on anything else. Review caught the first version doing it the
    /// generic way.
    ///
    /// Reports' three are also the strongest form of the argument rather than the weakest: a bar's extent and the
    /// goal line's place are two readings of one scale, so a client that computed either could draw a bar at 101%
    /// below a line at 100% — the chart contradicting the badge beside it, which is defect D11's shape in pixels.
    ///
    /// The ban is worth keeping for everything else, so the scan names the fields rather than dropping `Double`:
    /// a fifth name has to be argued for here.
    private static let geometryFields = [
        "let share: Double", "let position: Double", "let fill: Double", "let goalPosition: Double",
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
