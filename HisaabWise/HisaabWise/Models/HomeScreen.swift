import Foundation

/// `GET /v1/screens/home` — everything Home draws, in one response, **fully computed** (ADR-0020).
///
/// The screen this replaces read `GET /v1/budget` and rendered one figure. Home needs five things at once —
/// a spending split, a savings meter, a tip, a streak, and three article teasers — and under a
/// resource-shaped contract the client would fetch four responses and derive the join. The moment it
/// derives the join, it is calculating: defects D1, D10, D11, and D16 all happened that way.
///
/// **The budget engine has not moved.** Invariant 3 keeps 50/30/20, `saved`, and the goal verdict in one
/// place server-side; ADR-0020 changes only which route *exposes* them to a screen. `GET /v1/budget` is
/// still the engine's own endpoint — this payload is assembled from it.
///
/// **Read the field names as a list of things the client is not allowed to work out.** Every percentage
/// arrives as a percentage, every share as a fraction, every date as a label, and the goal verdict as a
/// verdict. Nothing here needs a `Double` multiplied by anything.
struct HomeScreen: Sendable, Hashable, Decodable {
    /// "Good morning" — chosen against the **server-owned** day boundary in the user's stored timezone
    /// (invariant 6). The prototype read `new Date().getHours()`, which a device-clock change moves.
    let greeting: String

    /// The display name. "Username" is a display name only; email is the identity (invariant 4).
    let name: String

    /// "Tuesday, 11 August" — a label, not a date. The client owns no calendar for this.
    let dateLabel: String

    /// "August" — the `.card-sub` on both the spending and savings cards.
    let monthLabel: String

    let spending: Spending
    let savings: Savings
    let tip: Tip
    let learning: Learning

    /// Article **teasers** only. The bodies are cacheable and stay on their own ETag'd endpoint
    /// (invariant 8, ADR-0020) — folding them in here would make editorial content per-user.
    let articles: [ArticleTeaser]

    // MARK: - Spending

    /// The donut, its centre readout, and the category key.
    struct Spending: Sendable, Hashable, Decodable {
        let total: Money

        /// "68% of pay" — the readout the design puts under the total, and **the figure defect D1 lived in**.
        /// The prototype computed `total / salary` against a hardcoded `salary: 8000`; this arrives computed
        /// against the salary the server holds, so there is no local number to be wrong.
        let shareOfPayLabel: String

        /// In the order they are drawn. Ordering is a calculation too (ADR-0020), so the server sends the
        /// sequence rather than the client sorting by amount.
        let categories: [Category]

        /// **The first-run case, said by the server rather than inferred from an empty array.** "No categories"
        /// and "a month with nothing logged" are the same array and different states — one of them wants the
        /// grey ring and a CTA, and only the server knows whether an empty month is empty because the account
        /// is new.
        let isFirstRun: Bool
    }

    /// One slice, and one row of the key.
    struct Category: Sendable, Hashable, Decodable, Identifiable {
        /// `rent`, `groceries` — stable, so isolating a slice survives a refresh.
        let id: String
        /// Server content, in the user's language.
        let name: String
        let amount: Money

        /// The slice's fraction of the whole, `0...1`. **Geometry, not a displayed figure** — the chart needs
        /// a number to turn into an angle, and it arrives rather than being computed from the minor units so
        /// that the angles and the percentage the user reads cannot round differently.
        let share: Double

        /// "38%" — the key row's percentage, and the isolated readout's "% of spend".
        let shareLabel: String

        /// Which of the six category colour slots this category owns, `1...6`. The design hardcodes a hex per
        /// category; a slot resolves through the palette, which is what keeps the later dark-mode swap a swap
        /// (ADR-0001).
        let slot: Int
    }

    // MARK: - Savings

    /// The meter: what is saved, what the goal is, and how it is going.
    struct Savings: Sendable, Hashable, Decodable {
        /// **Computed by the engine, never by the client** (invariant 3). Every card on this screen reads
        /// *this* value, which is what makes "they all agree" structural rather than tested.
        let saved: Money
        let goal: Money
        /// The `0` at the left end of the bar — a formatted zero, because the client has no formatter to make
        /// one (ADR-0003).
        let zeroLabel: String

        /// "56% of goal" — the pill.
        let percentageLabel: String

        /// Where the pin sits, `0...1`, already clamped. Geometry, for the reason `Category.share` is.
        let position: Double

        /// How it is going, as a value. It drives the pill's colour **and** which of three sentences the foot
        /// line shows — the sentences are the app's copy, in the catalogue, so they translate; the *choice*
        /// between them is the server's, because it is a verdict about money (defect D11 computed it two
        /// different ways).
        let verdict: Verdict

