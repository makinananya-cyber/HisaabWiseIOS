import Foundation

/// `GET /v1/screens/reports/:monthKey` — one **closed** month in full, fully computed (ADR-0020).
///
/// **The screen invariant 7 is about.** An archived month is immutable and carries the FX rate set pinned at
/// month close, so a later currency change converts the figures through *those* rates and never changes the
/// story: a met goal stays met. The client's half of that is having no conversion and no arithmetic — every
/// figure below arrives as a `Money` the server formatted, and the verdict, the percentages, and the four
/// split-bar segments arrive decided. `ReportsMonthViewModelTests` asserts it against the corpus's own pair of
/// payloads: the same month read in rupees and in dirhams differs in every display string and in nothing else.
///
/// **It carries `saved` and `goal` where ``ReportsScreen`` deliberately carries neither**, and the difference is
/// what each screen draws. The archive draws a badge, so a `saved` on it would be a figure with nothing to do
/// but be thresholded (defect D11). This draws the savings *meter*, which is the same shape Home's is — so both
/// figures are on the wire for the same reason Home's are, and the protection is unchanged: no percentage
/// arrives as a number, the verdict arrives as a verdict, and `Money` has no arithmetic with which to make
/// either.
///
/// **The split bar is the one place the Product Spec overrules the design** (§4.2 **[FIX]**). The prototype drew
/// `needs / wants / savings / left unspent`, and under a residual definition of `saved` that fourth segment is
/// identically zero — income minus needs minus wants *is* what was saved, so nothing is left over to draw. It is
/// replaced by the **surplus above goal**, which is the more informative quantity and the reason ``Portion`` has
/// exactly four cases.
struct ReportsMonthScreen: Sendable, Hashable, Decodable {
    /// `2026-02` — the month's identity and this screen's address. An identity rather than a date: the client
    /// owns no calendar (invariant 6), and every label below arrives formatted.
    let monthKey: String

    /// "February 2026" — the page's own heading, formatted server-side.
    let title: String

    /// How the month went, from §4.2's **one** threshold table (defect D11).
    ///
    /// The same value the archive's row and its trend bar carry, which `FixtureCorpusTests` asserts across the
    /// two payloads — one month thresholded twice inside one assembly would be D11 moved server-side.
    let verdict: ReportsScreen.Verdict

    /// "91% of goal" — the percentage as a sentence, which is what the meter's pill shows.
    let percentageLabel: String

    let totals: Totals
    let spending: Spending
    let savings: Savings
    let wants: Wants
    let split: Split

    /// The accordion: every category, and under each one every entry that was logged.
    let groups: [Group]

    /// "For the record" — the facts grid.
    let facts: [Fact]

    // MARK: - The headline totals

    /// `.summary` — what the month cost, split three ways, with the sentence that explains the split.
    struct Totals: Sendable, Hashable, Decodable {
        /// `#sum-num` — everything spent. **Additional income is not in it**: money in is not spending.
        let spent: Money
        /// Rent plus the utility lines.
        let fixed: Money
        /// Groceries, transport, entertainment, other.
        let variable: Money

        /// The `Extra in` chip — money that arrived on top of the salary that month.
        ///
        /// Named for what it is rather than `income`, because ``Split/income`` is the *whole* of what came in
        /// (salary plus this) and two fields called `income` meaning two quantities is how a screen comes to draw
        /// the wrong one.
        let additionalIncome: Money

        /// Whether the adaptive branch of the engine ran that month — needs outgrew half the income, so what was
        /// left was split evenly between wants and savings rather than 30/20 (§4.2).
        ///
        /// **The engine's own flag, not `needs > income / 2` worked out here.** It chooses which of two sentences
        /// the `.sum-note` shows, and the choice is a statement about the budget rule; the words are the app's
        /// (ADR-0011). The design computed it in the browser, having re-implemented 50/30/20 there to do it,
        /// which is the two-owners situation invariant 3 exists to prevent.
        let isAdapted: Bool
    }

    // MARK: - The donut

    /// `.spend` — the month's own donut and its category key.
    struct Spending: Sendable, Hashable, Decodable {
        /// "82% of income" — the `.dm-sub` for the whole ring. Against **income** rather than salary, because an
        /// archived month's income includes whatever extra arrived in it.
        let shareOfIncomeLabel: String

        /// "6 categories" — the `.pie-sub`. A count **and** a plural, so the server says it (ADR-0011).
        let categoryCountLabel: String

