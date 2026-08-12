import Foundation
@testable import HisaabWise
import Testing

/// Account reads **one endpoint**, writes through four, downloads one file, and derives nothing from any of them
/// (ADR-0020, ADR-0038).
///
/// The four claims the ticket asks for are each a section below: **email is not editable**, a **currency change
/// repaints and does not mutate stored amounts**, a **salary survives a round trip to the minor unit exactly**
/// (defect D16), and the **password change is one submission whose refusal names the step**.
///
/// Three of them are asserted against the **bytes on the wire** rather than against the values that went in. The
/// difference matters: an `Encodable` that stopped encoding a field would still compile, and a client that
/// converted a figure before sending it would still produce a `MoneyAmount`. What the server receives is the only
/// thing either claim is actually about.
///
/// **The `LoadState` mapping for a read is not asserted here.** It lives in `BaseViewModel.load()` and is asserted
/// in `BaseViewModelTests` — one owner, one suite. What *is* asserted here is the mapping for a **write**, because
/// that is this view model's own (`StateTaxonomyTests` names it).
@Suite("AccountViewModel")
@MainActor
struct AccountViewModelTests {
    // MARK: - Scaffolding

    private static func makeViewModel(
        _ transport: FixtureTransport,
        language: LanguageManager = LanguageManager(selected: .english)
    ) -> AccountViewModel {
        let client = TestBench.connect(language, to: transport)
        return AccountViewModel(
            client: client,
            content: ContentLoader(client: client, store: InMemoryContentStore()),
            language: language
        )
    }

    /// The screen, the two reference lists, the export, and **every write answering with the screen again**
    /// (ADR-0020).
    ///
    /// `Endpoint.me` is stubbed explicitly rather than claimed by the fixture, because `GET /v1/me` and
    /// `PUT /v1/me` are one path with two verbs and only one fixture may claim a path — the identity read holds it
    /// (`Fixture.endpoints`).
    private static func stubs(
        _ screen: Fixture = .accountINR
    ) throws -> [String: FixtureTransport.Outcome] {
        [
            Endpoint.screenAccount: try .ok(screen),
            Endpoint.me: try .ok(screen),
            Endpoint.currency: try .ok(.accountAED),
            Endpoint.password: try .ok(screen),
            Endpoint.export: try .ok(.meExport),
            Endpoint.language: try .ok(.languageArabic),
            Endpoint.path(for: .currencies): try .ok(.referenceCurrencies),
            Endpoint.path(for: .countries): try .ok(.referenceCountries),
        ]
    }

