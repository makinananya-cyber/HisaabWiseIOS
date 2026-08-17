import Foundation
import Observation

/// Account: **one read, four writes, one download, and the two settings that make every other screen stale**
/// (ADR-0020, ADR-0038).
///
/// The read half is three lines, as every screen's is. What the rest of this object is about is the four things
/// the design's `state` object held and a real client may not:
///
/// - **The salary is not a number here.** It is `Money.minor` on the way out of the payload and a typed string on
///   the way back in, and it never passes through a display string in either direction. That is defect D16:
///   the design renders `money(salaryShown())`, which rounds to the nearest whole unit, and then reads the
///   *rendered* figure back when the user saves — so opening the editor and pressing Save quantises the income
///   the budget engine runs on.
/// - **The security answers are not compared here.** Invariant 5 and defect D4: the design holds the answers in
///   `state.security[i].answer` and matches them in the browser with a Levenshtein distance. Everything about
///   that is the server's, so the three steps of the password flow are this object's *sequencing* of one
///   submission (``PasswordChange``).
/// - **The currency is not converted here.** `HWMoney.to(...)` in the design converts every figure on screen the
///   moment the picker closes. Here the change is a request, and what comes back is the truth — for this screen
///   from the write itself, and for the other four through ``ScreenRepaint``.
/// - **The language is not switched here either.** `LanguageManager` owns that (ADR-0024), including the revert
///   when the server disagrees; this object calls it and repaints.
///
/// **It is the fifth owner of an error-to-presentation mapping**, and `StateTaxonomyTests` names it. Three of
/// the four writes map exactly as Expenses' do — offline becomes `LoadState.offline`, because there is nothing to
/// correct and no queue to hold it (ADR-0019). The **preference** writes are the exception, and the one place in
/// the app where an offline write does not replace the screen: see ``Refusal``. Which of the two a write gets is
/// ``WriteKind``'s to say, so there is one write helper rather than two that differed only in their `catch`.
@MainActor
@Observable
final class AccountViewModel: BaseViewModel {
    /// Not `private(set)`: ``BaseViewModel`` requires a settable `state`, and the trade-off is recorded there.
    /// Mutation stays inside `load()` and the write helpers by convention.
    var state: LoadState<AccountScreen> = .loading

    // MARK: - Personal information

    /// `.editbtn.on` — whether the personal card is in edit mode.
    ///
    /// Per *visit*, like Expenses' `isEditing`: arriving at the page should not find it mid-edit from the last
    /// time, which is what the design's `open()` resets.
    private(set) var isEditingPersonal = false

    /// The three editable fields as they currently read, plus what is wrong with them.
    private(set) var personal = PersonalDraft()

    // MARK: - Changing the password

    /// Which step the flow is on, what has been typed into it, and how many times the answers have missed.
    private(set) var password = PasswordDraft()

    // MARK: - What the screen reports

    /// The last write that landed, for the toast. `nil` once it has been shown.
    ///
    /// A **value**, not a sentence: which words go with it is the screen's copy (ADR-0011).
    private(set) var notice: Notice?

    /// Why the last attempt at one thing did not happen, or `nil`. See ``Refusal``.
    ///
    /// **It names what it is about**, and review is what made that necessary: with one bare reason in here, a
    /// failed *export* on the root drew its banner over the currency picker and a failed currency change drew one
    /// under the export button. Three controls, one field, three wrong sentences.
    private(set) var refusal: Refusal?

    /// Whether a write is in flight, so a control can say so rather than accepting a second tap.
    private(set) var isWriting = false

    // MARK: - Deleting the account

    /// True while `DELETE /v1/me` is in flight, so the control shows a spinner rather than accepting a second
    /// tap on the one action here that cannot be undone by pressing it again.
    private(set) var isDeletingAccount = false

    // MARK: - Cacheable content

    /// The 160 currencies and the 251 countries, once they have been fetched. Cacheable content on their own
    /// ETags, so a second launch revalidates rather than downloading them again (ADR-0009) — and the same two
    /// lists registration reads, which is why neither is in the screen payload (ADR-0020).
    private var currencies: [Currency] = []
    private var countries: [Country] = []

    /// The currency the salary is **typed in**, from the most recent payload.
    ///
    /// Held rather than read from `state` at write time, for the reason `ExpensesViewModel.authoring` is: a write
    /// that failed offline has left `state` with no payload in it, and a retry still has to know which currency
    /// the figure in the box is in.
    private var authoring: AuthoringCurrency?

    private let client: APIClient
    private let content: ContentLoader