        /// One slice per category **that has something in it**, in the order they are drawn — so a quiet month
        /// has fewer than six and a month with nothing logged has none.
        ///
        /// **Empty means nothing was logged, and here that has one meaning.** Home needs `isFirstRun` to tell a
        /// new account from an empty month; a month that has *closed* with no categories is simply a month
        /// nothing was logged in, so the empty ring is drawn from the absence itself.
        let categories: [Category]
    }

    /// One slice, and one row of the key.
    struct Category: Sendable, Hashable, Decodable, Identifiable {
        /// `rent`, `groceries` — stable, so isolating a slice survives a re-render.
        let id: String
        /// Server content, in the user's language.
        let name: String
        let amount: Money

        /// The slice's fraction of the month's spend, `0...1`. **Geometry**, for the reason
        /// `HomeScreen.Category.share` is: the angle and the percentage the reader sees must not round
        /// differently.
        let share: Double

        /// "51%" — the key row's own text, and the isolated readout's "% of spend".
        let shareLabel: String

        /// Which of the six category colour slots, `1...6` — a slot rather than a colour, so the later dark-mode
        /// swap stays a swap (ADR-0001).
        let slot: Int
    }

    // MARK: - The savings meter

    /// `.meter` — what was set aside against the goal that was set at the start of the month.
    struct Savings: Sendable, Hashable, Decodable {
        /// **The residual, computed by the engine** (§4.2, invariant 3): income minus needs minus wants, clamped.
        /// The prototype stored a literal per archived month, reconciled against nothing.
        let saved: Money

        /// The goal as it stood when the month closed. It does not move when a salary changes (§4.2), which is
        /// why the corpus's archive keeps ₹13,000 across a raise.
        let goal: Money

        /// The `0` at the left end of the bar — a formatted zero, because the client has no formatter to make one
        /// (ADR-0003). **It converts with the display currency** like any other figure.
        let zeroLabel: String

        /// Where the pin sits, `0...1`, already clamped. Geometry — see ``Category/share``.
        let position: Double

        /// "18% of income saved" — the `.save-sub`.
        let shareOfIncomeLabel: String

        /// What was still short of the goal, or `nil` once it was reached. Read by one of the three foot
        /// sentences.
        let remaining: Money?

        /// What was saved **above** the goal, or `nil` when the goal was met exactly or missed.
        ///
        /// The same quantity ``Split/Segment`` draws as its fourth portion, so the sentence under the meter and
        /// the bar below it cannot disagree about it.
        let surplus: Money?
    }

    // MARK: - The wants allowance

    /// `#bud-card` — what went on wants against what the engine allowed.
    ///
    /// The design draws this in a *second* treatment: Expenses puts the same figures in a bar inside its galaxy
    /// summary (`.budget`), and here they are a card of their own with a big figure over a light track
    /// (`.bud-*`). Two treatments, two components — see ``HWAllowanceBar``.
    struct Wants: Sendable, Hashable, Decodable {
        /// Transport plus entertainment plus other.
        let used: Money
        /// 30% of income under the plain rule, half the remainder once needs outgrew their share (§4.2).
        let allowance: Money

        /// "63%" — the `.bud-pct` readout, as a string so the figure and the bar cannot round differently.
        let percentageLabel: String

        /// How much of the track is filled, `0...1`, already clamped. Geometry.
        let fill: Double

        /// `.card.over` — **the server's verdict**, not `used > allowance` computed here: it is a statement about
        /// money (defect D11), and it is not the same question as `fill >= 1`, because the fill clamps and the
        /// verdict does not.
        let isOver: Bool

        /// What was left of the allowance, or `nil` once it was passed.
        let remaining: Money?

        /// What was spent beyond it, or `nil` while it held. The pair ``Savings/remaining`` and
        /// ``Savings/surplus`` make, about the other allowance.
        let excess: Money?
    }

    // MARK: - The split bar

    /// `.split` — where the whole month's income went, in four parts (§4.2 **[FIX]**).
    struct Split: Sendable, Hashable, Decodable {
        /// Salary plus whatever extra arrived — the figure the four segments add up to, and the `.split-sub`'s
        /// own.
        let income: Money

        /// Exactly four, in the order they are drawn.
        let segments: [Segment]

        private enum CodingKeys: String, CodingKey {
            case income, segments
        }

        /// **Four parts, in §4.2's order, or the screen fails.**
        ///
        /// ``Portion`` refusing a *fifth* name is only half of the rule: three segments decode perfectly well and
        /// draw a bar that does not add up to the income printed beside it, which is the same lie in a shape the
        /// enum cannot see. So the sequence is checked here, once, where a payload becomes a value.
        ///
        /// The **order** is required and not merely the set. Ordering is the server's (ADR-0020), but this
        /// particular order is the rule's rather than a choice: needs first, then what was spent on wants, then the
        /// part of the goal that was reached, then what went beyond it. A bar that drew them shuffled would read as
        /// a different story about the same month.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            income = try container.decode(Money.self, forKey: .income)