    private static func loaded(
        _ transport: FixtureTransport,
        language: LanguageManager = LanguageManager(selected: .english)
    ) async throws -> (AccountViewModel, AccountScreen) {
        let viewModel = makeViewModel(transport, language: language)
        try await viewModel.load()
        return (viewModel, try #require(viewModel.state.value))
    }

    /// The body of the last request to `path`, as the JSON object the server would parse.
    ///
    /// **The point of every assertion that uses it**: a claim about what the client sends is a claim about bytes,
    /// and a claim about what it does *not* send can only be made about bytes.
    private static func body(
        _ transport: FixtureTransport,
        at path: String,
        method: String
    ) async throws -> [String: Any] {
        let request = try #require(
            await transport.recordedRequests.last { $0.path == path && $0.method == method },
            "no \(method) reached \(path)"
        )
        let data = try #require(request.body, "the \(method) to \(path) carried no body")
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// A copy of the standing payload with one salary substituted, as `[String: Any]`.
    ///
    /// Patched rather than kept as a fourth fixture, because what the D16 tests need is a figure whose *display*
    /// string has been rounded away from its minor units — and a fixture carrying one would be a fixture claiming
    /// the server rounds wrongly. The rounding is real and correct (§4.1, magnitude-aware, display only); the
    /// defect is a client that reads the rounded string back.
    private static func withSalary(minor: Int, display: String) throws -> Data {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.accountINR)) as? [String: Any]
        )
        var personal = try #require(payload["personal"] as? [String: Any])
        var salary = try #require(personal["salary"] as? [String: Any])
        salary["minor"] = minor
        salary["display"] = display
        personal["salary"] = salary
        payload["personal"] = personal
        return try JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - One read

    @Test("the screen is one request, and nothing else is fetched to draw it")
    func oneRequest() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (_, screen) = try await Self.loaded(transport)

        #expect(await transport.recordedRequests.count == 1)
        #expect(await transport.requestCount(for: Endpoint.screenAccount) == 1)
        #expect(screen.rows.count == AccountScreen.Section.allCases.count)
    }

    /// The four rows arrive **in the payload's order** (ADR-0020), not sorted here.
    @Test("the rows are drawn in the order the payload lists them")
    func theRowsKeepTheServersOrder() async throws {
        let (_, screen) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        #expect(screen.rows.map(\.section) == [.personal, .language, .currency, .password])
    }

    /// A signed-in user always has an account, so there is no arrangement in which this screen is `.empty`.
    @Test("a loaded account is never the empty state")
    func neverEmpty() async throws {
        let (viewModel, screen) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        #expect(!viewModel.isEmpty(screen))
    }

    /// **The row values the client may not work out.** The password row's subtitle is a date label computed in the
    /// user's stored timezone (invariant 6) and its value is the client's mask — the server has no password to send.
    @Test("the password row reads its subtitle from the payload and masks its value")
    func thePasswordRowIsMaskedAndDated() async throws {
        let (_, screen) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))
        let row = try #require(screen.row(.password))

        #expect(row.hint == "Changed 3 months ago")
        // **Nothing on the wire**, which is the assertion that matters: a payload carrying `••••••••` would be a
        // server sending a stand-in for a password.
        #expect(row.value == nil)
        #expect(row.section.masksValue)
        #expect(AccountScreen.Section.allCases.count { $0.masksValue } == 1)
    }

    /// An unrecognised section fails the decode rather than arriving as a row that opens nothing — the rule
    /// `ExpensesScreen.Kind` follows, for the same reason: the section decides which page opens.
    @Test("a section this build does not recognise fails the screen")
    func anUnknownSectionFailsTheScreen() async throws {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.accountINR)) as? [String: Any]
        )
        var rows = try #require(payload["rows"] as? [[String: Any]])
        rows[0]["section"] = "biometrics"
        payload["rows"] = rows

        let viewModel = Self.makeViewModel(
            FixtureTransport(stubs: [
                Endpoint.screenAccount: .response(
                    status: 200,
                    body: try JSONSerialization.data(withJSONObject: payload)
                ),
            ])
        )
        try await viewModel.load()

        #expect(viewModel.state.value == nil)
        #expect(viewModel.state.isFailed)
    }

    // MARK: - Email is not editable

    /// **The criterion, as an absence on the wire.** Email is the identity (invariant 4): it is drawn locked, it
    /// has no field in edit mode, and `PUT /v1/me` cannot carry it.
    ///
    /// Asserted against the bytes rather than against `PersonalDetailsUpdate`, because a type that stopped
    /// encoding a field would still compile — and because "the client cannot change the email" is a claim about
    /// what the server receives.
    @Test("a personal-details write carries no email at all")
    func theWriteCarriesNoEmail() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, screen) = try await Self.loaded(transport)

        viewModel.beginEditingPersonal()
        viewModel.editDisplayName("Neeraj M")
        await viewModel.savePersonalDetails()

        let body = try await Self.body(transport, at: Endpoint.me, method: "PUT")
        #expect(body["email"] == nil, "the personal write carries an email — it is the identity (invariant 4)")
        #expect(Set(body.keys) == ["displayName", "salary", "phone"])
        // And the address on screen is the one the server sent, before and after.
        #expect(screen.personal.email == viewModel.personalDetails?.email)
    }

    /// The draft the edit form fills has **no email field to type into**, which is the same rule one layer up.
    @Test("edit mode fills a draft with no email in it")
    func theDraftHasNoEmail() async throws {
        let (viewModel, screen) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        viewModel.beginEditingPersonal()

        #expect(viewModel.isEditingPersonal)
        #expect(viewModel.personal.displayName == screen.personal.displayName)
        #expect(viewModel.personal.national == screen.personal.phone?.national)
        // The draft's whole surface, so a fifth editable field is a change somebody makes on purpose.
        #expect(
            viewModel.personal == AccountViewModel.PersonalDraft(
                displayName: screen.personal.displayName,
                salary: TypedAmount.major(
                    screen.personal.salary.minor,
                    exponent: screen.personal.salary.exponent
                ),
                country: screen.personal.phone?.country ?? "",
                dialCode: screen.personal.phone?.dialCode ?? "",
                national: screen.personal.phone?.national ?? ""
            )
        )
    }

    // MARK: - The salary round trip (defect D16)

    /// **Defect D16, as an exact identity.** A figure read out of `Money.minor` and typed back in comes back the
    /// same integer, at every exponent in circulation.
    @Test(
        "a salary survives a round trip to the minor unit exactly",
        arguments: [
            (650_000_0, 2), (651_234_5, 2), (1, 2), (99, 2),
            (1_234_567, 3), (8_000, 0), (0 + 7, 0),
        ]
    )
    func theRoundTripIsExact(_ figure: (minor: Int, exponent: Int)) throws {
        let typed = TypedAmount.major(figure.minor, exponent: figure.exponent)

        #expect(TypedAmount.minor(from: typed, exponent: figure.exponent) == figure.minor)
    }

    /// And the same thing through the view model: what the write sends is the payload's own `minor`, untouched.
    @Test("saving without editing the salary sends the payload's figure back unchanged")
    func theSalaryIsNotQuantisedByASave() async throws {
        // A figure whose **display string has been rounded** — `₹65,123.45` reads as `₹65,120` under §4.1's
        // magnitude-aware rounding. That rounding is correct; reading it *back* is the defect.
        let transport = FixtureTransport(stubs: [
            Endpoint.screenAccount: .response(status: 200, body: try Self.withSalary(
                minor: 6_512_345,
                display: "₹65,120"
            )),
            Endpoint.me: try .ok(.accountINR),
        ])
        let (viewModel, screen) = try await Self.loaded(transport)
        #expect(screen.personal.salary.minor == 6_512_345)

        viewModel.beginEditingPersonal()
        await viewModel.savePersonalDetails()

        let body = try await Self.body(transport, at: Endpoint.me, method: "PUT")
        let salary = try #require(body["salary"] as? [String: Any])
        #expect(salary["minor"] as? Int == 6_512_345, "the salary was quantised on its way out (defect D16)")
        #expect(salary["currency"] as? String == "INR")

        // **And the display string would not have survived**, which is what makes the assertion above about
        // something. If the two agreed, this test would pass against the defect.
        #expect(TypedAmount.minor(from: "65,120", exponent: 2) != 6_512_345)
    }

    /// A figure the user genuinely retyped is sent as they typed it — in the currency it was **authored** in, with
    /// no conversion (§4.1 **[FIX]**: money is stored as authored and there is no storage base).
    @Test("an edited salary is sent as typed, in the authoring currency")
    func anEditedSalaryIsSentAsTyped() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.beginEditingPersonal()
        viewModel.editSalary("70000.55")
        await viewModel.savePersonalDetails()

        let salary = try #require(
            try await Self.body(transport, at: Endpoint.me, method: "PUT")["salary"] as? [String: Any]
        )
        #expect(salary["minor"] as? Int == 7_000_055)
        #expect(salary["currency"] as? String == "INR")
    }

    @Test("a blank name or a zero salary is refused locally and sends nothing")
    func localValidationRefusesRatherThanSending() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.beginEditingPersonal()
        viewModel.editDisplayName("   ")
        viewModel.editSalary("0")
        await viewModel.savePersonalDetails()

        // **Both**, not the first: the design marks every bad field and says "Check the highlighted details."
        #expect(viewModel.personal.failures == [.nameMissing, .salaryMissing])
        #expect(await transport.requestCount(for: Endpoint.me) == 0)
        #expect(viewModel.isEditingPersonal, "a refused save left edit mode, losing the user's typing")
    }

    /// Phone is optional at registration (ADR-0031), so **blank is a real state** and a partial number is not.
    @Test("a blank phone number is sent as absent and a partial one is refused")
    func aBlankPhoneIsAbsentAndAPartialOneIsRefused() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.beginEditingPersonal()
        viewModel.editPhoneDigits("987")
        await viewModel.savePersonalDetails()
        #expect(viewModel.personal.failures == [.phoneInvalid])
        #expect(await transport.requestCount(for: Endpoint.me) == 0)

        viewModel.editPhoneDigits("")
        await viewModel.savePersonalDetails()

        let body = try await Self.body(transport, at: Endpoint.me, method: "PUT")
        // **Absent rather than empty**: "" and "not given" are different facts, and only absence says the second.
        #expect(body["phone"] == nil)
    }

    /// The digits are the only thing kept, as the design's own `replace(/[^0-9]/g, '')` does.
    @Test("everything that is not a digit is stripped as the number is typed")
    func nonDigitsAreStripped() async throws {
        let (viewModel, _) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        viewModel.beginEditingPersonal()
        viewModel.editPhoneDigits("+91 (98) 765-43210")

        #expect(viewModel.personal.national == "919876543210")
    }

    // MARK: - A currency change repaints and mutates nothing

    /// **The criterion, in two halves.** The client sends the ISO code and *no monetary value at all*, and what it
    /// shows afterwards is the response — so nothing it holds was converted (§4.1, ADR-0003).
    @Test("a currency change sends only the code, and carries no figure across")
    func aCurrencyChangeSendsOnlyTheCode() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, before) = try await Self.loaded(transport)

        await viewModel.selectCurrency("AED")

        let body = try await Self.body(transport, at: Endpoint.currency, method: "PUT")
        #expect(Set(body.keys) == ["currency"], "a currency change carries something other than the code")
        #expect(body["currency"] as? String == "AED")

        let after = try #require(viewModel.state.value)
        // **The figures came from the response, not from a conversion here.** Byte-identical to the dirham
        // payload — which is the whole of the client's half of invariant 7.
        let dirhams = try Fixture.accountAED.decode(AccountScreen.self)
        let salaryMatchesTheResponse = after.personal.salary == dirhams.personal.salary
        #expect(salaryMatchesTheResponse)
        #expect(after.currency.rawValue == "AED")
        #expect(after.personal.salary.minor != before.personal.salary.minor)
        // And nothing that is not money moved.
        #expect(after.profile.displayName == before.profile.displayName)
        #expect(after.password.questions == before.password.questions)
        #expect(after.rows.map(\.section) == before.rows.map(\.section))
    }

    /// **The repaint, through the one object that can do it.** `TabViewModels` is the app's `ScreenRepaint` and the
    /// only conformance there is (ADR-0013 — no doubles), so this stands up all five screens and counts requests.
    @Test("a currency change re-reads every other screen")
    func aCurrencyChangeRepaintsTheApp() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs().merging([
            Endpoint.screenHome: try .ok(.homeINR),
            Endpoint.screenExpenses: try .ok(.expensesINR),
            Endpoint.screenLearn: try .ok(.learnInProgress),
            Endpoint.screenReports: try .ok(.reportsINR),
            Endpoint.curriculum: try .ok(.curriculum),
        ]) { _, stub in stub })
        let models = TestBench.tabViewModels(over: transport)

        try await models.account.load()
        try await models.home.load()
        #expect(await transport.requestCount(for: Endpoint.screenHome) == 1)

        await models.account.selectCurrency("AED")

        // Each of the other four read again — and Account did **not**, because the write it made answered with its
        // own screen (ADR-0020).
        #expect(await transport.requestCount(for: Endpoint.screenHome) == 2)
        #expect(await transport.requestCount(for: Endpoint.screenExpenses) == 1)
        #expect(await transport.requestCount(for: Endpoint.screenLearn) == 1)
        #expect(await transport.requestCount(for: Endpoint.screenReports) == 1)
        #expect(await transport.requestCount(for: Endpoint.screenAccount) == 1)
    }

    /// Re-picking the currency already in force sends nothing: a `PUT` that replaces a value with itself is a
    /// round trip and an app-wide repaint for no change.
    @Test("re-selecting the current currency is a no-op")
    func reSelectingTheSameCurrencyDoesNothing() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        await viewModel.selectCurrency("INR")

        #expect(await transport.requestCount(for: Endpoint.currency) == 0)
    }

    /// **The one write in the app whose offline failure does not replace the screen** (#23's criterion, ADR-0038):
    /// the picker stays, the tick stays where the server left it, and the explanation sits above the list.
    @Test("a currency change with no connection explains itself and leaves the screen alone")
    func anOfflineCurrencyChangeExplainsRatherThanFailing() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs().merging(
            [Endpoint.currency: .notConnected]
        ) { _, stub in stub })
        let (viewModel, before) = try await Self.loaded(transport)

        await viewModel.selectCurrency("AED")

        #expect(viewModel.refusal(about: .currency) == .needsConnection)
        #expect(!viewModel.state.isOffline, "the screen went offline, taking the picker and the explanation with it")
        #expect(viewModel.state.value == before, "the screen changed after a change that did not happen")
    }

    /// **A refused change can be tried again**, which it could not until review: the picker was disabled on
    /// `refusal != nil` and nothing cleared it, so one attempt with no connection left the control dead for the rest
    /// of the session — the user told a change had not happened and unable to make it.
    @Test("a currency change refused with no connection can be made again when there is one")
    func aRefusedCurrencyChangeCanBeRetried() async throws {
        let transport = FixtureTransport(
            // Offline, then the real answer — which is what "try again in a minute" means.
            sequences: [Endpoint.currency: [.notConnected, try .ok(.accountAED)]],
            stubs: try Self.stubs()
        )
        let (viewModel, _) = try await Self.loaded(transport)

        await viewModel.selectCurrency("AED")
        #expect(viewModel.refusal(about: .currency) == .needsConnection)
        #expect(!viewModel.isWriting, "the picker is still in flight after a refusal")

        await viewModel.selectCurrency("AED")

        #expect(viewModel.refusal == nil)
        #expect(viewModel.state.value?.currency.rawValue == "AED")
        #expect(await transport.requestCount(for: Endpoint.currency) == 2)
    }

    /// **A refusal belongs to one control.** With one bare reason on the view model, a failed export drew its
    /// sentence over the currency picker and a failed currency change drew one under the export button.
    @Test("a refusal is about the control that was tried and no other")
    func aRefusalNamesItsControl() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs().merging(
            [Endpoint.currency: .notConnected]
        ) { _, stub in stub })
        let (viewModel, _) = try await Self.loaded(transport)

        await viewModel.selectCurrency("AED")

        #expect(viewModel.refusal(about: .currency) == .needsConnection)
        for subject in AccountViewModel.Refusal.Subject.allCases
            where subject != AccountViewModel.Refusal.Subject.currency {
            #expect(viewModel.refusal(about: subject) == nil, "\(subject)")
        }
    }

    /// And a server that refuses says so differently, because trying again in a minute is not the remedy.
    @Test("a currency change the server refuses is a different explanation")
    func aRefusedCurrencyChangeSaysSo() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs().merging(
            [Endpoint.currency: .response(status: 500, body: Data())]
        ) { _, stub in stub })
        let (viewModel, _) = try await Self.loaded(transport)

        await viewModel.selectCurrency("AED")

        #expect(viewModel.refusal(about: .currency) == .refused)
        #expect(viewModel.state.value != nil)
    }

    // MARK: - The language

    /// The switch goes through `LanguageManager`, which is the one owner of the choice (ADR-0024) — and the screen
    /// is re-read afterwards, because its own payload was formatted in the old language.
    @Test("a language switch goes through the manager and re-reads the screen")
    func aLanguageSwitchGoesThroughTheManager() async throws {
        let language = LanguageManager(selected: .english)
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport, language: language)

        await viewModel.selectLanguage(.arabic)

        #expect(language.selected == .arabic)
        #expect(await transport.requestCount(for: Endpoint.language) == 1)
        #expect(await transport.requestCount(for: Endpoint.screenAccount) == 2, "the screen was not re-read")
        #expect(viewModel.notice == .languageChanged)
        #expect(viewModel.refusal == nil)
    }

    /// A server that stores a **different** language is a failed switch, and the manager's revert is what the
    /// screen reports (ADR-0024). Nothing here re-implements that; what is asserted is that it is surfaced.
    @Test("a server that stores a different language is reported and reverted")
    func aDisagreeingServerIsReverted() async throws {
        let language = LanguageManager(selected: .english)
        let transport = FixtureTransport(stubs: try Self.stubs().merging(
            // Asked for Arabic, answered with English.
            [Endpoint.language: try .ok(.languageEnglish)]
        ) { _, stub in stub })
        let (viewModel, _) = try await Self.loaded(transport, language: language)

        await viewModel.selectLanguage(.arabic)

        #expect(language.selected == .english, "the app switched to a language the server never stored")
        #expect(viewModel.refusal(about: .language) == .refused)
        #expect(viewModel.notice != .languageChanged)
    }

    /// The picker offers the **two shipped languages**, never the design's 87 (Product Spec §3.7 **[FIX]**).
    @Test("the language picker offers the shipped set and nothing else")
    func thePickerOffersTheShippedSet() async throws {
        let (viewModel, _) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        #expect(viewModel.shippedLanguages == AppLanguage.shipped)
        #expect(viewModel.shippedLanguages.count == 2)
    }

    /// The tick follows the **payload**, not the manager: the manager is optimistic and reverts on failure, so
    /// following it would tick a language the server has not accepted.
    @Test("the picker's selection is the stored language rather than the one on screen")
    func theSelectionFollowsTheServer() async throws {
        let language = LanguageManager(selected: .arabic)
        let (viewModel, _) = try await Self.loaded(
            FixtureTransport(stubs: try Self.stubs()),
            language: language
        )

        #expect(language.selected == .arabic)
        #expect(viewModel.storedLanguage == .english)
    }

    // MARK: - Changing the password

    /// Walks the flow to the third step with everything filled in. **It does not restart the flow** — the page's
    /// own `.task` does that once, and restarting here would reset `attempts` and make the support-after-three
    /// assertion below pass for the wrong reason.
    private static func advance(_ viewModel: AccountViewModel, throughStepsBefore final: String) async {
        viewModel.editCurrentPassword("the-old-one")
        await viewModel.advancePasswordChange()
        viewModel.editAnswer(at: 0, "Biscuit")
        viewModel.editAnswer(at: 1, "Jaipur")
        await viewModel.advancePasswordChange()
        viewModel.editNewPassword(final)
        viewModel.editConfirmation(final)
    }

    /// **One request, at the end.** The three steps are the client's sequencing; nothing exists server-side until
    /// the last button, and there is deliberately no route that checks a password on its own (``PasswordChange``).
    @Test("the three steps are one request, sent from the last one")
    func threeStepsAreOneRequest() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, screen) = try await Self.loaded(transport)

        viewModel.beginPasswordChange()
        await Self.advance(viewModel, throughStepsBefore: "a-much-longer-one")
        #expect(await transport.requestCount(for: Endpoint.password) == 0, "a step sent a request of its own")

        await viewModel.advancePasswordChange()

        #expect(await transport.requestCount(for: Endpoint.password) == 1)
        let body = try await Self.body(transport, at: Endpoint.password, method: "POST")
        #expect(body["currentPassword"] as? String == "the-old-one")
        #expect(body["newPassword"] as? String == "a-much-longer-one")

        // **The id, never the question's text** (§4.3 **[FIX]**, defect D12): the answer's hash is keyed to the id.
        let answers = try #require(body["securityAnswers"] as? [[String: Any]])
        #expect(answers.count == 2)
        #expect(answers.map { $0["questionId"] as? String } == screen.password.questions.map(\.id))
        #expect(answers.map { $0["answer"] as? String } == ["Biscuit", "Jaipur"])
        #expect(answers.allSatisfy { Set($0.keys) == ["questionId", "answer"] })
    }

    /// And it lands as a write does: the screen comes back from the response and the draft — two passwords and two
    /// answers — is emptied.
    @Test("a landed password change re-renders from the response and empties the draft")
    func aLandedChangeClearsTheDraft() async throws {
        let (viewModel, _) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        viewModel.beginPasswordChange()
        await Self.advance(viewModel, throughStepsBefore: "a-much-longer-one")
        await viewModel.advancePasswordChange()

        #expect(viewModel.notice == .passwordChanged)
        #expect(viewModel.password.current.isEmpty)
        #expect(viewModel.password.newPassword.isEmpty)
        #expect(viewModel.password.confirmation.isEmpty)
        #expect(viewModel.password.answers.allSatisfy { $0.isEmpty })
        #expect(viewModel.password.step == .currentPassword)
    }

    @Test("an empty current password does not advance and sends nothing")
    func anEmptyCurrentPasswordStops() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.beginPasswordChange()
        await viewModel.advancePasswordChange()

        #expect(viewModel.password.step == .currentPassword)
        #expect(viewModel.password.failure == .currentPasswordMissing)
        #expect(await transport.recordedRequests.count == 1)
    }

    @Test("both answers are required to move on")
    func bothAnswersAreRequired() async throws {
        let (viewModel, _) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        viewModel.beginPasswordChange()
        viewModel.editCurrentPassword("the-old-one")
        await viewModel.advancePasswordChange()
        viewModel.editAnswer(at: 0, "Biscuit")
        await viewModel.advancePasswordChange()

        // **Both**, which is Product Spec §3.7's **[FIX]** — the design asks for one code and this asks for two
        // answers.
        #expect(viewModel.password.step == .securityQuestions)
        #expect(viewModel.password.failure == .answerMissing)
    }

    @Test("a new password under eight characters, or one that is not confirmed, is refused locally")
    func theNewPasswordRules() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.beginPasswordChange()
        await Self.advance(viewModel, throughStepsBefore: "short")
        await viewModel.advancePasswordChange()
        // 8+ everywhere (invariant 4).
        #expect(viewModel.password.failure == .newPasswordTooShort)

        viewModel.editNewPassword("a-much-longer-one")
        viewModel.editConfirmation("a-much-longer-onf")
        await viewModel.advancePasswordChange()
        #expect(viewModel.password.failure == .confirmationMismatch)

        #expect(await transport.requestCount(for: Endpoint.password) == 0)
    }

    /// **The refusal names the step**, which is the other half of the one-request decision: the box the user has to
    /// retype is the one they are put back in front of.
    @Test("a wrong current password sends the reader back to the first step")
    func aWrongCurrentPasswordNamesItsStep() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs().merging([
            // **422, not 401** — and that is a constraint on the route rather than a detail of this test. A
            // `401` is answered by refreshing and retrying once (ADR-0007); a `401` here would spend the refresh
            // token, and against a rotating family a mistyped password could end the session. See
            // `ErrorCode.invalidCredentials`.
            Endpoint.password: .response(
                status: 422,
                body: Data(#"{"error":{"code":"INVALID_CREDENTIALS","message":"nope"}}"#.utf8)
            ),
        ]) { _, stub in stub })
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.beginPasswordChange()
        await Self.advance(viewModel, throughStepsBefore: "a-much-longer-one")
        await viewModel.advancePasswordChange()

        #expect(viewModel.password.failure == .currentPasswordRejected)
        #expect(viewModel.password.step == .currentPassword)
        // **A field error, not a failed screen**: it is a refusal the user can act on.
        #expect(viewModel.state.value != nil)
        #expect(!viewModel.state.isFailed)
    }

    /// A refused answer goes back to the questions — and after three misses the reader is pointed at support,
    /// which is the design's own escape route.
    @Test("refused answers go back to the questions, and three misses offer support")
    func refusedAnswersNameTheirStep() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs().merging([
            Endpoint.password: .response(
                status: 422,
                body: Data(#"{"error":{"code":"SECURITY_ANSWERS_INVALID"}}"#.utf8)
            ),
        ]) { _, stub in stub })
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.beginPasswordChange()
        await Self.advance(viewModel, throughStepsBefore: "a-much-longer-one")

        for attempt in 1...3 {
            await viewModel.advancePasswordChange()

            #expect(viewModel.password.failure == .answersRejected, "attempt \(attempt)")
            // Back to the step the refusal is about, so the boxes to retype are the ones on screen.
            #expect(viewModel.password.step == .securityQuestions, "attempt \(attempt)")
            #expect(viewModel.password.shouldOfferSupport == (attempt >= 3), "attempt \(attempt)")

            // The reader answers again and presses on, which is the only way back to the last step.
            if attempt < 3 { await viewModel.advancePasswordChange() }
        }

        #expect(await transport.requestCount(for: Endpoint.password) == 3)
    }

    /// Every failure belongs to exactly one step, so a message is never drawn beside a box that is not on screen.
    @Test("every password failure names the step whose box it is about", arguments: AccountViewModel.PasswordDraft.Failure.allCases)
    func everyFailureNamesAStep(_ failure: AccountViewModel.PasswordDraft.Failure) {
        #expect(AccountViewModel.PasswordStep.allCases.contains(failure.step))
    }

    /// The two server codes are the only ones read as field errors, and **only on the password write** — the same
    /// code arriving on a details write is not a wrong current password, because there is no password in that
    /// request.
    @Test("a code that names a password box is not read as one on another write")
    func aPasswordCodeOnAnotherWriteIsNotAFieldError() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs().merging([
            Endpoint.me: .response(
                status: 422,
                body: Data(#"{"error":{"code":"INVALID_CREDENTIALS"}}"#.utf8)
            ),
        ]) { _, stub in stub })
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.beginEditingPersonal()
        await viewModel.savePersonalDetails()

        #expect(viewModel.password.failure == nil)
        #expect(viewModel.state.isFailed)
        #expect(viewModel.state == .failed(.invalidCredentials))
    }

    /// The meter is feedback and gates nothing: the only rule that refuses a password is 8+ (invariant 4).
    @Test("the strength meter follows the design's formula and refuses nothing")
    func theStrengthMeterIsFeedback() async throws {
        let (viewModel, _) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))
        viewModel.beginPasswordChange()

        viewModel.editNewPassword("abc")
        #expect(viewModel.passwordStrength == .weak)
        viewModel.editNewPassword("Abcdefgh1!")
        #expect(viewModel.passwordStrength > .weak)
    }

    // MARK: - Offline, and the write mapping

    /// A *details* write with no connection is `LoadState.offline`, exactly as Expenses' writes are (ADR-0019):
    /// there is nothing to correct and no queue to hold it.
    @Test("a personal-details write with no connection becomes the offline state")
    func anOfflineDetailsWriteIsOffline() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs().merging(
            [Endpoint.me: .notConnected]
        ) { _, stub in stub })
        let (viewModel, _) = try await Self.loaded(transport)

        viewModel.beginEditingPersonal()
        viewModel.editDisplayName("Neeraj M")
        await viewModel.savePersonalDetails()

        #expect(viewModel.state.isOffline)
        // **The typing survives**, which is the whole of what can be offered when there is no queue.
        #expect(viewModel.personal.displayName == "Neeraj M")
        #expect(viewModel.isEditingPersonal)
    }

    // MARK: - The reference lists

    /// On demand, once, and a failure leaves the screen alone — a picker with no options is a worse screen, not a
    /// broken one.
    @Test("the reference lists are fetched on demand and only once")
    func theReferenceListsLoadOnDemand() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        #expect(viewModel.displayCurrencies.isEmpty)

        await viewModel.loadCurrencies()
        await viewModel.loadCurrencies()
        await viewModel.loadDialCodes()

        // The acceptance counts the workspace's content rules set.
        #expect(viewModel.displayCurrencies.count == 160)
        #expect(viewModel.dialCodes.count == 251)
        #expect(await transport.requestCount(for: Endpoint.path(for: .currencies)) == 1)
    }

    @Test("a reference list that will not load leaves the screen alone")
    func aFailedListDoesNotBreakTheScreen() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs().merging(
            [Endpoint.path(for: .currencies): .notConnected]
        ) { _, stub in stub })
        let (viewModel, screen) = try await Self.loaded(transport)

        await viewModel.loadCurrencies()

        #expect(viewModel.displayCurrencies.isEmpty)
        #expect(viewModel.state.value == screen)
    }

    /// A dial code is chosen as a **pair** — the ISO code and the dial code — because `+971` with no country
    /// behind it is a number the server cannot store (``PhoneNumber``).
    @Test("choosing a dial code takes the country with it")
    func choosingADialCodeTakesTheCountry() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)
        await viewModel.loadDialCodes()

        viewModel.beginEditingPersonal()
        viewModel.chooseDialCode(country: "AE")
        viewModel.editPhoneDigits("501234567")
        await viewModel.savePersonalDetails()

        let phone = try #require(
            try await Self.body(transport, at: Endpoint.me, method: "PUT")["phone"] as? [String: Any]
        )
        #expect(phone["country"] as? String == "AE")
        #expect(phone["dialCode"] as? String == "+971")
        #expect(phone["national"] as? String == "501234567")
        // E.164 is what makes a number unambiguous across borders, and it is built once (``PhoneNumber``).
        #expect(phone["e164"] as? String == "+971501234567")
    }

    // MARK: - The data-subject export

    /// `GET /v1/me/export` — the UAE PDPL access right (Product Spec §8). The bytes are held and **not decoded**:
    /// the client owns no schema for one person's whole history (``APIClient/bytes(at:)``).
    @Test("the export is held as bytes, exactly as the server sent them")
    func theExportIsHeldAsBytes() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (viewModel, _) = try await Self.loaded(transport)

        await viewModel.exportMyData()

        #expect(viewModel.exportedData == TestBench.payload(.meExport))
        #expect(await transport.requestCount(for: Endpoint.export) == 1)
        // Per-user, so it **presents the session and bypasses every cache** (invariant 8).
        let request = try #require(await transport.recordedRequests.last { $0.path == Endpoint.export })
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)

        viewModel.discardExport()
        #expect(viewModel.exportedData == nil)
    }

    @Test("an export that will not download explains itself and leaves the screen alone")
    func aFailedExportExplainsItself() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs().merging(
            [Endpoint.export: .notConnected]
        ) { _, stub in stub })
        let (viewModel, screen) = try await Self.loaded(transport)

        await viewModel.exportMyData()

        #expect(viewModel.exportedData == nil)
        #expect(viewModel.refusal(about: .export) == .needsConnection)
        // **And it says nothing about anything else**, which is review's correction: one bare reason on the view
        // model drew this sentence over the currency picker.
        #expect(viewModel.refusal(about: .currency) == nil)
        #expect(viewModel.state.value == screen)
    }

    // MARK: - The unwritten endpoint

    /// A `501` is a **failure**, not an absence — the state every unwritten screen endpoint answers with until the
    /// backend has one.
    @Test("a 501 from the screen endpoint is a failed state")
    func fiveHundredAndOneIsAFailure() async throws {
        let viewModel = Self.makeViewModel(
            FixtureTransport(stubs: [Endpoint.screenAccount: .response(status: 501, body: Data())])
        )

        try await viewModel.load()

        #expect(viewModel.state.isFailed)
        #expect(!viewModel.state.isOffline)
    }
}