    /// The one owner of the language choice (ADR-0024). Held rather than reached for, because the picker on this
    /// screen is the only thing in the app that calls `select(_:)`.
    private let language: LanguageManager

    /// Every other screen, so that a preference change reaches them.
    ///
    /// `weak`, and connected rather than injected: `TabViewModels` holds *this* object, so a strong reference back
    /// would be a cycle. The graph closes the loop with one call, exactly as it does for the language manager.
    private weak var repaint: (any ScreenRepaint)?

    /// Who is signed in, so that deleting the account can end the session.
    ///
    /// **Held here rather than read by the control**, because `AppShellTests` keeps `signOut()` to a single caller
    /// in the presentation layers and deletion should not become a second exit written in a view. The scan covers
    /// `Views/`, `Components/` and `DesignSystem/`; a view model ending the session it was handed is the same
    /// decision made in one place rather than two.
    private let session: SessionCoordinator

    init(
        client: APIClient,
        content: ContentLoader,
        language: LanguageManager,
        session: SessionCoordinator
    ) {
        self.client = client
        self.content = content
        self.language = language
        self.session = session
    }

    /// Closes the loop between this screen and the four it makes stale. Called once, by `AppEnvironment`.
    func connect(to repaint: any ScreenRepaint) {
        self.repaint = repaint
    }

    /// Re-reads the account **without blanking it first**.
    ///
    /// `load()` flips `state` to `.loading`, which on a page the reader is already looking at means the card
    /// vanishes and comes back. This keeps the current payload on screen and swaps it when the new one lands, so a
    /// page that reappears catches up quietly.
    ///
    /// **Why it exists.** The tab holds the payload it read when it was first opened, and the personal page reads
    /// that same held copy — so a salary changed anywhere else left this page showing the old figure while Home
    /// computed "% of pay" from the new one. Observed exactly that: 12,000 on the personal page and a Home reading
    /// 24% that only makes sense against 20,000. Invariant 2 says the salary has one owner; two screens disagreeing
    /// about it is the defect that invariant exists to prevent, even when neither figure was computed on the client.
    ///
    /// A failure is **silent on purpose**: the reader has a perfectly good payload on screen, and replacing it with
    /// an error because a background re-read did not land would be a worse report than saying nothing.
    func refreshQuietly() async {
        guard let screen = try? await fetch() else { return }
        state = .loaded(screen)
    }

    // MARK: - The single read

    /// **The single read.** No second call and no join — the two reference lists are cacheable content fetched on
    /// demand, which is ADR-0020's seam rather than an exception to it.
    func fetch() async throws -> AccountScreen {
        let screen = try await client.get(Endpoint.screenAccount, as: AccountScreen.self)
        authoring = screen.personal.salaryCurrency
        return screen
    }

    /// Whether a *loaded* Account has nothing to show.
    ///
    /// `false`, and there is no arrangement in which it could be anything else: an account always has an address,
    /// a name, a salary and four rows. `LoadState.empty` on this screen would be a signed-in user being told they
    /// have no account.
    func isEmpty(_ screen: AccountScreen) -> Bool { false }

    // MARK: - What the screen reads back

    /// One row out of the **current** payload, or `nil`.
    ///
    /// The pushed page's whole relationship with the screen, exactly as `ExpensesViewModel.category(id:)` is: a
    /// page is opened with a section and re-reads its row every time it draws, so a write that answers with a new
    /// payload re-renders the open page from server truth (ADR-0020).
    func row(_ section: AccountScreen.Section) -> AccountScreen.Row? {
        state.value?.row(section)
    }

    /// The personal card's four lines, or `nil` before the first payload.
    var personalDetails: AccountScreen.Personal? { state.value?.personal }

    /// The two questions the password flow asks, in the order the payload lists them.
    var securityQuestions: [SecurityQuestion] { state.value?.password.questions ?? [] }

    /// The symbol beside the salary field. Decoration around a number being typed, never formatting (ADR-0003).
    var salarySymbol: String { authoring?.symbol ?? "" }

    /// The stored language, from the payload — **not** from ``LanguageManager``.
    ///
    /// The two agree except during a switch, and which one the picker's tick follows matters: the manager is
    /// optimistic and reverts on failure (ADR-0024), so following *it* would tick a language the server has not
    /// accepted. The payload is what the server stored.
    var storedLanguage: AppLanguage? { state.value?.language }

    /// The display currency, from the payload.
    var displayCurrency: CurrencyCode? { state.value?.currency }

