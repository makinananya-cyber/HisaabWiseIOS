import Foundation

/// `GET /v1/screens/reports` — the archive of closed months and the savings-goal trend, **fully computed**
/// (ADR-0020).
///
/// **Read the field names as the list of things the design's browser worked out about history.** The prototype
/// held one `ARCHIVE` array and derived everything else from it at render time: `spentTotal(m)` summed six
/// categories, `paintHero()` averaged those totals and reduced the saved figures, `paintList()` grouped by year
/// and summed each group as it went, and `goalPct(m)` divided saved by goal so that `verdict(m)` could threshold
/// it. Each of those is a figure, a total, an ordering, or a verdict — so each of them is the server's.
///
/// **The verdict is the sharp end of it, and the reason this payload exists at all.** Defect D11 is *two*
/// threshold tables for the same pill on the same number: Reports thresholded at 100/70 and Home at 80/45.
/// §4.2 settles it — one table, 100/70, server-computed — and the way the client honours that is by having no
/// arithmetic with which to compute a second one. There is no `saved`, no `goal`, and no percentage as a number
/// anywhere below; a verdict arrives as a ``Verdict`` and a percentage arrives as a sentence.
///
/// **Two orderings, both sent.** The trend reads oldest to newest, because time reads that way; the archive
/// reads newest first, because the month a reader wants is the one that just closed. Ordering is a calculation
/// (ADR-0020), so the payload carries the two arrays rather than one the client sorts twice.
///
/// **No date, timestamp, or month number anywhere in it.** `monthKey` is an identity — the address of one
/// month's detail (#22) — and every label a reader sees arrives formatted against the user's stored timezone
/// (invariant 6). The client owns no calendar with which to name a month, which is the stronger form of the fix
/// `ExpensesScreen` applies to its entry labels: it could not re-derive "February" if it wanted to.
struct ReportsScreen: Sendable, Hashable, Decodable {
    /// `.hero-sub` and `.hero-split` — what the whole archive adds up to.
    let summary: Summary

    /// `.trend` — one bar per closed month against the dashed goal line.
    let trend: Trend

    /// `.yr` plus the `.month` rows under it: the archive, **grouped by the server**.
    ///
    /// Newest year first, and newest month first inside each. The design grouped as it rendered — a running
    /// `year` variable, and a `filter` over the whole array to total each group — which is the client both
    /// ordering and summing.
    let years: [Year]

    /// Every closed month in the archive, in the order the list draws them.
    ///
    /// A flattening, not a calculation: no figure comes out of it that was not in the payload, and nothing about
    /// the grouping is recomputed. It exists so a suite can say "eight months across two years" without walking
    /// the nesting itself.
    var allMonths: [Month] { years.flatMap(\.months) }

    // MARK: - The hero

    /// The three `.chip` figures and the sentence above them.
    struct Summary: Sendable, Hashable, Decodable {
        /// "Goal met in 2 of 6 months" — `#hero-sub`, and a **server sentence**.
        ///
        /// A count *and* a plural, which has six forms in Arabic (ADR-0011), joining two figures the client is
        /// not allowed to count. The design assembles it from three fragments and a trailing
        /// "· dashed line is the goal"; that half is the app's own copy, because it explains the chart rather
        /// than reporting anything.
        let goalsMetLabel: String

        /// How many months have closed.
        ///
        /// ``LearnScreen/Stat``'s shape without the sentence: ``display`` because the client has no thousands
        /// separator (ADR-0003), and ``value`` because nothing draws it. What `value` is for is the assertion —
        /// "the hero counts the months the archive holds" is a numeric claim, and two formatted strings can be
        /// wrong in the same way while two numbers cannot be equal by accident. The sentence Learn's `Stat`
        /// carries is absent because this chip has a visible caption beside it.
        let monthCount: Count

        /// `#k-avg` — the mean spend across the archive. **The server's mean**: the design divided a sum of
        /// six totals by six, in the browser, and §4.1 requires a total derived from unrounded values rather
        /// than from a sum of rounded parts.
        let averageSpend: Money

        /// `#k-saved` — everything saved across every closed month.
        let totalSaved: Money
    }

    /// A count, as a figure and as the string that is drawn.
    struct Count: Sendable, Hashable, Decodable {
        /// The raw figure. **Not drawn** — see ``Summary/monthCount``.
        let value: Int
        /// "6" — the chip's own text, formatted server-side.
        let display: String
    }

    // MARK: - The trend

    /// The bars and the line they are read against.
    struct Trend: Sendable, Hashable, Decodable {
        /// Where the dashed goal line sits, `0...1` of the plot area.
        ///
        /// **Geometry, and it is the server's for the same reason `Savings.position` is** — which is also why it
        /// borrows that field's name: the design scales the chart to `max(125, tallest × 1.08)` so a good month
        /// has headroom to overshoot, and this line's place and every bar's height are two readings of that one
        /// scale. Computed here, they could disagree — a bar at 101% drawn below a line at 100% is the chart
        /// contradicting the badge beside it.
        ///
        /// **A raw percentage would not do**, which is the part worth stating: sending `91` and letting the
        /// client scale it would hand it the number defect D11 was about, and it would then have to apply the
        /// headroom rule itself. A fraction of the plot is the only form that is both drawable and unthresholdable.
        let goalPosition: Double

