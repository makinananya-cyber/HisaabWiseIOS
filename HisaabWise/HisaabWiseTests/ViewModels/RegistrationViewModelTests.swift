import Foundation
@testable import HisaabWise
import Testing

/// Registration: three steps in the UI, **one request at the end**.
///
/// The ticket's four named tests are here — the atomic submit carries every field, an email collision returns to
/// step 1, a date of birth under 13 blocks submission on the client, and skip is distinguishable from an explicit
/// goal — and each is asserted **against the bytes on the wire** rather than against the view model's properties.
/// That distinction is the whole point: a form that held every field correctly and dropped one on the way to
/// `URLRequest.httpBody` would pass a properties test and ship a broken registration.
@Suite("Registration")
@MainActor
struct RegistrationViewModelTests {
    // MARK: - Standing one up

    /// A form over a transport that serves the three reference lists and whatever else the test programmes.
    private static func form(
        _ transport: FixtureTransport,
        language: AppLanguage = .english
    ) async -> (viewModel: RegistrationViewModel, session: SessionCoordinator) {
        let manager = LanguageManager(selected: language)
        let client = APIClient(
            baseURL: TestBench.baseURL,
            transport: transport,
            language: manager,
            refreshTokens: InMemoryTokenStore()
        )
        let session = SessionCoordinator(
            client: client,
            keptStore: InMemoryTokenStore(),
            transientStore: InMemoryTokenStore()
        )
        let viewModel = RegistrationViewModel(
            session: session,
            content: ContentLoader(client: client, store: InMemoryContentStore()),
            language: manager,
            legal: TestBench.legal
        )
        await viewModel.loadReferenceLists()
        return (viewModel, session)
    }

    /// The three content routes, plus a `POST /v1/auth/register` and the `GET /v1/me` that follows a successful
    /// one. Built as *stubs* rather than a queue, because the three lists are fetched concurrently and a global
    /// queue would answer whichever arrived first.
    private static func stubs(register: FixtureTransport.Outcome) -> [String: FixtureTransport.Outcome] {
        [
            Endpoint.path(for: .countries): .response(status: 200, body: TestBench.payload(.referenceCountries)),
            Endpoint.path(for: .currencies): .response(status: 200, body: TestBench.payload(.referenceCurrencies)),
            Endpoint.path(for: .securityQuestions): .response(
                status: 200,
                body: TestBench.payload(.referenceSecurityQuestions)
            ),
            Endpoint.register: register,
            Endpoint.me: .response(status: 200, body: TestBench.payload(.meUnverified)),
        ]
    }

    /// A `201` in the shape registration answers with: the same token pair a login does (ADR-0023), because a new
    /// account is signed in.
    private static var accepted: FixtureTransport.Outcome {
        .response(
            status: 201,
            body: TestBench.tokenPair(access: TestBench.accessToken(), refresh: "refresh-after-registering")
        )
    }

    /// Fills steps 1 and 2 with details that pass every rule, and advances to step 3 the way a user does.
    private static func fillAndAdvance(_ viewModel: RegistrationViewModel) {
        viewModel.name = "  Neeraj Makin  "
        viewModel.email = "  neeraj@example.ae "
        viewModel.chooseCountry(code: "AE")
        viewModel.phoneDigits = "50 123 4567"
        viewModel.dateOfBirth = birthday(yearsAgo: 31)
        viewModel.password = "a-long-enough-password-1!"
        viewModel.confirmPassword = "a-long-enough-password-1!"
        viewModel.acceptedTerms = true
        viewModel.advance()

        viewModel.chooseCurrency(code: "AED")
        viewModel.salaryText = "8,000"
        viewModel.chooseFirstQuestion(id: "sq01")
        viewModel.firstAnswer = " Al Noor "
        viewModel.chooseSecondQuestion(id: "sq03")
        viewModel.secondAnswer = "Dubai"
        viewModel.advance()
    }

    private static func birthday(yearsAgo: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(byAdding: .year, value: -yearsAgo, to: Date()) ?? Date()
    }