        /// What is left to save, or `nil` once the goal is met. Read by one of the three sentences.
        let remaining: Money?

        /// What the goal would be at a fifth of today's pay, when that is **more** than the stored goal.
        ///
        /// `nil` is the ordinary case and means "say nothing". It is non-null only when a rise in pay has left the
        /// goal behind — which was a real drift rather than a hypothetical one: a goal authored at registration was
        /// never revisited, so a reader whose salary went up kept a goal measured against the old figure and read
        /// "635% of goal" against a target that had become a twelfth of what they earned.
        ///
        /// **A suggestion, not a correction.** The server computes what it would pick; the reader decides. Both
        /// figures are server-formatted display strings, so the card states them without the client formatting
        /// money (ADR-0003).
        let goalNudge: GoalNudge?
    }

    /// The savings goal a pay rise suggests, and the one it would replace.
    struct GoalNudge: Sendable, Hashable, Decodable {
        let suggested: Money
        let current: Money
    }

    /// The design's three pill states — `low`, `warn`, and met.
    enum Verdict: String, Sendable, Hashable, Decodable, CaseIterable {
        case low
        case onTrack
        case met

        /// An unrecognised verdict reads as `onTrack` rather than failing the screen: a fourth state added
        /// server-side should degrade to the neutral one, not blank Home.
        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Verdict(rawValue: raw) ?? .onTrack
        }
    }

    // MARK: - The tip

    /// The tip of the day, **already chosen**.
    struct Tip: Sendable, Hashable, Decodable, Identifiable {
        let id: String

        /// The day it was chosen for, `YYYY-MM-DD` in the user's stored timezone.
        ///
        /// **It is not used to choose anything.** It is here so that "the server picked this" is a checkable
        /// claim rather than a convention: the client has no date arithmetic for tips and never calls
        /// `Date()`, and a test can assert that two payloads with different `dayKey`s produce different tips
        /// while the device clock produces none.
        let dayKey: String

        /// The tip's text, with `{c}` tokens **left verbatim** as the content rules require.
        let text: String

        /// What `{c}` becomes — `AED ` or `₹`, with the symbol-spacing rule already applied. Supplied rather
        /// than assembled, so the spacing rule keeps one owner (ADR-0003, ADR-0016).
        let currencyToken: String

        /// The text with the token substituted, through ``CurrencyToken`` — which is where the replacement lives
        /// now that Learn's lesson steps are a second caller (#20). The amounts inside a tip are **illustrative
        /// and never converted** (ADR-0016).
        var resolvedText: String {
            CurrencyToken(token: currencyToken).resolve(text)
        }

        /// Composed by ``HomeViewModel/tip(in:)`` when the user has asked for another one: the pool's text with
        /// **this** payload's currency token, because a cacheable pool cannot carry one user's currency.
        init(id: String, dayKey: String, text: String, currencyToken: String) {
            self.id = id
            self.dayKey = dayKey
            self.text = text
            self.currencyToken = currencyToken
        }
    }

    // MARK: - Learning

    /// The streak-and-XP mini-card, from the same payload as everything else — so the streak Home shows and
    /// the streak Learn shows cannot disagree.
    struct Learning: Sendable, Hashable, Decodable {
        /// Days. Counted against the server-owned day boundary, so a device-clock change cannot extend it
        /// (invariant 6).
        let streak: Int
        /// "120 XP · Needs vs. Wants" — the `.mini-sub`, composed server-side because it joins two figures
        /// and a title.
        let summary: String
        /// The lesson **Continue** goes to.
        let nextLesson: String
    }

    // MARK: - Articles

    /// A "Read more about" row. The body is fetched separately when the row is tapped.
    struct ArticleTeaser: Sendable, Hashable, Decodable, Identifiable {
        let id: String
        /// "Scam awareness" — the row's own label and the title of the screen it opens.
        let short: String
        /// Which glyph, as a name from a closed set the client maps to an SF Symbol. A *name* rather than the
        /// design's inline SVG path: the path is presentation, and shipping one per article would put five
        /// drawings in a JSON payload.
        let icon: Icon
        /// Which of the five accent slots the article is tinted with, `1...5`.
        let accent: Int
    }

    /// The design's five article glyphs, as a closed set.
    ///
    /// An enum rather than a free string because a name the client does not recognise draws nothing at all —
    /// and an article with no icon is a row with a hole in it. Unknown names fall back to ``lightbulb``.
    enum Icon: String, Sendable, Hashable, Decodable, CaseIterable {
        case shield
        case globe
        case steps
        case lightbulb
        case alert

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Icon(rawValue: raw) ?? .lightbulb
        }
    }
}