    /// The two shipped languages, in the order a picker lists them (Product Spec §3.7 **[FIX]**, ADR-0011).
    ///
    /// **`AppLanguage.shipped`, never a list of 87.** The design's `LANGUAGES` constant is reference content the
    /// backend serves and the picker offers the promise instead — which is why nothing in this file fetches a
    /// language list at all.
    var shippedLanguages: [AppLanguage] { language.shipped }

    /// The 160 currencies, once they have arrived.
    var displayCurrencies: [Currency] { currencies }

    /// The 251 countries, once they have arrived.
    var dialCodes: [Country] { countries }

    // MARK: - The reference lists

    /// Fetches the currency list, once.
    ///
    /// On demand rather than with the screen, for the reason Expenses fetches its pick lists on the first press:
    /// the screen paints from one request, and 160 currencies nobody may ask for are not worth a second one at
    /// load time.
    ///
    /// A list that will not load leaves the screen alone and reports nothing — an empty picker is a worse screen,
    /// not a broken one, and a failed *ancillary* fetch must not replace a screen that is fine (which is why this
    /// does not go through `load()`).
    func loadCurrencies() async {
        guard currencies.isEmpty else { return }
        currencies = (try? await content.load(.currencies, as: CurrencyList.self))?.currencies ?? []
    }

    /// Fetches the country list, once — the dial codes behind the phone row's `.dial` trigger.
    func loadDialCodes() async {
        guard countries.isEmpty else { return }
        countries = (try? await content.load(.countries, as: CountryList.self))?.countries ?? []
    }

    // MARK: - Editing the personal card

    /// Turns edit mode on, filling the three fields from the payload.
    ///
    /// **The salary is read from ``Money/minor``, and this is where defect D16 is fixed.** `TypedAmount.major`
    /// turns minor units into the digits a keypad produced; `Money.display` is "₹65,000", which has been through
    /// magnitude-aware rounding and is not a number this app is allowed to parse. The two directions use *their
    /// own* exponents — the figure's for reading it out and the authoring currency's for reading it back — which
    /// is the 10× trap `ExpensesViewModel.beginEditing` records.
    func beginEditingPersonal() {
        guard let details = state.value?.personal else { return }

        isEditingPersonal = true
        personal = PersonalDraft(
            displayName: details.displayName,
            salary: TypedAmount.major(details.salary.minor, exponent: details.salary.exponent),
            country: details.phone?.country ?? "",
            dialCode: details.phone?.dialCode ?? "",
            national: details.phone?.national ?? ""
        )
    }

    /// Leaves edit mode without saving — the way back out that does not commit.
    func cancelEditingPersonal() {
        isEditingPersonal = false
        personal = PersonalDraft()
    }

    func editDisplayName(_ text: String) {
        personal.displayName = text
        personal.failures.remove(.nameMissing)
    }

    func editSalary(_ text: String) {
        personal.salary = text
        personal.failures.remove(.salaryMissing)
    }

    func editPhoneDigits(_ text: String) {
        // Digits only, as the design's `value.replace(/[^0-9]/g, '')` does — a phone number is not a place for a
        // space, a dash or a second plus, and stripping them as they are typed is kinder than refusing later.
        //
        // **ASCII digits specifically, and non-ASCII ones are converted rather than dropped.** `\.isNumber` accepts
        // `٥`, and the server's `^\d{4,15}$` does not — so filtering on it alone let a number through the box that
        // the write then refused. An Arabic-locale reader typing ٥٠١ means 501, and a box that silently swallowed
        // their numerals would look broken. Capped at 15 because that is where the server stops caring.
        personal.national = String(
            text.compactMap { character -> Character? in
                guard let value = character.wholeNumberValue, (0...9).contains(value) else { return nil }
                return Character(String(value))
            }
            .prefix(15)
        )
        personal.failures.remove(.phoneInvalid)
    }

    /// A dial code from the country sheet. **The ISO code and the dial code together**, because a `+971` with no
    /// country behind it is a number the server cannot store against a country (``PhoneNumber``).
    func chooseDialCode(country code: String) {
        guard let country = countries.first(where: { $0.code == code }) else { return }
        personal.country = country.code
        personal.dialCode = country.dialCode
        personal.failures.remove(.phoneInvalid)
    }

    /// **Save changes** — `PUT /v1/me`.
    ///
    /// Email is not in the body and cannot be: it is the identity (invariant 4), it is drawn locked, and
    /// ``PersonalDetailsUpdate`` has no field for it.
    func savePersonalDetails() async {
        guard let request = validatedPersonalDetails() else { return }

        let saved = await write(.details, notice: .personalUpdated) {
            try await self.client.put(Endpoint.me, body: request, as: AccountScreen.self)
        }
        // Only on success: a write that failed leaves the user in edit mode with their typing intact, which is
        // the whole of what can be offered when there is no queue (ADR-0019).
        if saved { cancelEditingPersonal() }
    }

