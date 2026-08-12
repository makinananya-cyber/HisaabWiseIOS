import Foundation

/// `GET /v1/screens/account` — everything Account draws, in one response, **fully computed** (ADR-0020).
///
/// **Four rows, and each one is a different kind of thing.** Personal Information is a form, Language and
/// Currency are pickers over two different sources, and Password is a three-step flow. So ``Section`` is the
/// enum on this screen that refuses to guess — it decides *which page opens*, and an unrecognised section is a
/// row that leads somewhere the client cannot draw.
///
/// **Read the field names as a list of things the client may not work out.** ``Profile/initials`` — because
/// "the first letter of each of the first two words" is a rule about scripts, and the design's
/// `split(/\s+/).map(w => w[0]).toUpperCase()` produces a mangled pair of glyphs for an Arabic name.
/// ``Profile/summaryLabel`` — because the design concatenates `currency.c + ' · ' + language.n`, and a
/// sentence assembled from parts is the thing `LocalisationTests` scans for. ``Row/hint`` — because
/// "Changed 3 months ago" is a date label computed against a day boundary the server owns (invariant 6), and
/// the design's own copy for it is a literal that was never reconciled with anything. And
/// ``Phone/display`` — because `dial + national.replace(/(\d{5})(?=\d)/, '$1 ')` is a grouping rule for one
/// country applied to all 251.
///
/// **No `Double` at all**, which makes this the first screen payload with none: there is no geometry on it.
/// Nothing here is a figure except the salary, and the salary is a ``Money``.
///
/// **The salary is where defect D16 lives.** The design holds `state.salary` as a bare number, renders it
/// through `money(salaryShown())` — which rounds to the nearest whole unit — and then *reads that rendered
/// string back* when the user saves, so opening the editor and pressing Save quantises the figure that
/// enters the budget engine. Here the editable figure is ``Money/minor`` and the readable one is
/// ``Money/display``: two fields, and the one the user edits has never been through a formatter.
struct AccountScreen: Sendable, Hashable, Decodable {
    let profile: Profile

    /// The four rows, **in the order they are drawn**. Ordering is a calculation too (ADR-0020), so the
    /// sequence arrives rather than the client sorting a set of sections it happens to know about.
    let rows: [Row]

    let personal: Personal

    /// The stored language preference — **the picker's selection, and the reason it is a top-level field.**
    ///
    /// `PUT /v1/me/language` answers with this whole payload and `APIClient.setLanguage` reads exactly one
    /// field out of it (ADR-0024), so `language` has to sit at the root: a narrow decode of a nested
    /// `preferences.language` would be a second shape describing one field.
    ///
    /// It decodes as ``AppLanguage``, so a stored tag this build does not ship **fails the screen** rather
    /// than arriving as a case. That is the right answer and not a hazard: the only route that writes this
    /// field is the picker, and the picker offers `AppLanguage.shipped`.
    let language: AppLanguage

    /// The display currency — what every figure on every screen is converted into at read (ADR-0003).
    ///
    /// Not the currency the salary was *authored* in, which is ``Money/currency`` on the salary itself. The
    /// two are the same for a user who has never changed it and are allowed to differ for ever afterwards,
    /// because a currency change repaints and migrates nothing (§4.1).
    let currency: CurrencyCode

    let password: Password

    // MARK: - The profile header

    /// `.profile` — the initials avatar, the name, the address, and the one-line summary chip.
    struct Profile: Sendable, Hashable, Decodable {
        /// `.avatar` — "AM". **The server's**, because initials are a question about a writing system: the
        /// design takes the first character of each of the first two words and upper-cases them, which is
        /// wrong for a script with no case, wrong for a mononym, and wrong for a name whose first grapheme
        /// cluster is more than one scalar.
        let initials: String

        /// `.pro-name` — the display name. "Username" in the design's own copy, and a display name only:
        /// email is the identity (invariant 4).
        let displayName: String

        /// `.pro-mail` — the identity, and the one field on this screen that no write can change.
        let email: String

        /// `.pro-chip` — "INR · English". **One string, not two joined**: the design writes
        /// `state.currency.c + ' · ' + state.language.n`, and a sentence concatenated on the client is a
        /// sentence no translation can reorder (ADR-0011).
        let summaryLabel: String
    }

    // MARK: - A row

    /// One `.row` in the `.bubble` — the icon, the name, the subtitle, and the value at the trailing edge.
    struct Row: Sendable, Hashable, Decodable, Identifiable {
        /// Which page the row opens, and the row's identity.
        let section: Section

        /// `.row-name` — "Personal Information". Server content, in the reader's language.
        let name: String

        /// `.row-sub` — "Username, salary, phone", "Changed 3 months ago".
        ///
        /// **A date label for the password row, which is why it is the server's** (invariant 6, ADR-0020).
        /// The design carries `passwordChanged: '3 months ago'` as a literal reconciled against nothing and
        /// rewrites it to `'just now'` in the browser.
        let hint: String