    /// The body of the one `POST /v1/auth/register` that reached the transport, as JSON.
    private static func submitted(to transport: FixtureTransport) async throws -> [String: Any] {
        let requests = await transport.recordedRequests.filter { $0.path == Endpoint.register }
        let request = try #require(requests.first)
        #expect(requests.count == 1, "registration sent \(requests.count) requests; it is one call (#15)")
        let body = try #require(request.body)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    // MARK: - The reference lists

    /// ADR-0009 — the lists are **server content**, and the form cannot be drawn without them. The counts are the
    /// workspace's own acceptance test for the extraction.
    @Test("the three reference lists come from the server, at their full counts")
    func theReferenceListsLoad() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))

        #expect(viewModel.countries.count == 251)
        #expect(viewModel.currencies.count == 160)
        #expect(viewModel.questions.count == 14)
        #expect(viewModel.hasReferenceLists)
        #expect(viewModel.referenceFailure == nil)
    }

    /// The design's defaults, applied once the lists arrive — and **only over an empty choice**, so a user who
    /// went back a step does not find their currency reset.
    @Test("the design's defaults are applied to the empty choices and nothing else")
    func theDefaultsAreApplied() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))

        #expect(viewModel.country?.code == "IN")
        #expect(viewModel.currency?.code == "INR")

        viewModel.chooseCurrency(code: "AED")
        await viewModel.loadReferenceLists()

        #expect(viewModel.currency?.code == "AED", "a reload overwrote a choice the user had already made")
    }

    /// **Awaiting the load means the lists are there.** Two callers exist in the app — the screen's `.task` and
    /// the retry button — and a guard that returned early for the second one left it carrying on against three
    /// empty arrays. Which is exactly what it did until the running app showed a "filled" form refusing its own
    /// salary: the second caller had validated against a `nil` currency.
    @Test("a second, concurrent load joins the first rather than returning without the lists")
    func aConcurrentLoadJoinsTheFirst() async throws {
        let transport = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (viewModel, _) = await Self.form(transport)
        let before = await transport.recordedRequests.count

        // Two callers, together. Both must see the lists afterwards, and neither may double the requests.
        async let first: Void = viewModel.loadReferenceLists()
        async let second: Void = viewModel.loadReferenceLists()
        _ = await (first, second)

        #expect(viewModel.hasReferenceLists)
        #expect(viewModel.currency != nil)
        let added = await transport.recordedRequests.count - before
        #expect(added <= 3, "a joined load sent \(added) requests; three resources means at most three")
    }

    /// A form with no lists is a form with three dead controls, so the screen shows a retry instead. **Not a
    /// `LoadState`**: there is no read for the taxonomy to describe here (`StateTaxonomyTests`).
    @Test("lists that will not load leave the form undrawable, with a failure and a retry")
    func listsThatFailAreReported() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(queue: [.notConnected, .notConnected, .notConnected]))

        #expect(!viewModel.hasReferenceLists)
        #expect(viewModel.referenceFailure == .unreachable)
        // And the form's own failures are untouched: an offline list is not a field error.
        #expect(viewModel.failures.isEmpty)
    }

    // MARK: - The atomic submit

    /// **The ticket's first named test.** Every field from all three steps, in one body.
    ///
    /// Asserted against the JSON rather than the view model, and field by field rather than as a whole-object
    /// comparison: a comparison would fail as one opaque mismatch, and what a reader wants to know is *which*
    /// field went missing.
    @Test("the one submit carries every field from all three steps")
    func theSubmitCarriesEverything() async throws {
        let transport = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (viewModel, session) = await Self.form(transport, language: .arabic)
        Self.fillAndAdvance(viewModel)

        await viewModel.submit()

        let body = try await Self.submitted(to: transport)

        // Step 1 — and **trimmed**: the fixture typed leading spaces into the name and the email.
        #expect(body["name"] as? String == "Neeraj Makin")
        #expect(body["email"] as? String == "neeraj@example.ae")
        #expect(body["password"] as? String == "a-long-enough-password-1!")
        // `YYYY-MM-DD`, and the *date* rather than an age: an age computed on the client is an age that changes
        // without the server hearing about it.
        let dateOfBirth = try #require(body["dateOfBirth"] as? String)
        #expect(dateOfBirth.count == 10)
        #expect(dateOfBirth.hasPrefix("\(Calendar(identifier: .gregorian).component(.year, from: Date()) - 31)"))
        #expect(body["acceptedTerms"] as? Bool == true)

        // The phone, as **E.164** — the dial code and the digits, with the spaces the user typed stripped.
        let phone = try #require(body["phone"] as? [String: Any])
        #expect(phone["e164"] as? String == "+971501234567")
        #expect(phone["country"] as? String == "AE")
        #expect(phone["national"] as? String == "501234567")

        // Step 2 — `{amount, currency}` in minor units, never a bare number (invariant 1).
        #expect(body["displayCurrency"] as? String == "AED")
        let salary = try #require(body["salary"] as? [String: Any])
        #expect(salary["minor"] as? Int == 800_000)
        #expect(salary["currency"] as? String == "AED")

        // Two answers, keyed by the **opaque id** (§4.3 [FIX]) and trimmed.
        let answers = try #require(body["securityAnswers"] as? [[String: Any]])
        #expect(answers.count == 2)
        #expect(answers.map { $0["questionId"] as? String } == ["sq01", "sq03"])
        #expect(answers.map { $0["answer"] as? String } == ["Al Noor", "Dubai"])

        // Step 3 — the pre-filled 20%, and the fact that the user did not skip.
        let goal = try #require(body["savingsGoal"] as? [String: Any])
        #expect(goal["minor"] as? Int == 160_000)
        #expect(goal["currency"] as? String == "AED")
        #expect(body["goalWasSkipped"] as? Bool == false)

        // And the two the *client* is the only source of: invariant 6's timezone, and ADR-0024's language, so the
        // verification email is composed in the language the user registered in.
        #expect(body["timeZone"] as? String == TimeZone.current.identifier)
        #expect(body["language"] as? String == "ar")

        // A new account is signed in — which is how both Submit and Skip "land on Home": the session flips and
        // `RootView` swaps Landing for the shell (ADR-0026).
        #expect(session.isSignedIn)
    }

    /// **Nothing is persisted server-side until the submit.** The whole of the [FIX], as a request count: walking
    /// all three steps reaches the register route zero times, and there is no other write on the way.
    @Test("walking the three steps sends no write until the last button")
    func thereIsNoHalfBuiltAccount() async throws {
        let transport = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (viewModel, session) = await Self.form(transport)
        Self.fillAndAdvance(viewModel)

        #expect(viewModel.step == .three)
        #expect(!session.isSignedIn)

        let writes = await transport.recordedRequests.filter { $0.method != "GET" }
        #expect(writes.isEmpty, "a step sent a write: \(writes.map(\.path))")
    }

    /// **And no email-availability call anywhere**, which is the reason the collision arrives at the end: such an
    /// endpoint answers "does this person have an account" to anybody who asks.
    ///
    /// Asserted against the source as well as the wire — the wire only proves that *this* flow does not call one,
    /// and the failure mode is somebody adding the route later because it makes the form feel faster.
    @Test("there is no email-availability endpoint, on the wire or in the source")
    func thereIsNoAvailabilityCheck() async throws {
        let transport = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (viewModel, _) = await Self.form(transport)
        viewModel.email = "neeraj@example.ae"
        Self.fillAndAdvance(viewModel)

        let paths = await Set(transport.recordedRequests.map(\.path))
        #expect(!paths.contains { $0.contains("available") || $0.contains("exists") || $0.contains("check") })

        try SourceTree.expectAbsent(
            // The spellings such a route would actually arrive under. Not the bare word "available", which a
            // screen legitimately uses about its own content — the reference lists being unavailable is not an
            // email-availability check.
            ["/available", "availability", "emailAvailable", "email-available", "emailExists", "checkEmail"],
            from: ["Networking", "ViewModels", "Views"],
            because: "an email-availability route is an account-enumeration oracle (#15)"
        )
    }

    // MARK: - The collision

    /// **The ticket's second named test.** A `409 EMAIL_TAKEN` sends the user back to step 1 with the email field
    /// marked, from wherever they were.
    @Test("an email collision returns the user to step 1 with a field error")
    func aCollisionReturnsToStepOne() async throws {
        let refused = FixtureTransport.Outcome.response(
            status: 409,
            body: Data(#"{"error":{"code":"EMAIL_TAKEN"}}"#.utf8)
        )
        let transport = FixtureTransport(stubs: Self.stubs(register: refused))
        let (viewModel, session) = await Self.form(transport)
        Self.fillAndAdvance(viewModel)
        #expect(viewModel.step == .three)

        await viewModel.submit()

        #expect(viewModel.step == .one, "the user was left on a step where they cannot fix the problem")
        #expect(viewModel.failure(for: .email) == .emailTaken)
        #expect(!session.isSignedIn)
        // And the rest of what they typed survives: sending them back to fix one field must not cost them the
        // other two steps.
        #expect(viewModel.salaryText == "8,000")
        #expect(viewModel.secondQuestion?.id == "sq03")
    }

    /// Every other refusal stays on the screen the user is on. A collision moves them because there is somewhere
    /// to move *to*; a `500` has no field to mark.
    @Test("a refusal with no field to mark leaves the user where they are")
    func aServerFaultDoesNotMoveTheUser() async throws {
        let transport = FixtureTransport(
            stubs: Self.stubs(register: .response(status: 500, body: Data()))
        )
        let (viewModel, _) = await Self.form(transport)
        Self.fillAndAdvance(viewModel)

        await viewModel.submit()

        #expect(viewModel.step == .three)
        #expect(viewModel.formFailure == .refused(.unknown))
    }

    @Test("an offline submit is offline rather than a fault, and keeps everything typed")
    func anOfflineSubmitIsNotAFault() async throws {
        var stubs = Self.stubs(register: .notConnected)
        stubs[Endpoint.register] = .notConnected
        let transport = FixtureTransport(stubs: stubs)
        let (viewModel, session) = await Self.form(transport)
        Self.fillAndAdvance(viewModel)

        await viewModel.submit()

        #expect(viewModel.formFailure == .unreachable)
        #expect(!session.isSignedIn)
        #expect(viewModel.name == "Neeraj Makin" || viewModel.name == "  Neeraj Makin  ")
    }

    // MARK: - Thirteen

    /// **The ticket's third named test.** A date of birth under 13 is refused by the client, and **no request
    /// leaves**: a form that collects a twelve-year-old's name, email, and phone number before the server refuses
    /// them has already collected them.
    @Test("a date of birth under 13 blocks submission on the client")
    func tooYoungIsBlockedLocally() async throws {
        let transport = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (viewModel, session) = await Self.form(transport)
        Self.fillAndAdvance(viewModel)
        viewModel.dateOfBirth = Self.birthday(yearsAgo: 12)

        await viewModel.submit()

        #expect(viewModel.step == .one)
        #expect(viewModel.failure(for: .dateOfBirth) == .tooYoung(minimumAge: 13))
        #expect(!session.isSignedIn)
        let writes = await transport.recordedRequests.filter { $0.path == Endpoint.register }
        #expect(writes.isEmpty, "a 12-year-old's details reached the server to be refused there")
    }

    /// And the picker cannot offer one: the commonest mistake is unavailable rather than rejected after the fact.
    ///
    /// **The young end is exact and the old end is within a day**, which is the trade the calendar's zone makes.
    /// The zone has to be the device's — the picker's value is a local wall-clock day, and reading it in UTC moves
    /// the day (see the date-of-birth test above) — and a *120-year* span measured in a real zone crosses a
    /// historical offset change: the Gulf adopted +04:00 in 1920, so "120 years ago" comes back 119 years and 364
    /// days. Exactness matters for a birthday and not for the oldest date a picker offers, so the zone follows the
    /// input.
    @Test("the date picker's range runs from 13 years ago to about 120")
    func theDateRangeIsThirteenToOneHundredAndTwenty() {
        let now = Date()
        let range = RegistrationViewModel.dateOfBirthRange(now: now)

        #expect(RegistrationViewModel.age(on: range.upperBound, now: now) == 13)
        #expect(RegistrationViewModel.age(on: range.lowerBound, now: now) >= RegistrationViewModel.maximumAge - 1)
        #expect(RegistrationViewModel.age(on: range.lowerBound, now: now) <= RegistrationViewModel.maximumAge)
        // A birthday one day later than the newest allowed is a 12-year-old, and outside the range.
        #expect(!range.contains(range.upperBound.addingTimeInterval(60 * 60 * 24)))
    }

    /// Thirteen **today** is thirteen. An off-by-one here is a rule that turns a lawful user away on their
    /// birthday.
    @Test("somebody who turns 13 today is old enough")
    func thirteenTodayIsAllowed() async throws {
        let transport = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (viewModel, _) = await Self.form(transport)
        Self.fillAndAdvance(viewModel)
        viewModel.dateOfBirth = RegistrationViewModel.dateOfBirthRange().upperBound

        await viewModel.submit()

        #expect(viewModel.failure(for: .dateOfBirth) == nil)
        _ = try await Self.submitted(to: transport)
    }

    /// The day is formatted in **UTC**, so the day the user picked is the day the server stores. Formatting it in
    /// the device's zone would move a birthday across midnight for anybody far enough east or west.
    @Test("the date of birth is the calendar day chosen, in UTC")
    func theDateOfBirthIsAUTCDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let midnight = try! #require(calendar.date(from: DateComponents(year: 1994, month: 3, day: 7)))

        #expect(RegistrationViewModel.isoDay(midnight) == "1994-03-07")
        // Zero-padded on both halves, which is what a wire format means.
        let single = try! #require(calendar.date(from: DateComponents(year: 800, month: 1, day: 2)))
        #expect(RegistrationViewModel.isoDay(single) == "0800-01-02")
    }

    // MARK: - Skip against an explicit goal

    /// **The ticket's fourth named test.** Skip and a typed 20% are the same figure and different facts, and only
    /// `goalWasSkipped` tells them apart.
    @Test("skip and an explicit goal are distinguishable in the payload")
    func skipIsDistinguishableFromAnExplicitGoal() async throws {
        let skipped = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (skipping, skippedSession) = await Self.form(skipped)
        Self.fillAndAdvance(skipping)
        await skipping.skipGoal()

        let typed = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (typing, typedSession) = await Self.form(typed)
        Self.fillAndAdvance(typing)
        // The exact figure Skip would have sent, typed by hand.
        typing.editGoal("1600")
        await typing.submit()

        let skippedBody = try await Self.submitted(to: skipped)
        let typedBody = try await Self.submitted(to: typed)

        // Same figure…
        let skippedGoal = try #require(skippedBody["savingsGoal"] as? [String: Any])
        let typedGoal = try #require(typedBody["savingsGoal"] as? [String: Any])
        #expect(skippedGoal["minor"] as? Int == 160_000)
        #expect(typedGoal["minor"] as? Int == 160_000)

        // …different fact.
        #expect(skippedBody["goalWasSkipped"] as? Bool == true)
        #expect(typedBody["goalWasSkipped"] as? Bool == false)

        // And both land on Home.
        #expect(skippedSession.isSignedIn)
        #expect(typedSession.isSignedIn)
    }

    /// Skip works from an **emptied** box, which is the state the design points it at. Submit does not: it has
    /// nothing to send.
    @Test("skip accepts the suggestion from an empty box; submit refuses one")
    func skipWorksFromAnEmptyBox() async throws {
        let transport = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (viewModel, session) = await Self.form(transport)
        Self.fillAndAdvance(viewModel)
        viewModel.editGoal("")

        await viewModel.submit()

        #expect(viewModel.failure(for: .goal) == .goalMissing)
        #expect(!session.isSignedIn)

        await viewModel.skipGoal()

        #expect(session.isSignedIn)
        let body = try await Self.submitted(to: transport)
        #expect(body["goalWasSkipped"] as? Bool == true)
    }

    // MARK: - Step 3's arithmetic

    /// The box arrives pre-filled at 20% of the salary, as the design fills it on the way in.
    @Test("step 3 opens pre-filled at 20% of the salary")
    func stepThreeIsPreFilled() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        Self.fillAndAdvance(viewModel)

        #expect(viewModel.goalText == "1600")
        #expect(viewModel.suggestedGoalMinor == 160_000)
        // Already the suggestion, so the "use the suggested amount" button is not offered.
        #expect(!viewModel.suggestsUsingTheSuggestion)
    }

    /// The live "% of salary" feedback, and the three verdicts the hint has copy for.
    @Test("the share of salary is computed live, in whole points")
    func theShareOfSalaryIsLive() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        Self.fillAndAdvance(viewModel)

        #expect(viewModel.goalShareText == "20")
        #expect(viewModel.goalAgainstSuggestion == .orderedSame)

        viewModel.editGoal("2400")
        #expect(viewModel.goalShareText == "30")
        #expect(viewModel.goalAgainstSuggestion == .orderedDescending)
        #expect(viewModel.suggestsUsingTheSuggestion)

        viewModel.editGoal("400")
        #expect(viewModel.goalShareText == "5")
        #expect(viewModel.goalAgainstSuggestion == .orderedAscending)

        // An empty box has no share and offers no suggestion button — the design points at Skip there.
        viewModel.editGoal("")
        #expect(viewModel.goalShareText == nil)
        #expect(!viewModel.suggestsUsingTheSuggestion)
    }

    @Test("the suggestion button fills the box without submitting")
    func theSuggestionButtonOnlyFills() async throws {
        let transport = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (viewModel, session) = await Self.form(transport)
        Self.fillAndAdvance(viewModel)
        viewModel.editGoal("50")

        viewModel.useSuggestedGoal()

        #expect(viewModel.goalText == "1600")
        #expect(!session.isSignedIn)
        let writes = await transport.recordedRequests.filter { $0.path == Endpoint.register }
        #expect(writes.isEmpty)
    }

    /// A salary with fils in it survives as minor units, and the 20% of it rounds rather than truncating.
    @Test("a fractional salary is read as minor units and the suggestion rounds")
    func aFractionalSalaryIsExact() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        Self.fillAndAdvance(viewModel)
        viewModel.salaryText = "8,000.55"

        #expect(viewModel.salaryMinor == 800_055)
        // 20% of 800,055 minor units is 160,011, and the round-trip through the box keeps the fils.
        #expect(viewModel.suggestedGoalMinor == 160_011)
        #expect(viewModel.suggestedGoalText == "1600.11")
    }

    // MARK: - Step 1's rules

    @Test("every step 1 rule is enforced, and each marks its own field")
    func stepOneValidates() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))

        viewModel.advance()

        #expect(viewModel.step == .one, "an empty step 1 advanced")
        #expect(viewModel.failure(for: .name) == .nameMissing)
        #expect(viewModel.failure(for: .email) == .emailInvalid)
        #expect(viewModel.failure(for: .dateOfBirth) == .dateOfBirthMissing)
        #expect(viewModel.failure(for: .password) == .passwordTooShort)
        #expect(viewModel.failure(for: .terms) == .termsNotAccepted)
        // The phone is **optional at launch**, so an empty one is not a failure.
        #expect(viewModel.failure(for: .phone) == nil)
    }

    /// Invariant 4 — **8+ characters everywhere**, where the design's sign-in accepted six.
    @Test("the password floor is eight characters")
    func thePasswordFloorIsEight() {
        #expect(RegistrationViewModel.minimumPasswordLength == 8)
        #expect(SignInViewModel.minimumPasswordLength == RegistrationViewModel.minimumPasswordLength)
    }

    @Test("a confirmation that does not match marks the confirmation field, not the password")
    func mismatchedConfirmationMarksItsOwnField() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        viewModel.password = "a-long-enough-password"
        viewModel.confirmPassword = "a-long-enough-passwore"

        viewModel.advance()

        #expect(viewModel.failure(for: .confirmPassword) == .passwordsDoNotMatch)
        #expect(viewModel.failure(for: .password) == nil)
    }

    /// A number that is given has to be one; a number that is not given is fine. Both halves matter — a rule that
    /// only checked the given case would let `12` through, and one that required a number would contradict §3.3.
    @Test("a phone number is optional, and a given one is 6 to 15 digits")
    func thePhoneIsOptionalButValidatedWhenGiven() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        #expect(RegistrationViewModel.phoneDigitRange == 6...15)

        viewModel.phoneDigits = "12345"
        viewModel.advance()
        #expect(viewModel.failure(for: .phone) != nil)

        viewModel.phoneDigits = "1234567890123456"
        viewModel.advance()
        #expect(viewModel.failure(for: .phone) != nil)

        viewModel.phoneDigits = "501234567"
        viewModel.advance()
        #expect(viewModel.failure(for: .phone) == nil)
    }

    /// A form with no phone number sends **no phone key at all** rather than an empty one — absent is what
    /// "optional" means on the wire.
    @Test("a blank phone number is absent from the body rather than empty")
    func aBlankPhoneIsAbsent() async throws {
        let transport = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (viewModel, _) = await Self.form(transport)
        Self.fillAndAdvance(viewModel)
        viewModel.phoneDigits = ""

        await viewModel.submit()

        let body = try await Self.submitted(to: transport)
        #expect(body["phone"] == nil)
    }

    /// The design's own regex, and it is **deliberately loose**: it refuses what is obviously not an address and
    /// leaves the rest to the server, because every stricter one is wrong about somebody's real email.
    @Test("the email check refuses the obvious and accepts the unusual", arguments: [
        (email: "neeraj@example.ae", valid: true),
        (email: "n+tag@sub.example.co.uk", valid: true),
        (email: "no-at-sign.example.com", valid: false),
        (email: "two@@example.com", valid: false),
        (email: "trailing@example.", valid: false),
        (email: "space in@example.com", valid: false),
        (email: "short@tld.c", valid: false),
    ])
    func theEmailCheckIsLoose(_ testCase: (email: String, valid: Bool)) async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        viewModel.email = testCase.email

        viewModel.advance()

        #expect((viewModel.failure(for: .email) == nil) == testCase.valid, "\(testCase.email)")
    }

    /// The design's own formula, transcribed: one point for eight characters, another for twelve, another for
    /// mixed case, another for a digit **and** a symbol.
    @Test("the strength meter scores the design's four levels", arguments: [
        (password: "", strength: PasswordStrength.none),
        (password: "abc", strength: .weak),
        (password: "abcdefgh", strength: .weak),
        (password: "abcdefghijkl", strength: .fair),
        (password: "abcdefghIJKL", strength: .good),
        (password: "abcdefghIJK1!", strength: .strong),
        // Long, mixed, and with a digit but no symbol: three points, not four.
        (password: "abcdefghIJKL1", strength: .good),
    ])
    func theStrengthMeterScores(_ testCase: (password: String, strength: PasswordStrength)) async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        viewModel.password = testCase.password

        #expect(viewModel.passwordStrength == testCase.strength, "\(testCase.password)")
    }

    /// It gates nothing. A "weak" password of eight characters is accepted, because 8+ is the only rule
    /// (invariant 4) and the meter is feedback.
    @Test("the strength meter refuses nothing")
    func theStrengthMeterIsAdvisory() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        Self.fillAndAdvance(viewModel)
        viewModel.password = "aaaaaaaa"
        viewModel.confirmPassword = "aaaaaaaa"

        #expect(viewModel.passwordStrength == .weak)
        #expect(viewModel.validate(.one, goalMinor: viewModel.goalMinor).isEmpty)
    }

    // MARK: - Step 2's rules

    @Test("every step 2 rule is enforced, and each marks its own field")
    func stepTwoValidates() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        Self.fillAndAdvance(viewModel)
        viewModel.salaryText = ""
        viewModel.firstQuestion = nil
        viewModel.secondQuestion = nil

        let failures = viewModel.validate(.two, goalMinor: nil)

        #expect(failures.contains(.salaryMissing))
        #expect(failures.contains(.firstQuestionMissing))
        #expect(failures.contains(.secondQuestionMissing))
    }

    /// A chosen question with no answer is its own failure, drawn against the question's own field — the design
    /// puts both messages in the same `.msg`.
    @Test("a question chosen and left unanswered is refused")
    func anUnansweredQuestionIsRefused() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        Self.fillAndAdvance(viewModel)
        viewModel.firstAnswer = "   "
        viewModel.secondAnswer = ""

        let failures = viewModel.validate(.two, goalMinor: nil)

        #expect(failures.contains(.firstAnswerMissing))
        #expect(failures.contains(.secondAnswerMissing))
    }

    /// **Two of fourteen, and they must differ.** The picker's list makes it unbreakable; the validation covers
    /// the two slots being filled in either order.
    @Test("the two questions must differ, in the picker and in the validation")
    func theTwoQuestionsMustDiffer() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        Self.fillAndAdvance(viewModel)

        // The list offered for slot 1 omits slot 2's question, and vice versa.
        let firstList = viewModel.questions(excluding: viewModel.secondQuestion)
        #expect(firstList.count == 13)
        #expect(!firstList.contains { $0.id == "sq03" })
        #expect(viewModel.questions(excluding: nil).count == 14)

        viewModel.chooseSecondQuestion(id: "sq01")
        #expect(viewModel.validate(.two, goalMinor: nil).contains(.secondQuestionRepeated))
    }

    /// §4.3 **[FIX]** — the identity is the opaque id, and the English text never crosses to the server. A
    /// question stored by its wording cannot be reworded, translated, or compared across languages.
    @Test("a question's identity is its id, and its text is never sent")
    func questionIdentityIsTheID() async throws {
        let transport = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (viewModel, _) = await Self.form(transport)
        Self.fillAndAdvance(viewModel)
        let text = try #require(viewModel.firstQuestion?.text)
        #expect(!text.isEmpty)

        await viewModel.submit()

        let requests = await transport.recordedRequests.filter { $0.path == Endpoint.register }
        let body = try #require(requests.first?.body)
        let json = try #require(String(data: body, encoding: .utf8))

        #expect(json.contains("sq01"))
        #expect(!json.contains(text), "the question's English wording went to the server instead of its id")
        // And nothing named `question` carries prose: the key is `questionId`.
        #expect(!json.contains("\"question\":"))
    }

    /// Invariant 5 — a raw security answer is sent once and **nothing on the device can store one**. Asserted as
    /// a source scan, because the failure mode is a future convenience: an answer kept in `UserDefaults` "so the
    /// user does not have to retype it".
    @Test("nothing in the persistence layer can hold a security answer")
    func answersAreNeverPersisted() throws {
        try SourceTree.expectAbsent(
            ["SecurityAnswer", "securityAnswer", "firstAnswer", "secondAnswer"],
            from: ["Persistence", "Networking"],
            because: "a raw security answer is sent once and never stored (invariant 5)"
        )
    }

    // MARK: - What the review found

    /// **A comma may be a decimal separator, and reading it as grouping is a 100× error.**
    ///
    /// `.decimalPad` offers the device region's separator and no other, so on a German or Brazilian phone there is
    /// no `.` key at all. The last separator decides, by what follows it: one or two digits separates a fraction,
    /// three or more groups. Every "% of pay" in the app is computed against this figure (invariant 2).
    @Test("a typed figure is read the same whichever separator the region offers", arguments: [
        (typed: "8000", minor: 800_000),
        (typed: "8,000", minor: 800_000),
        (typed: "8.000", minor: 800_000),
        (typed: "8000.50", minor: 800_050),
        (typed: "8000,50", minor: 800_050),
        (typed: "1,234,567", minor: 123_456_700),
        (typed: "1,5", minor: 150),
        (typed: "8000.5", minor: 800_050),
        // Any digit script: `Character.isNumber` accepts these and `Double` does not, so an Arabic keyboard's
        // digits used to be refused as "not a figure" (ADR-0011 ships Latin digits; it does not stop a user
        // typing others).
        (typed: "٨٠٠٠", minor: 800_000),
        (typed: "", minor: 0),
        (typed: "abc", minor: 0),
        (typed: "0", minor: 0),
    ])
    func aFigureIsReadWhicheverSeparatorIsUsed(_ testCase: (typed: String, minor: Int)) async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        viewModel.salaryText = testCase.typed

        #expect(viewModel.salaryMinor == (testCase.minor == 0 ? nil : testCase.minor), "\(testCase.typed)")
    }

    /// **The day the user picked is the day that is sent.** A `DatePicker` yields the instant a local wall-clock
    /// day began, so reading its components in UTC moves the day for anybody whose local time is inside the UTC
    /// offset — in `Asia/Dubai`, every user registering before 04:00.
    @Test("the date of birth is the local calendar day the picker offered")
    func theDateOfBirthIsTheLocalDay() async throws {
        let transport = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (viewModel, _) = await Self.form(transport)
        Self.fillAndAdvance(viewModel)

        // Built the way the picker builds it: a wall-clock day in the **device's** calendar, at a time of day
        // early enough to fall on the previous day in UTC for a positive offset.
        let calendar = Calendar(identifier: .gregorian)
        let chosen = try #require(
            calendar.date(from: DateComponents(year: 1994, month: 3, day: 12, hour: 1, minute: 30))
        )
        viewModel.dateOfBirth = chosen

        await viewModel.submit()

        let body = try await Self.submitted(to: transport)
        #expect(body["dateOfBirth"] as? String == "1994-03-12")
        // And the same day whatever the hour, which is the property the zone choice is really about.
        for hour in [0, 1, 12, 23] {
            let atHour = try #require(
                calendar.date(from: DateComponents(year: 1994, month: 3, day: 12, hour: hour, minute: 30))
            )
            #expect(RegistrationViewModel.isoDay(atHour) == "1994-03-12", "hour \(hour)")
        }
    }

    /// **A corrected salary corrects the goal.** The pre-fill re-derives on every entry to step 3 while the box
    /// still holds the suggestion — guarding it on "the box is empty" left `1600` beside a statement card reading
    /// `4000`, and submitted it as an explicit choice.
    @Test("going back and changing the salary re-derives the pre-filled goal")
    func aCorrectedSalaryCorrectsTheGoal() async throws {
        let transport = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (viewModel, _) = await Self.form(transport)
        Self.fillAndAdvance(viewModel)
        #expect(viewModel.goalText == "1600")

        viewModel.goBack()
        viewModel.salaryText = "20000"
        viewModel.advance()

        #expect(viewModel.step == .three)
        #expect(viewModel.goalText == "4000", "the goal is still 20% of a salary that no longer exists")
        #expect(viewModel.suggestedGoalText == "4000")
    }

    /// And a figure the **user** typed is left alone, which is the other half of the same rule.
    @Test("a goal the user typed survives a trip back to step 2")
    func aTypedGoalIsNotOverwritten() async throws {
        let transport = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (viewModel, _) = await Self.form(transport)
        Self.fillAndAdvance(viewModel)
        viewModel.editGoal("2500")

        viewModel.goBack()
        viewModel.salaryText = "20000"
        viewModel.advance()

        #expect(viewModel.goalText == "2500")
        await viewModel.submit()
        let body = try await Self.submitted(to: transport)
        #expect(body["goalWasSkipped"] as? Bool == false)
    }

    /// **An unanswered question marks the answer box, not the question.** They were attached to the question's own
    /// field, so the picker reddened and the empty box did not.
    @Test("an empty answer marks the answer field")
    func anEmptyAnswerMarksTheAnswerField() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        Self.fillAndAdvance(viewModel)
        viewModel.firstAnswer = ""
        viewModel.secondAnswer = ""
        // Back to step 2 and forward again, which is how a user reaches this: `advance()` is the only thing that
        // records failures.
        viewModel.goBack()
        viewModel.advance()

        #expect(viewModel.failure(for: .firstAnswer) == .firstAnswerMissing)
        #expect(viewModel.failure(for: .secondAnswer) == .secondAnswerMissing)
        #expect(viewModel.failure(for: .firstQuestion) == nil)
        #expect(viewModel.failure(for: .secondQuestion) == nil)
    }

    /// **Clearing a failure clears the right one.** Typing an answer used to clear "choose a question", leaving a
    /// clean-looking form with no question chosen that the next submit refuses again.
    @Test("typing an answer does not clear the question's own failure")
    func typingAnAnswerLeavesTheQuestionFailure() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        Self.fillAndAdvance(viewModel)
        viewModel.firstQuestion = nil
        viewModel.goBack()
        viewModel.advance()
        #expect(viewModel.failure(for: .firstQuestion) == .firstQuestionMissing)

        viewModel.clearFailure(for: .firstAnswer)

        #expect(viewModel.failure(for: .firstQuestion) == .firstQuestionMissing)
    }

    /// **"Those do not match" is about both boxes**, so correcting either one clears it. Only the confirm field
    /// did, which left a stale error under a box that was now correct.
    @Test("correcting either password box clears the mismatch")
    func correctingEitherBoxClearsTheMismatch() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        #expect(RegistrationFailure.passwordsDoNotMatch.field == .confirmPassword)

        // Reached the way a user reaches it, then corrected in the box the screen's password binding writes to.
        viewModel.password = "abcdefgh1"
        viewModel.confirmPassword = "abcdefgh"
        viewModel.advance()
        #expect(viewModel.failure(for: .confirmPassword) == .passwordsDoNotMatch)

        // What `RegistrationDetailsStep`'s password binding does: clears its own field *and* the confirmation's.
        viewModel.password = "abcdefgh"
        viewModel.clearFailure(for: .password)
        viewModel.clearFailure(for: .confirmPassword)

        #expect(viewModel.failure(for: .confirmPassword) == nil)
    }

    /// **"Nothing has been asked for" is not "the ask failed".** The screen's `.task` runs after the first body
    /// evaluation, so a fresh form has three empty lists and no failure — which was drawing the failure state.
    @Test("a form that has not asked for its lists yet reports no failure")
    func anUnaskedFormHasNoFailure() async throws {
        let manager = LanguageManager(selected: .english)
        let client = APIClient(
            baseURL: TestBench.baseURL,
            transport: FixtureTransport(),
            language: manager,
            refreshTokens: InMemoryTokenStore()
        )
        let viewModel = RegistrationViewModel(
            session: SessionCoordinator(
                client: client,
                keptStore: InMemoryTokenStore(),
                transientStore: InMemoryTokenStore()
            ),
            content: ContentLoader(client: client, store: InMemoryContentStore()),
            language: manager,
            legal: TestBench.legal
        )

        #expect(!viewModel.hasReferenceLists)
        #expect(!viewModel.hasAskedForReferenceLists)
        #expect(viewModel.referenceFailure == nil, "an unasked form reports a failure it has not had")

        await viewModel.loadReferenceLists()

        #expect(viewModel.hasAskedForReferenceLists)
        #expect(viewModel.referenceFailure != nil)
    }

    /// **E.164 has no trunk prefix in it.** A UAE resident writes their number `0501234567`; concatenating that
    /// onto `+971` produced a thirteen-digit string inside the accepted range that is not a dialable number.
    @Test("a number typed with its trunk prefix still produces a valid E.164")
    func theTrunkPrefixIsStripped() async throws {
        let transport = FixtureTransport(stubs: Self.stubs(register: Self.accepted))
        let (viewModel, _) = await Self.form(transport)
        Self.fillAndAdvance(viewModel)
        viewModel.phoneDigits = "050 123 4567"

        #expect(viewModel.phoneSignificantDigits == "501234567")
        #expect(viewModel.validate(.one, goalMinor: nil).isEmpty)

        await viewModel.submit()

        let body = try await Self.submitted(to: transport)
        let phone = try #require(body["phone"] as? [String: Any])
        #expect(phone["e164"] as? String == "+971501234567")
        #expect(phone["national"] as? String == "501234567")
    }

    /// And the length is counted on the digits that will be **sent**: `0012345` is seven typed digits and five
    /// significant ones, which is under the floor.
    @Test("the digit count is checked against the significant number")
    func theDigitCountIgnoresTheTrunkPrefix() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        viewModel.phoneDigits = "0012345"

        viewModel.advance()

        #expect(viewModel.failure(for: .phone) != nil)
    }

    // MARK: - Moving between steps

    /// `advance()` is the only way forward, so a step cannot be skipped past — and `goBack()` clears the failures
    /// on the step being left, so returning to it does not arrive pre-marked.
    @Test("the step advances only through validation, and back clears what was marked")
    func theStepsMoveOneAtATime() async throws {
        let (viewModel, _) = await Self.form(FixtureTransport(stubs: Self.stubs(register: Self.accepted)))
        #expect(viewModel.step == .one)

        viewModel.advance()
        #expect(viewModel.step == .one)

        Self.fillAndAdvance(viewModel)
        #expect(viewModel.step == .three)

        viewModel.goBack()
        #expect(viewModel.step == .two)
        #expect(viewModel.failures.isEmpty)

        viewModel.goBack()
        #expect(viewModel.step == .one)
        // And there is nowhere further back: the way out of step 1 is the navigation stack's own back.
        viewModel.goBack()
        #expect(viewModel.step == .one)
    }
}
