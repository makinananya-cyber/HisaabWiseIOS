import Foundation
import Observation

/// Which of the design's three screens the user is on.
enum RegistrationStep: Int, Sendable, Equatable, CaseIterable, Comparable {
    case one = 1
    case two = 2
    case three = 3

    static func < (lhs: RegistrationStep, rhs: RegistrationStep) -> Bool { lhs.rawValue < rhs.rawValue }

    var next: RegistrationStep? { RegistrationStep(rawValue: rawValue + 1) }
    var previous: RegistrationStep? { RegistrationStep(rawValue: rawValue - 1) }
}

/// Every box across the three steps, so a failure can say which one it belongs beside.
enum RegistrationField: Sendable, Equatable, CaseIterable {
    case name, email, phone, dateOfBirth, password, confirmPassword, terms
    case salary, firstQuestion, firstAnswer, secondQuestion, secondAnswer
    case goal
}

/// What is wrong, as a value — the same shape ``SignInFailure`` has, and for the same reason: the rules are worth
/// asserting, and a rendered sentence cannot be asserted about.
enum RegistrationFailure: Sendable, Equatable {
    case nameMissing
    case emailInvalid
    /// **The collision.** There is deliberately no email-availability endpoint — it would be an
    /// account-enumeration oracle — so this only ever arrives from the submit, and it sends the user back to
    /// step 1 with the field marked (#15).
    case emailTaken
    case phoneInvalid(country: String)
    case dateOfBirthMissing
    case tooYoung(minimumAge: Int)
    case passwordTooShort
    case passwordsDoNotMatch
    case termsNotAccepted
    case salaryMissing
    case firstQuestionMissing
    case firstAnswerMissing
    case secondQuestionMissing
    case secondQuestionRepeated
    case secondAnswerMissing
    /// The goal box is empty, or holds something that is not a figure. **Only reachable through Submit** — Skip
    /// sends the suggestion, so it has a figure by definition.
    case goalMissing
    case unreachable
    case refused(ErrorCode)

    var field: RegistrationField? {
        switch self {
        case .nameMissing: .name
        case .emailInvalid, .emailTaken: .email
        case .phoneInvalid: .phone
        case .dateOfBirthMissing, .tooYoung: .dateOfBirth
        case .passwordTooShort: .password
        case .passwordsDoNotMatch: .confirmPassword
        case .termsNotAccepted: .terms
        case .salaryMissing: .salary
        case .firstQuestionMissing: .firstQuestion
        // **Beside the box that is empty, not beside the question.** The two were attached to the question's own
        // field until review, so an unanswered question reddened the picker and left the empty answer unmarked.
        case .firstAnswerMissing: .firstAnswer
        case .secondQuestionMissing, .secondQuestionRepeated: .secondQuestion
        case .secondAnswerMissing: .secondAnswer
        case .goalMissing: .goal
        case .unreachable, .refused: nil
        }
    }

    /// Which step the user has to be on to fix it. The collision is the interesting one: it arrives while the
    /// user is on step 3 and belongs to step 1.
    var step: RegistrationStep {
        switch field {
        case .name, .email, .phone, .dateOfBirth, .password, .confirmPassword, .terms: .one
        case .salary, .firstQuestion, .firstAnswer, .secondQuestion, .secondAnswer: .two
        case .goal, nil: .three
        }
    }
}

/// Registration: three steps in the UI, **one request at the end**.
///
/// Everything the user types is held here until they submit, which is the whole of the [FIX]: there is no
/// half-built account on the server to resume or clean up, and no email-availability call anywhere — that
/// endpoint would answer "does this person have an account" to anybody who asked.
///
/// Not a ``BaseViewModel``, for the reason sign-in's is not: this writes.
@MainActor
@Observable
final class RegistrationViewModel {
    // MARK: Step 1
    var name = ""
    var email = ""
    var country: Country?
    var phoneDigits = ""
    /// `YYYY-MM-DD`, as the design's date input gives it and as the server stores it.
    var dateOfBirth: Date?
    var password = ""
    var confirmPassword = ""
    var acceptedTerms = false

