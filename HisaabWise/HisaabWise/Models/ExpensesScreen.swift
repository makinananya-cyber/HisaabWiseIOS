import Foundation

/// `GET /v1/screens/expenses` — everything Expenses draws, in one response, **fully computed** (ADR-0020).
///
/// **Seven categories in three structural kinds**, and the kinds are the interesting part: `log` appends
/// deletable entries, `lines` holds a set of named monthly bills, `fixed` holds one editable amount. Which
/// kind a category is decides *which write the screen offers*, which is why ``Kind`` is the one enum here
/// that refuses to guess — see it.
///
/// **Read the field names as a list of things the client may not work out.** `entryCountLabel`,
/// `percentageLabel`, `dateLabel`, `isOver`, and every per-category `total`. The design computed all of
/// them: `catTotal()` summed the entries, `whenLabel()` read the device clock, `updateCount()` pluralised a
/// count, and `budget()` re-implemented the 50/30/20 engine in the browser. None of that is here, and the
/// absences are the point — invariant 3 keeps the engine server-side, and invariant 6 keeps a day boundary
/// out of reach of a device-clock change.
///
/// **One `Double`, and it is geometry.** ``Wants/fill`` is a fraction a bar turns into a width, arriving
/// clamped, for the same reason `HomeScreen.Category.share` does: the width and the percentage the user reads
/// must not round differently. `MoneyFormattingAbsenceTests` names it as the third exemption to the `Double`
/// ban, so a fourth has to be argued for there.
struct ExpensesScreen: Sendable, Hashable, Decodable {
    /// "August" — the `.hero-amt small` and the `.list-head` label. A label, not a date: after a rollover
    /// crossed in flight this is what names the **live** month in the re-filing offer (§4.5).
    let monthLabel: String

    let summary: Summary
    let wants: Wants

    /// What the user types in, for the amount field's own two labels.
    let entry: EntryCurrency

    /// In the order they are drawn — seven of them. Ordering is a calculation too (ADR-0020), so the
    /// sequence arrives rather than the client sorting by kind or by amount.
    let categories: [Category]

    // MARK: - The monthly summary

    /// `.summary` — total spent, split Fixed / Variable / Income.
    ///
    /// Four figures, four sums the client does not perform. The design's `totalFixed()`, `totalVar()`, and
    /// `totalIn()` each reduced over the live month; doing that here would mean the client and the budget
    /// engine both deciding what counts as fixed, which is two owners for one rule (invariant 3).
    struct Summary: Sendable, Hashable, Decodable {
        /// `#sum-num` — spent this month. **Additional Income is not in it**: money in is not spending, and
        /// the design's own `paintSummary` excludes it from the total while counting it in `income` below.
        let total: Money
        /// Rent plus the utility lines.
        let fixed: Money
        /// Groceries, transport, entertainment, other.
        let variable: Money
        /// Additional Income for the month — money **in**, which lifts the wants allowance rather than the
        /// total (Product Spec §3.4, open decision O1).
        let income: Money
    }

    // MARK: - The wants budget

    /// `.budget` — the wants allowance, what has gone against it, and whether it has been passed.
    struct Wants: Sendable, Hashable, Decodable {
        /// Transport plus entertainment plus other.
        let used: Money
        /// 30% of income under the plain rule, half the remainder once needs outgrow their share — the
        /// adaptive engine's output, and **not** re-derived here (Product Spec §4.2, invariant 3).
        let allowance: Money

        /// "88%" — the `.budget-pct` readout. A string, so the ratio the user reads and the width of the bar
        /// cannot disagree about rounding.
        let percentageLabel: String

        /// How much of the track is filled, `0...1`, already clamped. **Geometry** — the one `Double` on this
        /// screen, for the reason `HomeScreen.Category.share` is one.
        let fill: Double

        /// `.budget.over` — the explicit over-budget state.
        ///
        /// **The server's, not `used > allowance` computed here.** It is a verdict about money and defect D11
        /// is what happens when one of those is worked out in two places; it is also not the same question as
        /// `fill >= 1`, because the fill clamps and the verdict does not.
        let isOver: Bool
    }

    // MARK: - What the user types in