            let segments = try container.decode([Segment].self, forKey: .segments)
            guard segments.map(\.portion) == Portion.allCases else {
                throw ReportsMonthDecodingError.notTheFourPortions(segments.map { $0.portion.rawValue })
            }
            self.segments = segments
        }
    }

    /// One part of the month's income.
    struct Segment: Sendable, Hashable, Decodable, Identifiable {
        let portion: Portion
        var id: Portion { portion }

        let amount: Money

        /// The segment's fraction of income, `0...1`. Geometry, and it is what makes the bar drawable without
        /// the client dividing one figure the payload carries by another.
        let share: Double

        /// The `aim` beside the figure in the key — 50% of income for needs, the allowance for wants and
        /// savings — or `nil` for the surplus, which is what a month did *better* than its aim rather than a
        /// target of its own.
        let target: Money?
    }

    /// The four parts §4.2 settles on, and **the fourth is the [FIX]**.
    ///
    /// The design's fourth segment was "left unspent", which a residual `saved` makes identically zero: all
    /// spending is needs or wants, so income minus both is exactly what was saved and there is no remainder to
    /// draw. ``surplus`` — what was saved above the goal — takes its place.
    ///
    /// **It refuses to guess**, for ``ReportsScreen/Verdict``'s reason and one more: a fifth portion drawn as a
    /// portion the client happened to recognise would be a bar whose parts no longer add up to the income
    /// printed beside them, about a month that cannot be corrected. So a fifth is a coordinated release.
    enum Portion: String, Sendable, Hashable, Decodable, CaseIterable {
        /// Rent, utilities, groceries.
        case needs
        /// Transport, entertainment, other — what was actually spent, not the allowance.
        case wants
        /// `min(saved, goal)` — the part of the goal that was reached.
        case saved
        /// `max(0, saved − goal)`.
        case surplus
    }

    // MARK: - The accordion

    /// One `.arow` — a category, what it cost, and every entry filed under it that month.
    ///
    /// **Seven of them, always**, as on Expenses: six spending categories and Additional Income last. A category
    /// with nothing in it is a row with an empty panel rather than a row that is missing, which is what makes the
    /// accordion a record of the month rather than a list of the busy parts of it.
    struct Group: Sendable, Hashable, Decodable, Identifiable {
        /// `rent`, `income` — stable, and what the open panel is remembered by.
        let id: String
        /// Server content, in the user's language.
        let name: String

        /// Which of the six category colour slots tints the row's glyph tile, `1...6`.
        let slot: Int

        /// Which glyph, from the closed set Expenses already names — one table of eleven names for the same
        /// eleven things, rather than a second one that could disagree about which drawing Utilities gets.
        let icon: Icon

        /// Which way the money moved. Additional Income is the only ``Flow/incoming`` group, and it takes the
        /// navy treatment the app uses for money in.
        let flow: Flow

        /// The category's total for the month, **already signed** where money came in (`+₹900`) — the sign is
        /// part of the server's formatting rather than a `+` the client prefixes (ADR-0003).
        let total: Money

        /// "3 entries · 28% of spend" — a count, a plural, and a percentage, so the server composes it
        /// (ADR-0011). Arabic has six plural forms; the design wrote `n === 1 ? ' entry · ' : ' entries · '`.
        let summaryLabel: String

        /// Every entry, in the order the panel draws them — **the server's ordering** (ADR-0020).
        let entries: [Entry]
    }

    /// One `.ent` — an amount, what it was for, and when.
    ///
    /// **No id, deliberately**, where `ExpensesScreen.Entry` has one: that id is the address
    /// `DELETE /v1/expenses/:id` is sent to, and an archived month is immutable (invariant 7). There is nothing
    /// to send anywhere, so there is no address — the panel draws these the way `ArticleView` draws a
    /// paragraph.
    struct Entry: Sendable, Hashable, Decodable {
        /// "Metro / subway", or the words the user typed. Server content.
        let label: String

        /// "14 Feb", or "Fixed each month" for a bill that has no day. **A string, from the server**, computed in
        /// the user's stored timezone (invariant 6) — the design built it with `new Date(...)` in the browser, so
        /// moving the device clock re-labelled history.
        let dateLabel: String

        let amount: Money
    }

    /// The glyph set, shared with Expenses — see ``Group/icon``.
    typealias Icon = ExpensesScreen.Icon

    /// Which way the money moved, shared with Expenses for ``Icon``'s reason: it is the same distinction about
    /// the same seven categories, and the *treatment* it chooses is the same treatment.
    typealias Flow = ExpensesScreen.Flow

    // MARK: - For the record

    /// One `.fact` — a figure worth keeping, with the sentence that qualifies it.
    struct Fact: Sendable, Hashable, Decodable, Identifiable {
        /// Which fact this is. The **label** is the app's copy, keyed on this (ADR-0011): it names a rule rather
        /// than reporting anything, exactly as the summary chips' captions do.
        let kind: Kind
        var id: Kind { kind }

        /// What is drawn — a money display string for five of the six, and a **category name** for
        /// ``Kind/biggestCost``, which is why this is a string rather than a `Money`.
        let value: String

        /// "18% of everything that came in" — the qualifying line, or `nil` where there is nothing to add (a
        /// month with nothing logged has no biggest cost).
        ///
        /// **A server sentence**, because it joins a figure to words and word order belongs to the translation —
        /// the same reason `ReportsScreen.Bar.accessibilityLabel` is one. It is also the reason a currency change
        /// re-reads it: a sentence with a figure inside it is re-composed rather than converted.
        let note: String?
    }

    /// The design's six facts, as a closed vocabulary.
    enum Kind: String, Sendable, Hashable, Decodable, CaseIterable {
        /// The salary that month — **pinned at close**, because salary is a point-in-time value (§4.2).
        case salary
        /// The goal that was set at the start of it.
        case goal
        /// What was actually set aside.
        case saved
        /// Which category cost the most. Its ``Fact/value`` is a name.
        case biggestCost
        /// Rent, bills and food.
        case needs
        /// Income minus everything spent.
        case leftOver
    }

    // MARK: - Decoding

    private enum CodingKeys: String, CodingKey {
        case monthKey, title, verdict, percentageLabel, totals, spending, savings, wants, split, groups, facts
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        monthKey = try container.decode(String.self, forKey: .monthKey)
        title = try container.decode(String.self, forKey: .title)
        verdict = try container.decode(ReportsScreen.Verdict.self, forKey: .verdict)
        percentageLabel = try container.decode(String.self, forKey: .percentageLabel)
        totals = try container.decode(Totals.self, forKey: .totals)
        spending = try container.decode(Spending.self, forKey: .spending)
        savings = try container.decode(Savings.self, forKey: .savings)
        wants = try container.decode(Wants.self, forKey: .wants)
        split = try container.decode(Split.self, forKey: .split)
        groups = try container.decode([Group].self, forKey: .groups)
        // **A fact whose kind this build does not know is dropped, and only that fact.** The grid is a set of
        // tiles and the label is the app's, so a seventh kind added server-side has no words to draw itself with
        // — a tile with a hole in it. Losing one tile until the app ships a label for it is additive; failing the
        // month, which `Portion` does, would take a whole immutable record away over an extra figure nobody
        // asked for. `try?` per element rather than on the array, because `[Fact].self` would drop all six.
        facts = try container.decode([FailableFact].self, forKey: .facts).compactMap(\.fact)
    }

    /// One fact, or nothing where its kind is unrecognised — see the note in `init(from:)`.
    private struct FailableFact: Decodable {
        let fact: Fact?

        init(from decoder: any Decoder) throws {
            fact = try? Fact(from: decoder)
        }
    }
}

/// Why a month payload was refused. Every case is a refusal to draw a month wrongly rather than a refusal to draw
/// one — an archived month is immutable (invariant 7), so a figure that is wrong here is wrong for ever.
enum ReportsMonthDecodingError: Error, Equatable, Sendable {
    /// The split bar did not arrive as §4.2's four parts in §4.2's order. Carries what did arrive, so the failure
    /// names the payload rather than the rule.
    case notTheFourPortions([String])
}

extension ReportsMonthScreen {
    /// One part of the split by name, or `nil`.
    ///
    /// **A lookup, not a calculation** — the same shape `ExpensesScreen.category(id:)` has, and here for the same
    /// reason: the sentence under the summary card names what needs came to, and reading it out of the payload is
    /// not the client working it out. Written on the model so a screen and a test find it the same way.
    func segment(_ portion: Portion) -> Segment? {
        split.segments.first { $0.portion == portion }
    }

    /// One accordion group by id, or `nil`.
    func group(id: String) -> Group? {
        groups.first { $0.id == id }
    }
}
