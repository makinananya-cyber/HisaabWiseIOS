import Foundation

/// The four steps the strength meter shows, and the formula behind them.
///
/// The design's own: one point for eight characters, another for twelve, another for mixed case, another for a
/// digit *and* a symbol, capped at four. Transcribed rather than replaced by a library — the bars a user sees
/// have to agree with the rule the copy implies, and a third-party estimator would disagree with both.
///
/// **It gates nothing.** The only rule that refuses a password is 8+ (invariant 4); this is feedback.
enum PasswordStrength: Int, Sendable, Equatable, CaseIterable, Comparable {
    case none = 0
    case weak = 1
    case fair = 2
    case good = 3
    case strong = 4

    static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool { lhs.rawValue < rhs.rawValue }

    static func of(_ password: String) -> PasswordStrength {
        guard !password.isEmpty else { return .none }
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.contains(where: \.isUppercase), password.contains(where: \.isLowercase) { score += 1 }
        let hasDigit = password.contains(where: \.isNumber)
        let hasSymbol = password.contains { !$0.isLetter && !$0.isNumber }
        if hasDigit, hasSymbol { score += 1 }
        // A password that scored nothing still shows one lit bar: the meter appears the moment there is
        // something to measure, and an empty meter beside a filled box reads as broken.
        return PasswordStrength(rawValue: max(1, min(score, 4))) ?? .weak
    }
}

/// A phone number as the server stores it: **E.164**, with the parts it was built from kept so the field can be
/// redrawn without re-parsing.
struct PhoneNumber: Sendable, Hashable, Encodable {
    /// ISO 3166-1 alpha-2 of the chosen dial code.
    let country: String
    /// `+971`.
    let dialCode: String
    /// Digits only, as typed.
    let national: String

    /// `+971501234567` — dial code and national digits, nothing else. The one representation that is unambiguous
    /// across borders, which is why it is what goes on the wire.
    var e164: String { "\(dialCode)\(national)" }

    private enum CodingKeys: String, CodingKey { case country, dialCode, national, e164 }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(country, forKey: .country)
        try container.encode(dialCode, forKey: .dialCode)
        try container.encode(national, forKey: .national)
        try container.encode(e164, forKey: .e164)
    }

    /// The most national digits the server will take. Its `phoneSchema` is `^\d{4,15}$`, so past 15 more
    /// typing cannot help — the box stops rather than growing a number that will be refused.
    static let maximumNationalDigits = 15

    /// `text` reduced to the ASCII digits the wire format allows.
    ///
    /// **One funnel for every box that takes a phone number**, because there are two — registration's field and
    /// Account's inline row — and they disagreed. Both used `filter(\.isNumber)`, which is looser than it
    /// reads: `isNumber` is true for "½" and "Ⅷ" as well as "٥", so it passed through characters the server's
    /// `\d` refuses. Neither capped the length, and neither stopped a hardware keyboard, a paste, or dictation
    /// from putting letters in the box at all — a whole alphanumeric password went into one of them.
    ///
    /// Non-ASCII **decimal** digits are converted rather than dropped: an Arabic-locale user typing ٥٠١ means
    /// 501, and a box that silently swallowed their numerals would look broken rather than strict.
    static func nationalDigits(from text: String) -> String {
        let ascii = text.compactMap { character -> Character? in
            guard let value = character.wholeNumberValue, (0...9).contains(value) else { return nil }
            return Character(String(value))
        }
        return String(ascii.prefix(maximumNationalDigits))
    }
}

/// One security question and its answer, on the way to the server **once**.
///
/// Invariant 5 — the raw answer never reaches storage and is never echoed back: the server hashes the normalised
/// key words. The client's job is to send it and forget it, which is why this type is `Encodable` and not
/// `Decodable`: there is no response shape for it to come back in.
struct SecurityAnswer: Sendable, Hashable, Encodable {
    /// The opaque id — `sq07` — never the English text (§4.3 **[FIX]**).
    let questionID: String
    let answer: String

    private enum CodingKeys: String, CodingKey {
        case questionID = "questionId"
        case answer
    }
}

/// Everything the three steps collect, as one body for one request.
///
/// **[FIX] One atomic `POST /v1/auth/register`.** The design walks three screens and the client holds all of it
/// in memory until the end, so there is no half-built account to resume, clean up, or accidentally sign in to.
/// Nothing is persisted server-side until this body is sent.
struct RegistrationRequest: Sendable, Encodable {
    let name: String
    let email: String
    /// `YYYY-MM-DD`. Sent as the date the user chose rather than an age, because an age computed on the client
    /// is an age that changes without the server hearing about it.
    let dateOfBirth: String
    /// Optional at launch, so absent rather than empty when it was not given.
    let phone: PhoneNumber?
    let password: String
    /// The display currency, by ISO code. The symbol and the name are presentation and stay on the client.
    let displayCurrency: String
    /// `{amount, currency}` — never a bare number (invariant 1). `amount` is minor units.
    let salary: MoneyAmount
    let savingsGoal: MoneyAmount
    /// **Whether the goal is the suggestion or the user's own.** Skip and an explicitly typed 20% are the same
    /// figure and different facts, and only this field can tell them apart (#15).
    let goalWasSkipped: Bool
    /// Exactly two, from the 14-question bank.
    let securityAnswers: [SecurityAnswer]
    /// Terms & Privacy, which cannot be false — `validate()` refuses the submission first.
    let acceptedTerms: Bool
    /// Captured here for the same reason ADR-0023 puts it on login and refresh: invariant 6's day boundaries are
    /// computed in the user's stored zone, and registration is the first chance to record one.
    let timeZone: String
    /// So the verification email that registration sends is composed in the language the user is using
    /// (ADR-0024).
    let language: String
}

/// A monetary value on its way *to* the server: minor units and a currency, never a formatted string.
///
/// The mirror of ``Money``, which is what comes *back* — and deliberately a different type, because the response
/// carries a server-formatted `display` string that a request has no business inventing (ADR-0003).
struct MoneyAmount: Sendable, Hashable, Encodable {
    /// An integer count of the currency's smallest unit. Never a float: a salary typed as `8000.5` and rounded
    /// differently on two sides is a figure nobody can reconcile.
    let minor: Int
    let currency: String
}