    /// The display currency, as the amount field's own decoration and as the currency a new entry is
    /// **authored in**.
    ///
    /// Money is stored exactly as authored, in the currency it was typed in — there is no storage base
    /// (Product Spec §4.1 **[FIX]**). So this is not presentation trivia: it is what the client sends
    /// alongside the minor units, and it is the server's answer to "what currency is this user typing in"
    /// rather than a guess assembled from a locale.
    ///
    /// The **exponent** is here for the reason ADR-0031 had to ask the currency reference list for one: a
    /// dinar typed `1.234` is 1234 minor units, not 123, and reading two decimal places for every currency is
    /// right 157 times out of 160.
    struct EntryCurrency: Sendable, Hashable, Decodable {
        let code: CurrencyCode
        /// `.amount .cur` — `₹`, `AED`, `د.إ`. Decoration around a number being typed, never formatting: what
        /// comes *back* is formatted by the server (ADR-0003).
        let symbol: String
        /// `.amount .code` — the ISO code beside the field.
        let displayCode: String
        /// The currency's minor-unit digits — 2 for most, 3 for KWD/BHD/OMR, 0 for JPY/KRW.
        let exponent: Int
    }

    // MARK: - A category

    /// One `.cat` row, and everything the detail page behind it draws.
    struct Category: Sendable, Hashable, Decodable, Identifiable {
        /// `groceries`, `rent` — stable, so a pushed detail page survives the screen re-rendering under it
        /// after a write.
        let id: String
        /// Server content, in the user's language.
        let name: String
        /// `.cat-sub` / `.hero-sub` — "Add each shop as you go". Server content, because it is a sentence
        /// about a category and the categories are the server's.
        let hint: String

        /// **The per-category running total, read and never computed** (ADR-0020). The design summed the
        /// entries client-side in `catTotal()`; this arrives, and `ExpensesViewModelTests` asserts that a
        /// payload whose total disagrees with its own entries is drawn as the *total* says.
        ///
        /// For a category whose ``flow`` is ``Flow/incoming`` the display string is **already signed** —
        /// `+₹900`. The sign is part of the server's formatting rather than a `+` the client prefixes, which
        /// is ADR-0003 applied to one more case: a client-side prefix would put the sign on the wrong side of
        /// an Arabic string, and the design's own `(c.income ? '+' : '')` does exactly that.
        let total: Money

        /// "2 entries" — a count **and** a plural, so the server says it (ADR-0020, ADR-0011). Arabic has six
        /// plural forms; the design wrote `n === 1 ? '1 entry' : n + ' entries'`.
        ///
        /// `nil` for the two kinds that have no entry list.
        let entryCountLabel: String?

        let kind: Kind
        let flow: Flow
        let icon: Icon

        /// What a `log` entry is labelled with, or `nil` where the category's own name is the label
        /// (Groceries).
        let field: Field?

        /// `log` only — newest first, **in the server's order**. The design sorted by timestamp on the
        /// client; ordering is a calculation (ADR-0020) and the client has no timestamps to sort by, only
        /// labels.
        let entries: [Entry]

        /// `lines` only.
        let lines: [Line]

        private enum CodingKeys: String, CodingKey {
            case id, name, hint, total, entryCountLabel, kind, flow, icon, field, entries, lines
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            hint = try container.decode(String.self, forKey: .hint)
            total = try container.decode(Money.self, forKey: .total)
            entryCountLabel = try container.decodeIfPresent(String.self, forKey: .entryCountLabel)
            kind = try container.decode(Kind.self, forKey: .kind)
            flow = try container.decode(Flow.self, forKey: .flow)
            icon = try container.decode(Icon.self, forKey: .icon)
            // **A field shape this build does not recognise reads as no field at all**, which is the
            // Groceries case: the entry takes an amount and is labelled with the category's name. A fifth
            // shape added server-side therefore degrades to a usable form rather than blanking the screen —
            // and `try?` rather than `decodeIfPresent` because the latter *throws* on an unknown string.
            field = try? container.decodeIfPresent(Field.self, forKey: .field)
            // Absent rather than empty for the kinds that have neither, so a fixture reads as the design's
            // own state does — a `fixed` category carrying two empty arrays is noise nobody has to write.
            entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
            lines = try container.decodeIfPresent([Line].self, forKey: .lines) ?? []
        }
    }

    /// The three structural kinds, and **the one enum here that will not guess**.
    ///
    /// ``Icon`` and ``Flow`` degrade to a default because they are presentation: a category drawn with the
    /// wrong glyph is a blemish. `kind` decides which *write* the detail page offers, and guessing it offers
    /// the wrong shape of write — a `log` form over Rent would let a user append a second rent for the month
    /// rather than correct the one there is. So an unrecognised kind fails the decode, and the screen renders
    /// `LoadState.failed` rather than a form that files the wrong thing.
    enum Kind: String, Sendable, Hashable, Decodable, CaseIterable {
        /// Groceries · Transport · Entertainment · Other · Additional Income — append-only entries, each
        /// individually deletable.
        case log
        /// Utilities — several named monthly bills, each addable, editable, and removable.
        case lines
        /// Rent — one editable monthly amount.
        case fixed
    }