    // MARK: Step 2
    var currency: Currency?
    /// As typed, in major units — "8,000" or "8000.50". Parsed once, at the boundary.
    var salaryText = ""
    var firstQuestion: SecurityQuestion?
    var firstAnswer = ""
    var secondQuestion: SecurityQuestion?
    var secondAnswer = ""

    // MARK: Step 3

    /// What is in the goal box. **Written through ``editGoal(_:)``**, not directly, so that "the user chose this
    /// figure" is a fact the view model knows rather than one it has to guess from the value.
    private(set) var goalText = ""

    /// Whether what is in the box is still the app's suggestion rather than the user's own number.
    ///
    /// It is what makes the pre-fill **re-derive**: the box is filled on the way into step 3, and a user who goes
    /// back and corrects their salary must not arrive at a goal computed from the old one. Guarding the pre-fill
    /// on `goalText.isEmpty` — which is what it did until review — left `1600` in the box beside a statement card
    /// reading `4000`, and submitted it as an explicit choice.
    private(set) var goalIsSuggestion = true

    private(set) var goalWasSkipped = false

    // MARK: The reference lists

    /// The 251 countries, the 160 currencies, and the 14 questions — **fetched, never compiled in**
    /// (ADR-0009). Empty until ``loadReferenceLists()`` has run.
    private(set) var countries: [Country] = []
    private(set) var currencies: [Currency] = []
    private(set) var questions: [SecurityQuestion] = []
    var isLoadingReferenceLists: Bool { listsInFlight != nil }

    /// The one load in flight, or `nil`.
    ///
    /// **A second caller awaits this task rather than returning early**, which is the difference between
    /// `await loadReferenceLists()` meaning "the lists are there now" and meaning "somebody is working on it".
    /// There are genuinely two concurrent callers — the screen's `.task` and the retry button — and an early
    /// return leaves the second one carrying on against three empty arrays. The same single-flight shape
    /// `APIClient` uses for a refresh, and for the same reason: the guard that only *skips* work is the one that
    /// silently lies about what it did.
    private var listsInFlight: Task<Void, Never>?

    /// Why the lists are not there, if they are not.
    ///
    /// **Separate from ``failures``, which is about what the user typed.** A list that would not load is not a
    /// field error and cannot be corrected by editing anything; it is the one condition on this screen that has
    /// a retry rather than a fix, and folding it into the form's failures would put an offline message under the
    /// email box.
    private(set) var referenceFailure: RegistrationFailure?

    /// Whether the lists have been asked for at all.
    ///
    /// The screen's `.task` is what asks, and it runs *after* the first body evaluation — so for one frame the
    /// state is "three empty lists and no failure", which is not a failure and must not be drawn as one. It read
    /// "something went wrong · Try again" until review, on every entry to the screen.
    private(set) var hasAskedForReferenceLists = false

    /// Whether the form can be drawn at all. The currency and the two questions are pickers over server content
    /// — there is no keyboard fallback for them — so a form without the lists is a form with three dead
    /// controls.
    var hasReferenceLists: Bool { !currencies.isEmpty && !questions.isEmpty && !countries.isEmpty }

    // MARK: State
    private(set) var step: RegistrationStep = .one
    private(set) var failures: [RegistrationFailure] = []
    private(set) var isSubmitting = false

    /// Product Spec §3.3 — 13+, which is also the App Store age rating this app carries.
    static let minimumAge = 13
    /// The design's own floor for the date picker, so a mistyped year lands inside a sensible range.
    static let maximumAge = 120
    static let minimumPasswordLength = 8
    /// The design's own: `/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/`. Deliberately loose — it refuses what is obviously not
    /// an address and leaves the rest to the server, because every stricter regex is wrong about somebody's real
    /// email.
    static let emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/
    /// The design's 6–15 digits, which is E.164's own range for a national number.
    static let phoneDigitRange = 6...15