    /// The body to send, or `nil` — in which case ``PersonalDraft/failures`` says which fields are wrong.
    ///
    /// **Local input validation, which is not a calculation** (ADR-0020): it decides whether there is something to
    /// send, not what any figure is. Every rule is the design's own, and a **set** of failures rather than the
    /// first one, because the design marks every bad field at once and says "Check the highlighted details."
    private func validatedPersonalDetails() -> PersonalDetailsUpdate? {
        guard let currency = authoring else { return nil }

        var failures: Set<PersonalDraft.Failure> = []

        let name = personal.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { failures.insert(.nameMissing) }

        let minor = TypedAmount.minor(from: personal.salary, exponent: currency.exponent)
        if minor == nil { failures.insert(.salaryMissing) }

        // **Blank is allowed and a partial number is not**, which is where this departs from the design: the
        // design requires a phone because its own state always has one, and ADR-0031 made it optional at
        // registration. So "no number" is a thing an account can be in, and clearing the field says so; six to
        // fifteen digits is the design's own range for a number that is actually there.
        let digits = personal.national.filter(\.isNumber)
        let hasCountry = !personal.country.isEmpty && !personal.dialCode.isEmpty
        if !digits.isEmpty, !(6...15).contains(digits.count) || !hasCountry {
            failures.insert(.phoneInvalid)
        }

        personal.failures = failures
        guard failures.isEmpty, let minor else { return nil }

        return PersonalDetailsUpdate(
            displayName: name,
            // Exactly as authored, in the currency it was typed in — there is no storage base (§4.1 **[FIX]**).
            salary: MoneyAmount(minor: minor, currency: currency.code.rawValue),
            // **Absent rather than empty**, as registration sends it: "" and "not given" are different facts.
            phone: digits.isEmpty
                ? nil
                : PhoneNumber(country: personal.country, dialCode: personal.dialCode, national: digits)
        )
    }

    // MARK: - The display currency

    /// **Changing the display currency** — `PUT /v1/me/currency`, then a repaint of every other screen.
    ///
    /// Online-only by design (ADR-0003): every figure the app shows was converted server-side at read, so a
    /// change the server has not accepted would be a currency label over another currency's arithmetic. There is
    /// no offline write (ADR-0019), and what offline gets is the explanation in ``Refusal``.
    ///
    /// The client sends the **ISO code and nothing else**, which is the whole of its half of invariant 7 and
    /// §4.1: it converts nothing, it carries no figure across the change, and what it draws afterwards is what
    /// the response says.
    func selectCurrency(_ code: String) async {
        guard let current = state.value?.currency, code != current.rawValue else { return }

        let changed = await write(.currency, notice: .currencyChanged) {
            try await self.client.put(
                Endpoint.currency,
                body: DisplayCurrencyUpdate(currency: code),
                as: AccountScreen.self
            )
        }
        if changed { await repaint?.repaintEveryScreen() }
    }

    // MARK: - The language

    /// **Switching the language**, through the one object that owns the choice (ADR-0024), then a repaint.
    ///
    /// `LanguageManager.select(_:)` is optimistic with a revert: the app changes first so the request *carries*
    /// the new language, and any failure — offline, a 5xx, or a server that stored a different language — undoes
    /// the change and rethrows. So there is nothing for this method to undo, and what it adds is the two things
    /// the manager cannot know about: this screen's own re-read, and the other four screens'.
    ///
    /// **Re-selecting the language on screen is not always a no-op**, and the guard is the manager's rather than
    /// this one's for exactly that reason: a language that came from the *device* was never sent, so an Arabic
    /// phone whose account was registered in English has to be able to repair that by tapping "العربية".
    func selectLanguage(_ selected: AppLanguage) async {
        guard !isWriting else { return }
        isWriting = true
        defer { isWriting = false }

        refusal = nil
        do {
            try await language.select(selected)
        } catch is CancellationError {
            return
        } catch {
            refusal = Refusal(subject: .language, reason: .init(error))
            return
        }

        // The screen's own payload was formatted in the old language, so it is re-read — but **quietly**. The
        // language switch has already succeeded on the server (`language.select` above), so the reader is looking
        // at a good, correctly-worded screen. Re-reading through `load()` would blank it to a spinner and then, if
        // the follow-up GET happened to fail, to a `.failed` placeholder — reporting an error for a change that
        // worked, which is the warning triangle seen after switching language. `refreshQuietly()` swaps in the
        // newly-formatted payload when it lands and keeps the current one when it does not: the same reasoning
        // that method already documents, and the graceful shape `selectCurrency`'s `write(...)` has.
        await refreshQuietly()
        notice = .languageChanged
        await repaint?.repaintEveryScreen()
    }