        /// `.row-val` — "English", "INR". `nil` on the two rows the design draws without one.
        ///
        /// **The password row's `••••••••` does not come through here.** The server has no password to send
        /// and must never send a stand-in for one; eight bullets are the design's own decoration, so they are
        /// drawn on the client (``Section/masksValue``).
        let value: String?

        var id: Section { section }
    }

    /// The four pages, and **the one enum on this screen that will not guess.**
    ///
    /// ``ExpensesScreen/Kind`` refuses an unrecognised value for the same reason: it decides which *shape of
    /// write* a page offers, and guessing offers the wrong one. Here a fifth section drawn as `personal`
    /// would put a salary field over something that is not a salary. So an unrecognised section fails the
    /// decode and the screen renders `LoadState.failed`, which is the honest report that this build is older
    /// than the account it is looking at.
    enum Section: String, Sendable, Hashable, Decodable, CaseIterable {
        /// Display name, salary, phone — editable. And email, which is not.
        case personal
        /// The two shipped languages (Product Spec §3.7 **[FIX]**).
        case language
        /// The 160 currencies.
        case currency
        /// Current password → both security questions → new password.
        case password

        /// Whether the row draws a masked value instead of the payload's.
        ///
        /// True for exactly one section, and the mask is app copy. See ``Row/value``.
        var masksValue: Bool { self == .password }
    }

    // MARK: - Personal information

    /// The `#pi` card — four lines, three of them editable.
    struct Personal: Sendable, Hashable, Decodable {
        /// The value the "Username" field is filled from.
        let displayName: String

        /// **Locked** (invariant 4). It is here as well as on ``Profile`` because the two are different
        /// things on the page — the header's subtitle and the card's third line — and because the card is
        /// where the design puts the `.info-note` explaining why it cannot be changed.
        let email: String

        /// Whether the address has been confirmed.
        ///
        /// The banner this drives sits **beside the locked email**, not on the account root: the shell
        /// already carries the app-wide reminder above the tabs (ADR-0031), and two strips saying the same
        /// thing on one screen is one too many. Read from the payload rather than from `SessionCoordinator`
        /// because a screen renders from one response (ADR-0020).
        let isEmailVerified: Bool

        /// The salary — `minor` for the field the user edits, `display` for the line they read (defect D16).
        ///
        /// ``Money/currency`` is the currency it was **authored** in and is what a save sends it back in:
        /// money is stored as authored and there is no storage base (§4.1 **[FIX]**). The design converts
        /// into a `SALARY_BASE` on the way in and out, which is precisely the storage base the [FIX]
        /// removes.
        let salary: Money

        /// The two labels the salary field draws, and the exponent it is read at.
        ///
        /// **Not derivable from ``salary``**, which carries a code and no symbol — and the symbol lives in
        /// the 160-currency reference list, which this page would otherwise have to load to draw one field.
        let salaryCurrency: AuthoringCurrency

        /// `nil` when no number was given, rather than an empty one: phone is optional at registration
        /// (ADR-0031) and "absent" and "blank" are different facts.
        let phone: Phone?
    }

    /// A phone number as the design's `.phone-wrap` needs it: the parts for the two controls, and the
    /// server's own formatting for the read-only line.
    struct Phone: Sendable, Hashable, Decodable {
        /// ISO 3166-1 alpha-2 — the `.dial-iso` chip, and what the country picker's selection is compared
        /// against.
        let country: String
        /// `+91` — the `.dial-code`.
        let dialCode: String
        /// Digits only, for the field.
        let national: String

        /// `+91 98765 43210` — **the server's grouping.** The design's
        /// `national.replace(/(\d{5})(?=\d)/, '$1 ')` splits after five digits, which is an Indian mobile's
        /// grouping applied to all 251 countries.
        let display: String
    }

    // MARK: - Changing the password

    /// What the password flow needs to know before it can ask anything.
    struct Password: Sendable, Hashable, Decodable {
        /// **The two questions this account chose**, by id and by localised text (§4.3 **[FIX]**, D12).
        ///
        /// The ids are what the answers are submitted against, and the text is display content the server
        /// may reword or translate without orphaning a single hash. The answers themselves are not here and
        /// have no field to be in: they are never stored raw, never logged, and never returned to the client
        /// (invariant 5, defect D4).
        let questions: [SecurityQuestion]
    }
}

extension AccountScreen {
    /// One row by section, or `nil`.
    ///
    /// The pushed detail's whole relationship with the payload, exactly as `ExpensesScreen.category(id:)` is:
    /// a page is pushed with a *section* and re-reads its row out of whatever payload is current, so a write
    /// that answers with a new screen re-renders the open page from server truth rather than from the copy it
    /// was pushed with (ADR-0020).
    func row(_ section: Section) -> Row? {
        rows.first { $0.section == section }
    }
}