    /// The **national significant number** — the digits typed, with any trunk prefix removed.
    ///
    /// E.164 has no trunk prefix in it: `+971 50 123 4567`, never `+971 050…`. A UAE resident writing their number
    /// the way it is written locally types `0501234567`, and concatenating that onto `+971` produced a thirteen-
    /// digit string that is inside the accepted range and is not a dialable number. Stripped here rather than in
    /// `PhoneNumber`, so validation counts the digits that will actually be sent.
    var phoneSignificantDigits: String {
        var digits = phoneDigits.digits
        while digits.first == "0" { digits.removeFirst() }
        return digits
    }
    /// The 20% rule the design states in step 3's own copy.
    static let suggestedGoalShare = 0.20

    /// The design's own defaults: India's dial code and the Indian Rupee, applied once the lists arrive.
    ///
    /// Transcribed rather than re-picked. The design opens on `IN`/`INR` — the largest remitting group among UAE
    /// expatriates — and choosing differently here would be a product decision made in a view model.
    static let defaultCountryCode = "IN"
    static let defaultCurrencyCode = "INR"

    private let session: SessionCoordinator
    private let content: ContentLoader

    /// The two hosted pages the consent checkbox links to (#15). From build configuration, never a literal — the
    /// domain arrives with the owner's Cloudflare credentials (Rule 7, ADR-0010).
    let legal: LegalLinks

    /// The app's language choice, read for one field: the body records it so that the verification email — and
    /// every message composed later — is in the language the user registered in (ADR-0024). Taken rather than
    /// reached for, because a view model does not know what an environment is.
    private let language: LanguageManager

    init(
        session: SessionCoordinator,
        content: ContentLoader,
        language: LanguageManager,
        legal: LegalLinks
    ) {
        self.session = session
        self.content = content
        self.language = language
        self.legal = legal
    }

    // MARK: - The reference lists

    /// Loads the three lists, in parallel, and applies the design's defaults to the two that have one.
    ///
    /// Idempotent and re-entrant-safe: called from the screen's `.task` and again by the retry, and a second
    /// call while one is in flight returns immediately rather than doubling the requests.
    ///
    /// **All three or none.** A form with countries and no currencies is a form the user can fill in halfway
    /// before discovering it, so one failure fails the screen and the retry asks for all three again — which
    /// costs nothing, because the two that succeeded are revalidated with their ETags and answer `304`.
    func loadReferenceLists() async {
        if let listsInFlight {
            await listsInFlight.value
            return
        }

        let task = Task { await self.fetchReferenceLists() }
        listsInFlight = task
        await task.value
        listsInFlight = nil
    }

    private func fetchReferenceLists() async {
        hasAskedForReferenceLists = true
        referenceFailure = nil

        do {
            // Three conditional GETs together rather than in sequence: they are independent, and a registration
            // form that opens in three round trips on a slow network opens slowly for no reason.
            async let countries = content.load(.countries, as: CountryList.self)
            async let currencies = content.load(.currencies, as: CurrencyList.self)
            async let questions = content.load(.securityQuestions, as: SecurityQuestionList.self)

            self.countries = try await countries.countries
            self.currencies = try await currencies.currencies
            self.questions = try await questions.questions
        } catch is CancellationError {
            // Reachable only through an explicit cancel: the load runs in a stored, **unstructured** `Task` —
            // which is what makes it joinable by a second caller — and an unstructured task does not inherit
            // cancellation from the `.task` that started it. So leaving the screen mid-fetch does not cancel these
            // three requests; they finish, fill an object nobody is looking at, and are released with it. Handled
            // rather than left to the general arm because a cancelled load is not something to show a failure for.
            return
        } catch {
            referenceFailure = Self.failure(for: error)
            return
        }

        // Applied after the lists arrive, and only over an empty choice: a user who has already picked
        // something and gone back a step must not find it reset to the default.
        if country == nil {
            country = self.countries.first { $0.code == Self.defaultCountryCode } ?? self.countries.first
        }
        if currency == nil {
            currency = self.currencies.first { $0.code == Self.defaultCurrencyCode } ?? self.currencies.first
        }
    }

    // MARK: - Choosing from a picker