    // MARK: - Changing the password

    /// The current-password step's box.
    func editCurrentPassword(_ text: String) {
        password.current = text
        password.failure = nil
    }

    /// One security answer, by its position in the payload's list.
    func editAnswer(at index: Int, _ text: String) {
        password.answers[index] = text
        password.failure = nil
    }

    func editNewPassword(_ text: String) {
        password.newPassword = text
        password.failure = nil
    }

    func editConfirmation(_ text: String) {
        password.confirmation = text
        password.failure = nil
    }

    /// How strong the new password is, for the meter. Feedback, and it gates nothing (invariant 4 is the only
    /// rule, and it is 8+).
    var passwordStrength: PasswordStrength { .of(password.newPassword) }

    /// Starts the flow at step one, with one empty answer per question.
    ///
    /// Called when the page opens, as the design's `RENDER.password` resets `pw` — arriving at the flow should
    /// not find it half-finished, and a password left in a field is a password left in memory.
    func beginPasswordChange() {
        password = PasswordDraft(answers: Array(repeating: "", count: securityQuestions.count))
    }

    /// **Continue** — checks the step on screen and moves to the next, or submits from the last.
    ///
    /// The change itself is still **one** request (``PasswordChange``) and the server still re-verifies everything,
    /// so no state is carried between steps. What changed is *when the reader finds out*: each step now asks
    /// `POST /v1/me/password/check` whether what they have typed is right, rather than letting them fill three
    /// screens and learn at the end that the first box was wrong. Observed: a wrong current password walked the
    /// whole wizard, then bounced back to step one — three steps of work for a typo.
    ///
    /// The trade-off that buys is written down on the endpoint: a check route is a password-guessing oracle behind
    /// a valid session, which is why it writes nothing and counts every miss against the recovery lockout.
    ///
    /// **A check that cannot reach the server does not block the step.** The reader keeps moving and the final
    /// submit — which is authoritative — reports the failure. A fail-fast that turned into a fail-always offline
    /// would be worse than the problem it fixes.
    func advancePasswordChange() async {
        switch password.step {
        case .currentPassword:
            guard !password.current.isEmpty else {
                password.failure = .currentPasswordMissing
                return
            }
            guard await confirmPasswordStep(sendingAnswers: false) else { return }
            password.step = .securityQuestions
        case .securityQuestions:
            guard password.answers.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
                password.failure = .answerMissing
                return
            }
            guard await confirmPasswordStep(sendingAnswers: true) else { return }
            password.step = .newPassword
        case .newPassword:
            await submitPasswordChange()
        }
    }

    /// Asks the server whether what has been typed so far is right. `true` means "carry on".
    ///
    /// Refusals are `422`, never `401` (``ErrorCode/invalidCredentials``), so a mistyped password cannot spend the
    /// refresh token and end the session — which is the whole reason the route exists on those terms.
    private func confirmPasswordStep(sendingAnswers: Bool) async -> Bool {
        guard !isWriting else { return false }
        isWriting = true
        defer { isWriting = false }

        let answers = sendingAnswers
            ? zip(securityQuestions, password.answers).map {
                SecurityAnswer(questionID: $0.id, answer: $1.trimmed)
            }
            : nil

        do {
            _ = try await client.post(
                Endpoint.passwordCheck,
                body: PasswordCheck(currentPassword: password.current, securityAnswers: answers),
                as: PasswordCheckAccepted.self
            )
            password.failure = nil
            return true
        } catch let error as APIError {
            switch error {
            case .offline:
                // Not a refusal. Let them through; the submit is authoritative.
                return true
            case .server(_, let code):
                guard let rejection = PasswordDraft.Failure(code) else { return true }
                password.failure = rejection
                password.step = rejection.step
                return false
            case .malformedResponse, .unauthenticated:
                return true
            }
        } catch {
            return true
        }
    }

    /// The way back, which the design draws on steps two and three.
    ///
    /// It keeps what was typed: stepping back to correct one answer should not empty the other.
    func retreatPasswordChange() {
        guard let previous = password.step.previous else { return }
        password.step = previous
        password.failure = nil
    }

    /// `POST /v1/me/password` — the whole change, once.
    private func submitPasswordChange() async {
        guard password.newPassword.count >= PasswordDraft.minimumLength else {
            password.failure = .newPasswordTooShort
            return
        }
        guard password.confirmation == password.newPassword else {
            password.failure = .confirmationMismatch
            return
        }
        guard securityQuestions.count == password.answers.count else { return }

        let request = PasswordChange(
            currentPassword: password.current,
            securityAnswers: zip(securityQuestions, password.answers).map { question, answer in
                // **The id, never the question's text** (§4.3 **[FIX]**, defect D12): the answer's hash is keyed
                // to the id, so a reworded or translated question keeps its answers.
                SecurityAnswer(questionID: question.id, answer: answer.trimmingCharacters(in: .whitespaces))
            },
            newPassword: password.newPassword
        )

        let changed = await write(.password, notice: .passwordChanged) {
            try await self.client.post(Endpoint.password, body: request, as: AccountScreen.self)
        }

        // The whole draft goes on success, including both passwords: there is no reason to keep either in memory
        // for a moment longer than the request took.
        if changed {
            password = PasswordDraft(answers: Array(repeating: "", count: securityQuestions.count))
        }
    }

    // MARK: - Deleting the account

    /// **`DELETE /v1/me`** — the account, soft-deleted with a 30-day grace period (ADR-0015).
    ///
    /// **App Store 5.1.1(v) requires this to be reachable in-app.** The route was implemented, tested, and called
    /// by nothing: there was no control for it anywhere in this client, which fails review rather than merely
    /// missing a feature.
    ///
    /// The server revokes every family, so the only correct end to a successful deletion is a sign-out — and that
    /// is all this does about navigation: `signOut()` flips `isSignedIn` and `RootView` swaps the shell for
    /// Landing (ADR-0026), which is the route every exit already takes.
    ///
    /// A failure reports itself as a refusal beside the control rather than replacing the screen, for the same
    /// reason a refused currency change does: the account is otherwise fine, and blanking it to say "that did not
    /// go through" is the wrong report.
    func deleteAccount() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        refusal = nil
        do {
            _ = try await client.delete(Endpoint.deleteAccount, as: AccountDeletion.self)
            await session.signOut()
        } catch is CancellationError {
            return
        } catch {
            refusal = Refusal(subject: .deleteAccount, reason: .init(error))
        }
    }

    /// The refusal for one control, or `nil` — including when the last refusal was about something else.
    func refusal(about subject: Refusal.Subject) -> Refusal.Reason? {
        guard let refusal, refusal.subject == subject else { return nil }
        return refusal.reason
    }

    func dismissNotice() { notice = nil }

    // MARK: - One write

    /// Sends a write and re-renders from whatever it answers with.
    ///
    /// **Every write returns the updated screen payload** (ADR-0020), so the profile header, the row subtitles and
    /// the salary's display string all come back computed rather than being patched here.
    private func write(
        _ kind: WriteKind,
        notice: Notice,
        _ send: @escaping () async throws -> AccountScreen
    ) async -> Bool {
        guard !isWriting else { return false }
        isWriting = true
        defer { isWriting = false }

        refusal = nil
        do {
            let screen = try await send()
            authoring = screen.personal.salaryCurrency
            state = .loaded(screen)
            self.notice = notice
            return true
        } catch is CancellationError {
            // The screen is going away. Nobody to tell, and no state to set.
            return false
        } catch {
            apply(error, kind: kind)
            return false
        }
    }

    /// **The write half of the error mapping**, and it is Expenses' rule minus the one case Account cannot have.
    ///
    /// - **Offline is `LoadState.offline`, not a field error** (ADR-0019). There is no queue and nothing to
    ///   correct; the screen says so and offers its own reload. What survives is the draft, so a retry does not
    ///   cost the user their typing.
    /// - **A refused password change is a field error**, because it is the one refusal the user can act on: a
    ///   wrong current password or a wrong answer is something to type again, and the copy belongs beside the box
    ///   rather than in a placeholder where the screen used to be.
    /// - **Everything else is a failed screen carrying its code**, exactly as a read's would be.
    ///
    /// `MONTH_CLOSED` has no arm here and cannot: nothing on this screen is addressed to a month.
    private func apply(_ error: any Error, kind: WriteKind) {
        // **A preference write reports a notice beside the picker rather than a screen that has gone.** The one
        // place in the app where an offline write does not become `LoadState.offline` — read ``Refusal``.
        if let subject = kind.refusalSubject {
            refusal = Refusal(subject: subject, reason: .init(error))
            return
        }

        guard let apiError = error as? APIError else {
            state = .failed(.unknown)
            return
        }

        // **Only the password change reads a code as a field error**, which is the correction the `WriteKind`
        // exists for: `INVALID_CREDENTIALS` arriving on a *details* write is not a wrong current password — there
        // is no password in that request — and treating it as one would put a message under a box the user is not
        // looking at while the write that actually failed reported nothing.
        if kind == .password, let rejection = PasswordDraft.Failure(apiError.errorCode) {
            password.failure = rejection
            // Back to the step the refusal is about, so the box the user has to retype is the one on screen.
            password.step = rejection.step
            if rejection == .answersRejected { password.attempts += 1 }
            return
        }

        switch apiError {
        case .offline:
            state = .offline
        case .server, .malformedResponse, .unauthenticated:
            state = .failed(apiError.errorCode ?? .unknown)
        }
    }
}