        /// Oldest first, left to right — "time reads the way people expect", as the design puts it. **The
        /// server's ordering** (ADR-0020).
        let bars: [Bar]
    }

    /// One `.tbar`: a month's savings performance, coloured by the verdict.
    ///
    /// The bars carry **savings** rather than total spend, which is the design's own decision and worth keeping:
    /// spend varies less month to month, and the goal is the number the reader set.
    struct Bar: Sendable, Hashable, Decodable, Identifiable {
        /// `2026-02` — the month's identity, and the address of its detail (#22).
        let monthKey: String
        var id: String { monthKey }

        /// "Feb" — the label under the bar. The design slices three characters off the month's name; an
        /// abbreviation is a **date label**, so it arrives formatted (invariant 6) rather than being cut from a
        /// longer string the client would have to know the language of.
        let label: String

        /// How much of the plot the bar fills, `0...1`. Geometry — see ``Trend/goalPosition``, and the name is
        /// `ExpensesScreen.Wants.fill`'s for the same reason: it is a bar's extent as a fraction of its track.
        let fill: Double

        /// How the month went, from §4.2's one table. Drives the bar's colour and the badge in the replacement
        /// list.
        let verdict: Verdict

        /// "91% of goal" — the percentage as a sentence, which is what the replacement rows show.
        let percentageLabel: String

        /// "February 2026, 91% of goal, ₹11,830 saved" — what VoiceOver reads for this bar.
        ///
        /// The design puts exactly this in a `title` attribute, which touch never surfaces. A **server
        /// sentence** because it joins a date label, a percentage, and a money figure, and word order belongs
        /// to the translation (ADR-0011) — the same reason `LessonCompletion.streakLine` is one.
        let accessibilityLabel: String
    }

    // MARK: - The archive

    /// One `.yr` header and the months under it.
    struct Year: Sendable, Hashable, Decodable, Identifiable {
        /// "2026" — a label, not a number. Nothing is computed from it, and it is not a `Int` the client could
        /// be tempted to compare against a clock.
        let label: String
        var id: String { label }

        /// `.yr span` — what was saved across this year's closed months. **The server's total**: the design
        /// filtered the whole archive by year and reduced it, per row, while rendering.
        let totalSaved: Money

        /// Newest first, as the design lists them.
        let months: [Month]
    }

    /// One `.month` row: when, what it cost, and how the goal went.
    struct Month: Sendable, Hashable, Decodable, Identifiable {
        /// `2026-02` — the identity, and the detail screen's address (#22).
        let monthKey: String
        var id: String { monthKey }

        /// "February" — `.m-name`. The year beside it is the group's, so it is not repeated here.
        let label: String

        /// `.m-spent` — what the month cost, server-formatted (ADR-0003).
        let spent: Money

        /// "91% of goal" — the `.m-badge`'s own text.
        let percentageLabel: String

        /// Which of the three the badge is. **The server's**, from §4.2's table (defect D11).
        let verdict: Verdict

        /// `.m-bar` — how the month was shaped, as proportions of its spend.
        ///
        /// **One stripe per category that has something in it**, so a quiet month has fewer than six and a month
        /// with nothing logged has none — the design's own `t > 0 ? … : ''`. A bar of one grey segment would be a
        /// month drawn as though it had a shape.
        let segments: [Segment]
    }

    /// One stripe of the proportion bar: a category colour slot and its share of the month.
    struct Segment: Sendable, Hashable, Decodable, Identifiable {
        /// Which of the six category colour slots, `1...6`. A **slot** rather than a colour, so the later
        /// dark-mode swap stays a swap (ADR-0001) — the same shape `HomeScreen.Category.slot` has.
        let slot: Int
        var id: Int { slot }

        /// The stripe's share of the row's width, `0...1`. Geometry: the design divides a category's total by
        /// the month's, and dividing two figures the client does not hold is not something it can do. Named as
        /// `HomeScreen.Category.share` is, because it is the same quantity about the same six categories.
        let share: Double
    }

    // MARK: - The verdict

    /// §4.2's three verdicts, and **the only vocabulary in the app that comes from that table by name**.
    ///
    /// Defect D11 is two threshold tables disagreeing about one pill. `HomeScreen.Verdict` names the *design's*
    /// three pill classes — `low` / `onTrack` / `met` — for the live month; these are the table's own words for
    /// a month that has closed. Two names for one rule is a translation, not a second rule: both arrive
    /// computed, and neither screen can threshold anything.
    ///
    /// **It refuses to guess, where Home's degrades**, and the difference is what the value is about. Home's
    /// pill describes a month still in progress, so an unrecognised verdict reading as "on track" is a hedge
    /// about something that has not happened yet. This describes a month that is **closed and immutable**
    /// (invariant 7): a fourth verdict rendered as `near` would tell a reader that a month they may have
    /// smashed or missed outright nearly hit its goal, and it would keep telling them that for ever. An
    /// archive whose story changes is the thing invariant 7 exists to prevent, so a fourth verdict is a
    /// coordinated release — exactly as ``ExpensesScreen/Kind`` and ``LearnScreen/LessonState`` are.
    enum Verdict: String, Sendable, Hashable, Decodable, CaseIterable {
        /// `saved ≥ 100%` of goal. A `goal` of 0 yields this, because there was nothing to miss (§4.2).
        case hit
        /// `saved ≥ 70%`.
        case near
        /// Otherwise.
        case miss
    }
}