    /// **The pickers hand back an id, and these are what turn one into a choice.**
    ///
    /// Not `Binding<Country?>` set directly from the view, and that is the §4.3 **[FIX]** made structural: a
    /// question is identified by `sq07` and never by its English wording, so what crosses from the sheet is the
    /// id. A view that assembled the model itself would be a view that could assemble one the list does not
    /// contain.
    ///
    /// An unknown id is ignored rather than clearing the choice: the only way to send one is a list that has
    /// changed underneath the open sheet, and losing the user's current answer over it would be the worse of the
    /// two outcomes.
    func chooseCountry(code: String) {
        guard let match = countries.first(where: { $0.code == code }) else { return }
        country = match
        clearFailure(for: .phone)
    }

    func chooseCurrency(code: String) {
        guard let match = currencies.first(where: { $0.code == code }) else { return }
        currency = match
        clearFailure(for: .salary)
    }

    func chooseFirstQuestion(id: String) {
        guard let match = questions.first(where: { $0.id == id }) else { return }
        firstQuestion = match
        clearFailure(for: .firstQuestion)
    }

    func chooseSecondQuestion(id: String) {
        guard let match = questions.first(where: { $0.id == id }) else { return }
        secondQuestion = match
        clearFailure(for: .secondQuestion)
    }

    /// The questions offered for one of the two slots: every question **except the one the other slot holds**.
    ///
    /// The design filters the list rather than validating after the fact, and that is the better of the two —
    /// "choose a second, different question" is a rule the picker can make unbreakable instead of a message the
    /// user reads after breaking it. ``validateStepTwo`` still refuses a repeat, because the two slots can also
    /// be filled in the other order.
    func questions(excluding other: SecurityQuestion?) -> [SecurityQuestion] {
        guard let other else { return questions }
        return questions.filter { $0 != other }
    }

    var passwordStrength: PasswordStrength { .of(password) }

    /// The failure beside one box, if any.
    func failure(for field: RegistrationField) -> RegistrationFailure? {
        failures.first { $0.field == field }
    }

    /// The failure that belongs to the form rather than to a box.
    var formFailure: RegistrationFailure? {
        failures.first { $0.field == nil }
    }

    func clearFailure(for field: RegistrationField) {
        failures.removeAll { $0.field == field }
    }

    // MARK: - Salary and the goal

    /// The salary in minor units, or `nil` if what was typed is not a figure.
    ///
    /// Grouping separators are stripped rather than parsed by a formatter: the field is a keypad, the user may
    /// type `8,000` or `8000`, and a locale-aware parse would disagree with itself between languages. **This is
    /// not client-side money arithmetic** — it is reading one number the user typed, before any currency exists
    /// to convert it into (ADR-0003).
    var salaryMinor: Int? { Self.minor(from: salaryText) }

    /// 20% of the salary, in minor units — what step 3 pre-fills and what **Skip for now** accepts.
    var suggestedGoalMinor: Int? {
        guard let salaryMinor else { return nil }
        return Int((Double(salaryMinor) * Self.suggestedGoalShare).rounded())
    }

    var goalMinor: Int? { Self.minor(from: goalText) }

    /// How what the user typed compares with the suggestion, or `nil` while there is nothing to compare.
    ///
    /// A `ComparisonResult` rather than three booleans, because the design's hint has exactly three endings —
    /// on the rule, ahead of it, under it — and a pair of booleans leaves a fourth combination representable.
    var goalAgainstSuggestion: ComparisonResult? {
        guard let goalMinor, let suggestedGoalMinor else { return nil }
        if goalMinor == suggestedGoalMinor { return .orderedSame }
        return goalMinor > suggestedGoalMinor ? .orderedDescending : .orderedAscending
    }

    /// Whether to offer `.suggest` — "Use the suggested amount".
    ///
    /// Hidden when the box already holds the suggestion (`useBtn.hidden = typed === s`) and when it holds nothing
    /// at all, where the design points at **Skip for now** instead: a button that sets a field to what it already
    /// says, or that duplicates the control beneath it, is a button that does nothing.
    var suggestsUsingTheSuggestion: Bool {
        goalMinor != nil && goalAgainstSuggestion != .orderedSame
    }

    /// `.suggest` — puts the suggestion in the box, leaving it editable. It does **not** submit: the user asked
    /// for the figure, not for the account.
    func useSuggestedGoal() {
        guard let suggestedGoalText else { return }
        goalText = suggestedGoalText
        goalIsSuggestion = true
        clearFailure(for: .goal)
    }