// MARK: - The values it owns

extension AccountViewModel {
    /// What a write **is**, for the two things that depend on it: whether a refusal is a field error, and whether it
    /// is a notice beside a control rather than a screen that has gone.
    ///
    /// The same correction `ExpensesViewModel.WriteKind` records, arrived at from the other side — and what lets
    /// there be **one** write helper here rather than two that differed only in their `catch`.
    fileprivate enum WriteKind {
        /// `PUT /v1/me`. Its refusals are the screen's, because there is nothing in the request the user could
        /// retype in response to a `500` — and because a form whose payload has gone has nothing to draw.
        case details

        /// `POST /v1/me/password` — **the only write whose refusal names a box** (`INVALID_CREDENTIALS`,
        /// `SECURITY_ANSWERS_INVALID`).
        case password

        /// `PUT /v1/me/currency` — a **preference**, whose refusal is a notice beside the picker (``Refusal``).
        case currency

        /// Which control a refusal belongs beside, or `nil` for a write whose failure is the screen's.
        var refusalSubject: Refusal.Subject? {
            switch self {
            case .details, .password: nil
            case .currency: .currency
            }
        }
    }

    /// The three editable personal details as they currently read.
    ///
    /// A value rather than five loose properties, so "the form is untouched" and "the form has this much in it"
    /// are things a test states about one thing — the same shape `ExpensesViewModel.EntryDraft` has.
    struct PersonalDraft: Sendable, Equatable {
        var displayName = ""
        /// As typed, in major units. Parsed once, at the boundary (``TypedAmount``) — and filled from
        /// `Money.minor`, never from `Money.display` (defect D16).
        var salary = ""
        /// ISO 3166-1 alpha-2 of the chosen dial code.
        var country = ""
        /// `+91`, with the plus.
        var dialCode = ""
        /// Digits only, as typed.
        var national = ""