    /// Which way the money moves.
    ///
    /// Additional Income is the only `incoming` category, and it is a **structural** fact rather than a
    /// styling one: it is excluded from the donut and from the spend total, and added to income for budget
    /// purposes (Product Spec §3.4). What the client does with it is choose a tint and a glyph treatment —
    /// which is why an unrecognised value reads as `outgoing`, the commoner and less surprising of the two.
    enum Flow: String, Sendable, Hashable, Decodable, CaseIterable {
        case outgoing = "out"
        case incoming = "in"

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Flow(rawValue: raw) ?? .outgoing
        }
    }

    /// The design's four `field` configurations, as a closed vocabulary.
    ///
    /// The design carries a label, a placeholder, a type, and two flags per category. Only the *shape* is
    /// structural — whether it is typed or picked, which list it picks from, whether it may be left empty —
    /// so that is what crosses the wire, and the words stay app copy in the presentation layer where the
    /// localisation scans look for them. Four cases rather than a record of five fields, because the design
    /// has four and a fifth is a decision somebody makes rather than a combination that falls out.
    enum Field: String, Sendable, Hashable, Decodable, CaseIterable {
        /// Entertainment — "Where was it?", typed, required.
        case place
        /// Additional Income — "Where did it come from?", typed, **optional**: money arriving without a
        /// story is still money arriving.
        case source
        /// Transport — picked from the 22-mode list.
        case transportMode
        /// Other — picked from the 20-type list, one of whose options asks the user to type what it was.
        case otherType

        /// Which server-served list the field picks from, or `nil` where it is typed.
        var picklist: Picklist? {
            switch self {
            case .place, .source: nil
            case .transportMode: .transport
            case .otherType: .other
            }
        }

        /// Whether an entry may be filed with this field left blank.
        var isOptional: Bool { self == .source }
    }

    /// Which of the two server-served pick lists (ADR-0009).
    enum Picklist: String, Sendable, Hashable, Decodable, CaseIterable {
        /// 22 modes of transport.
        case transport
        /// 20 "Other" types, the last of which opens a free-text box.
        case other
    }

    /// The design's category and bill glyphs, as a closed set.
    ///
    /// A **name**, not the design's inline SVG path: a path is presentation, and shipping eleven drawings in
    /// a JSON payload is shipping the design system over the wire. Unknown names fall back to ``tag``, which
    /// is the design's own generic label glyph — a row with no icon is a row with a hole in it.
    enum Icon: String, Sendable, Hashable, Decodable, CaseIterable {
        case groceries
        case transport
        case entertainment
        case other
        case income
        case utilities
        case rent
        /// The utility line glyphs — electricity, water, and phone.
        case bolt
        case drop
        case signal
        /// The generic label glyph, and the fallback.
        case tag

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Icon(rawValue: raw) ?? .tag
        }
    }

    // MARK: - A logged entry

    /// One `.entry` — an amount, what it was for, and when.
    struct Entry: Sendable, Hashable, Decodable, Identifiable {
        /// The address `DELETE /v1/expenses/:id` is sent to.
        let id: String

        /// "Metro / subway", "Cinema — Reel Cinemas", or the category's own name. **Server content**: it is
        /// either a picklist option's name or the words the user typed, and both come back as they were
        /// stored.
        let label: String

        let amount: Money

        /// "Today" · "Yesterday" · "4 days ago" · "3 Aug" — **as a string, from the server**, computed
        /// against its own day boundary in the user's stored timezone (invariant 6).
        ///
        /// The design's `whenLabel()` read `new Date()` and diffed against the entry's timestamp, so moving
        /// the device clock re-labelled history. There is no timestamp in this payload at all, which is the
        /// stronger form of the same rule: the client cannot derive the label because it has nothing to
        /// derive it from.
        let dateLabel: String
    }

    // MARK: - A monthly bill

    /// One `.line` — a named bill inside a `lines` category.
    struct Line: Sendable, Hashable, Decodable, Identifiable {
        let id: String
        /// "Electricity". Server content — the user named it.
        let name: String
        let amount: Money
        let icon: Icon
    }
}

extension ExpensesScreen {
    /// One category by id, or `nil`.
    ///
    /// **The detail page's whole relationship with the payload.** It is pushed with an *id* and re-reads the
    /// category out of whatever payload is current, so a write that returns a new screen re-renders the open
    /// detail from server truth rather than from the copy it was pushed with (ADR-0020). Written here rather
    /// than in the view model so the lookup is the same one a test does.
    func category(id: String) -> Category? {
        categories.first { $0.id == id }
    }
}