    /// The user typing in the goal box. **The only way `goalText` changes from the outside**, because the typing is
    /// what makes the figure theirs rather than the app's.
    func editGoal(_ text: String) {
        goalText = text
        goalIsSuggestion = false
        clearFailure(for: .goal)
    }

    /// The live "% of salary" step 3 shows as the user types, rounded to whole points.
    ///
    /// The one figure this app computes on the client, and it is not money: it is a ratio between two numbers the
    /// user typed on this screen, before either has reached a server. Every *displayed* figure that belongs to an
    /// account still comes from a response (ADR-0020).
    var goalShareOfSalary: Int? {
        guard let goalMinor, let salaryMinor, salaryMinor > 0 else { return nil }
        return Int((Double(goalMinor) / Double(salaryMinor) * 100).rounded())
    }

    /// That share as the string the copy interpolates — Latin digits, no grouping, no locale (ADR-0011).
    ///
    /// Converted here rather than at the call site because **every argument this app's copy takes is a string**:
    /// that is what makes a catalogue key derivable from the source it is written in, and it is the rule
    /// `LocalisationTests` reads `Views/` against. A number interpolated into a `Text` would resolve to a key
    /// spelled `%lld` and quietly find nothing.
    var goalShareText: String? {
        goalShareOfSalary.map { "\($0)" }
    }

    /// The suggested figure as the step-3 statement draws it — major units, so `800000` reads `8000`.
    ///
    /// The one number on this screen the client composes, and it is **not** a converted or formatted monetary
    /// value: it is 20% of a figure the user typed one field earlier, before any of it has reached a server
    /// (ADR-0003 governs figures that come *back*).
    var suggestedGoalText: String? {
        suggestedGoalMinor.map(Self.majorString)
    }

    /// Reads a typed figure into minor units, or `nil` if what was typed is not a figure.
    ///
    /// The rule itself — which separator is the decimal point, and what happens to a figure typed in Eastern
    /// Arabic-Indic digits — lives in ``TypedAmount`` now that Expenses (#18) is a second caller. It was
    /// private to this file, and a second copy of a rule whose failure mode is a 100× error is not a copy
    /// worth having.
    ///
    /// **Two minor digits**, and this screen has no exponent to pass: the reference list carries a code, a name,
    /// and a symbol. A three-digit currency (KWD, BHD, OMR) is recorded in `CONTEXT.md` as a field the list has
    /// to grow. Expenses reads its exponent from the screen payload, which is why that caller passes a real one.
    ///
    /// It took a `Currency?` and never read it. Kept as a wrapper rather than inlined so the two call sites above
    /// state the exponent decision once.
    private static func minor(from text: String) -> Int? {
        TypedAmount.minor(from: text, exponent: 2)
    }

    // MARK: - Moving between steps

    /// Validates the current step and advances. The **only** way forward, so a step cannot be skipped past.
    func advance() {
        failures = validate(step, goalMinor: goalMinor)
        guard failures.isEmpty, let next = step.next else { return }
        if next == .three, goalIsSuggestion, let suggested = suggestedGoalMinor {
            // The design pre-fills step 3 with the suggestion, so the user starts on the figure rather than on an
            // empty box — and it is re-derived every time the step is entered, so a corrected salary corrects the
            // goal with it. A figure the user typed is left alone.
            goalText = Self.majorString(suggested)
        }
        step = next
    }

    func goBack() {
        guard let previous = step.previous else { return }
        failures = []
        step = previous
    }

    /// Minor units back into what the field shows — `800000` → `"8000"`, `800050` → `"8000.50"`.
    ///
    /// Two minor digits for the reason ``minor(from:currency:)`` reads two: this screen has no exponent.
    static func majorString(_ minor: Int) -> String {
        TypedAmount.major(minor, exponent: 2)
    }

    // MARK: - The one request

    /// Submits everything, from any step, with the goal the user typed.
    func submit() async {
        goalWasSkipped = false
        await submit(goalMinor: goalMinor)
    }