        /// Every field that is wrong, not the first one: the design marks them all and says "Check the
        /// highlighted details."
        var failures: Set<Failure> = []

        /// What is wrong with the form, as values — the same shape `SignInFailure` and
        /// `ExpensesViewModel.EntryDraft.Failure` have, and for the same reason: a rule worth writing is worth
        /// asserting, and a rendered sentence cannot be asserted about.
        enum Failure: Sendable, Equatable, Hashable, CaseIterable {
            /// A display name is not an identity, and it is still not allowed to be blank — it is what the
            /// profile card and Home's greeting are drawn from.
            case nameMissing
            /// The design's "Enter an amount greater than zero", applied to a salary.
            case salaryMissing
            /// A number that is there and is not six to fifteen digits, or has no country behind it. **Blank is
            /// not a failure** — phone is optional (ADR-0031).
            case phoneInvalid
        }
    }

    /// The password flow's three steps, in order.
    ///
    /// `Int`-backed so the dots can be drawn from the position without the view counting cases — and **not
    /// `Comparable`**, which it was until review pointed out that nothing anywhere orders two steps: what the flow
    /// needs is "the one before this", and that is ``previous``.
    enum PasswordStep: Int, Sendable, Equatable, CaseIterable {
        /// The password you use now. Sent, not checked here (defect D4).
        case currentPassword = 0
        /// **Both** questions the account chose (Product Spec §3.7 **[FIX]**).
        case securityQuestions = 1
        /// The new one, twice.
        case newPassword = 2

        var previous: PasswordStep? { PasswordStep(rawValue: rawValue - 1) }
    }

    /// What has been typed into the flow, and what is wrong with it.
    ///
    /// It holds two passwords and two security answers in memory, which is why every path that finishes with it —
    /// success, and leaving the page — replaces it with an empty one.
    struct PasswordDraft: Sendable, Equatable {
        var step: PasswordStep = .currentPassword
        var current = ""
        /// One per question, in the payload's order. Positional rather than keyed, because the *order* is the
        /// server's and the pairing is made once, at submission, from `zip`.
        var answers: [String] = []
        var newPassword = ""
        var confirmation = ""
        var failure: Failure?

        /// How many times the answers have been refused. The design points at support after three
        /// (`pw.tries >= 3`), which is the only thing left that can help somebody who cannot answer their own
        /// questions.
        var attempts = 0

        /// 8+ characters everywhere (invariant 4).
        static let minimumLength = 8

        /// Whether the reader has been refused often enough to be told about support.
        var shouldOfferSupport: Bool { attempts >= 3 }

        /// What is wrong, whether the client decided it or the server did.
        ///
        /// **One enum for both**, because the screen draws them in the same place and the user cannot tell the
        /// difference: "you left this blank" and "that is not your password" are both a message under the same
        /// box. What differs is who knows — and ``init(_:)`` is where a server code becomes one of these.
        enum Failure: Sendable, Equatable, CaseIterable {
            /// Local: nothing typed.
            case currentPasswordMissing
            /// Local: one of the two answers left blank.
            case answerMissing
            /// Local: under eight characters.
            case newPasswordTooShort
            /// Local: the two new-password boxes disagree.
            case confirmationMismatch
            /// The server's `INVALID_CREDENTIALS` — the current password was wrong.
            case currentPasswordRejected
            /// The server's `SECURITY_ANSWERS_INVALID`. **It does not say which one**, and must not: telling
            /// somebody which of two guesses landed is a hint to whoever is guessing.
            case answersRejected

            /// Which step this failure belongs to — where the box the user has to correct is.
            ///
            /// Total rather than optional, because every failure is about exactly one box: a client-side one is
            /// already on that step, and a server-side one is what sends the reader back to it.
            var step: PasswordStep {
                switch self {
                case .currentPasswordMissing, .currentPasswordRejected: .currentPassword
                case .answerMissing, .answersRejected: .securityQuestions
                case .newPasswordTooShort, .confirmationMismatch: .newPassword
                }
            }

            /// A server code as a field error, or `nil` for a code that is not about a field.
            ///
            /// The one place either code is interpreted. `ViewModels` may branch on an `ErrorCode` — Expenses
            /// does, to offer re-filing — and what it may not do is turn one into a sentence; that is
            /// `ErrorCopy`'s, and neither of these two is in it (see `ErrorCode.invalidCredentials`).
            init?(_ code: ErrorCode?) {
                switch code {
                case .invalidCredentials: self = .currentPasswordRejected
                case .securityAnswersInvalid: self = .answersRejected
                default: return nil
                }
            }
        }
    }

    /// What just happened, for the toast. The words are the screen's; the choice is this object's.
    enum Notice: Sendable, Equatable, CaseIterable {
        case personalUpdated
        case currencyChanged
        case languageChanged
        case passwordChanged
    }

    /// Why one thing did not happen — **as a notice beside the control that was tried, not as a state**.
    ///
    /// It carries a **subject** as well as a reason, and that is review's correction: with the reason alone, a
    /// failed export drew its sentence over the currency picker and a failed currency change drew one under the
    /// export button. A refusal is about one control.
    ///
    /// Neither half is a `LoadState`: the screen is fine, and the taxonomy has one owner (ADR-0016).
    struct Refusal: Sendable, Equatable {
        let subject: Subject
        let reason: Reason

        /// Which control the sentence goes beside. The three things on this screen whose failure leaves the screen
        /// standing — two preferences and the deletion request.
        enum Subject: Sendable, Equatable, CaseIterable {
            case currency
            case language
            case deleteAccount
        }

        /// What to say. Two cases, because there are two things worth saying and the difference matters: a change
        /// that needs a connection is one to try again in a minute, and a change the server refused is not.
        enum Reason: Sendable, Equatable, CaseIterable {
            /// The request never reached the server. Online-only by design (ADR-0003), so this is the whole of what
            /// offline means here.
            case needsConnection
            /// The server answered, and said no.
            case refused

            /// A thrown error as a reason.
            ///
            /// Total, and **cancellation never reaches it**: a user who navigated away mid-request has not been
            /// refused anything, so every caller returns on `CancellationError` before asking this.
            init(_ error: any Error) {
                guard let apiError = error as? APIError else { self = .refused; return }
                switch apiError {
                case .offline: self = .needsConnection
                case .server, .malformedResponse, .unauthenticated: self = .refused
                }
            }
        }
    }
}