    /// **Skip for now** — accepts the suggestion and records that it was not chosen (#15).
    func skipGoal() async {
        goalWasSkipped = true
        await submit(goalMinor: suggestedGoalMinor)
    }

    private func submit(goalMinor: Int?) async {
        // Every step's rules, not just this one: the atomic call means a field left invalid two screens ago would
        // otherwise reach the server.
        // Every step's rules against **the figure actually being sent**, which is what makes one function serve
        // both buttons: Submit passes what was typed and Skip passes the suggestion.
        failures = RegistrationStep.allCases.flatMap { validate($0, goalMinor: goalMinor) }
        guard failures.isEmpty else {
            // Back to the earliest step that has something wrong with it, which is where the user can fix it.
            step = failures.map(\.step).min() ?? step
            return
        }
        guard let request = request(goalMinor: goalMinor) else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await session.register(request)
        } catch {
            let failure = Self.failure(for: error)
            failures = [failure]
            // An email collision is the one failure that moves the user: it belongs to step 1, and it is the only
            // way the client ever learns the address is taken (#15).
            if failure.field != nil { step = failure.step }
        }
    }

    /// The body, built once from what all three steps collected.
    func request(goalMinor: Int?) -> RegistrationRequest? {
        guard let currency, let salaryMinor, let goalMinor,
              let dateOfBirth, let firstQuestion, let secondQuestion
        else { return nil }

        return RegistrationRequest(
            name: name.trimmed,
            email: email.trimmed,
            dateOfBirth: Self.isoDay(dateOfBirth),
            // Optional at launch: absent rather than empty when it was not given.
            phone: phoneDigits.isEmpty ? nil : country.map {
                PhoneNumber(country: $0.code, dialCode: $0.dialCode, national: phoneSignificantDigits)
            },
            password: password,
            displayCurrency: currency.code,
            salary: MoneyAmount(minor: salaryMinor, currency: currency.code),
            savingsGoal: MoneyAmount(minor: goalMinor, currency: currency.code),
            goalWasSkipped: goalWasSkipped,
            securityAnswers: [
                SecurityAnswer(questionID: firstQuestion.id, answer: firstAnswer.trimmed),
                SecurityAnswer(questionID: secondQuestion.id, answer: secondAnswer.trimmed),
            ],
            acceptedTerms: acceptedTerms,
            timeZone: TimeZone.current.identifier,
            language: language.acceptLanguage
        )
    }

    /// The calendar every date rule here uses: **Gregorian, in the device's own zone.**
    ///
    /// One calendar for all three of `isoDay`, `dateOfBirthRange`, and `age(on:now:)` — and the zone has to be the
    /// device's, because that is the zone the value was produced in. A `DatePicker` yields the instant at which
    /// the chosen wall-clock day began *locally*, carrying the time-of-day of whatever it replaced; reading its
    /// components in UTC then moves the day across midnight for every user whose local time is inside the UTC
    /// offset. In `Asia/Dubai` — the target market — anybody registering before 04:00 would have sent a birthday
    /// one day early.
    ///
    /// The cost is that a *span* measured this way crosses historical offset changes: the Gulf adopted +04:00 in
    /// 1920, so "120 years ago" is 119 years and 364 days. That is fine for the oldest date a picker offers and
    /// would not be fine for a birthday, which is why the zone follows the input rather than the arithmetic.
    ///
    /// It is not a *display* calendar: the date the user reads is drawn by the system's own `DatePicker`, in the
    /// environment's locale (ADR-0011). This is arithmetic.
    private static var calendar: Calendar { Calendar(identifier: .gregorian) }

    /// `YYYY-MM-DD` — **the calendar day the user chose**, read in the zone they chose it in.
    static func isoDay(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        // Padded by hand. `String(format:)` is banned app-wide — it is the halfway house to a sentence assembled
        // at a call site (ADR-0011) — and a `DateFormatter` would format against a locale, which for a wire
        // format is exactly wrong: `YYYY-MM-DD` is not a date the user reads.
        func padded(_ value: Int, to width: Int) -> String {
            let digits = "\(value)"
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(padded(parts.year ?? 0, to: 4))-\(padded(parts.month ?? 0, to: 2))-\(padded(parts.day ?? 0, to: 2))"
    }

    /// The oldest date of birth that is still under 13, and the youngest that is over 120 — the range the picker
    /// offers, so the commonest mistake is unavailable rather than rejected.
    static func dateOfBirthRange(now: Date = Date()) -> ClosedRange<Date> {
        let newest = calendar.date(byAdding: .year, value: -minimumAge, to: now) ?? now
        let oldest = calendar.date(byAdding: .year, value: -maximumAge, to: now) ?? now
        return oldest...newest
    }

    static func age(on birthday: Date, now: Date = Date()) -> Int {
        calendar.dateComponents([.year], from: birthday, to: now).year ?? 0
    }

    // MARK: - What is wrong

    func validate(_ step: RegistrationStep, goalMinor: Int?) -> [RegistrationFailure] {
        switch step {
        case .one: validateStepOne()
        case .two: validateStepTwo()
        case .three: validateStepThree(goalMinor: goalMinor)
        }
    }

    private func validateStepOne() -> [RegistrationFailure] {
        var failures: [RegistrationFailure] = []
        if name.trimmed.isEmpty { failures.append(.nameMissing) }
        if email.trimmed.wholeMatch(of: Self.emailPattern) == nil { failures.append(.emailInvalid) }
        // Optional at launch — but a number that *is* given has to be one, counted on the digits that will be
        // sent rather than the digits that were typed.
        if !phoneDigits.isEmpty, !Self.phoneDigitRange.contains(phoneSignificantDigits.count) {
            failures.append(.phoneInvalid(country: country?.name ?? ""))
        }
        if let dateOfBirth {
            // **Blocked on the client as well as the server** (#15): the server is authoritative, and a form that
            // sends a 12-year-old's details to be refused has already collected them.
            if Self.age(on: dateOfBirth) < Self.minimumAge { failures.append(.tooYoung(minimumAge: Self.minimumAge)) }
        } else {
            failures.append(.dateOfBirthMissing)
        }
        if password.count < Self.minimumPasswordLength { failures.append(.passwordTooShort) }
        if confirmPassword != password { failures.append(.passwordsDoNotMatch) }
        if !acceptedTerms { failures.append(.termsNotAccepted) }
        return failures
    }

    private func validateStepTwo() -> [RegistrationFailure] {
        var failures: [RegistrationFailure] = []
        if currency == nil || salaryMinor == nil { failures.append(.salaryMissing) }
        if firstQuestion == nil {
            failures.append(.firstQuestionMissing)
        } else if firstAnswer.trimmed.isEmpty {
            failures.append(.firstAnswerMissing)
        }
        if secondQuestion == nil {
            failures.append(.secondQuestionMissing)
        } else if secondQuestion == firstQuestion {
            // The design asks for "a second, *different* question": two answers to one question is one answer.
            failures.append(.secondQuestionRepeated)
        } else if secondAnswer.trimmed.isEmpty {
            failures.append(.secondAnswerMissing)
        }
        return failures
    }

    /// - Parameter goalMinor: the figure being submitted. What the user typed, from Submit; the suggestion, from
    ///   Skip — which is why the emptied-box case cannot block Skip.
    private func validateStepThree(goalMinor: Int?) -> [RegistrationFailure] {
        // The box arrives pre-filled with the suggestion, so this only fires for a user who deliberately cleared
        // it and pressed Submit rather than Skip. The design says the same thing there: "Enter a goal, or tap
        // Skip for now."
        goalMinor == nil ? [.goalMissing] : []
    }

    /// An error from the one request, as a failure the form can draw. The second half of sign-in's rule: a
    /// refusal must not describe *why* beyond what the user can act on.
    static func failure(for error: any Error) -> RegistrationFailure {
        guard let apiError = error as? APIError else { return .refused(.unknown) }
        switch apiError {
        case .offline: return .unreachable
        case .malformedResponse: return .refused(.malformedResponse)
        case .unauthenticated: return .refused(.unauthenticated)
        case .server(_, let code):
            // The collision, which is the only per-field failure registration can receive.
            return code == .emailTaken ? .emailTaken : .refused(code)
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var digits: String { filter(\.isNumber) }
}
