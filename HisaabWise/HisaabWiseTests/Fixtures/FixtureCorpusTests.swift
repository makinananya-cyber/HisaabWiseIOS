import Foundation
@testable import HisaabWise
import Testing

/// The corpus, and the claim ADR-0013 makes about it: **one set of files, two consumers, so drift breaks a
/// test rather than rotting a preview.**
///
/// That claim has three parts, and each is asserted here rather than described. Every payload in the corpus
/// decodes into the type the app decodes it into — a fixture that no longer matches the model is a failure
/// here. Every endpoint the app calls has a payload behind it, found by **reading `Endpoint.swift`** rather
/// than from a list, so a route added next month is covered without anybody remembering. And the drift itself
/// is exercised: one fixture is deliberately wrong, and it fails for the reason it should.
@Suite("The fixture corpus")
struct FixtureCorpusTests {
    // MARK: - Every file is there and is the shape it says it is

    @Test("every fixture in the corpus has a file behind it", arguments: Fixture.allCases)
    func everyFixtureResolves(_ fixture: Fixture) throws {
        // The whole point of the enum: a missing file is a test failure rather than an empty preview or a
        // `noOutcome` thrown from somewhere unrelated three suites later.
        #expect(try !fixture.data().isEmpty)
    }

    @Test("the budget payloads decode into the type the app decodes them into")
    func budgetsDecode() throws {
        let inr = try Fixture.budgetINR.decode(BudgetSummary.self)
        #expect(inr.income.display == "₹65,000")
        #expect(inr.income.currency.rawValue == "INR")
        #expect(inr.month == "2026-08")

        let aed = try Fixture.budgetAED.decode(BudgetSummary.self)
        #expect(aed.income.display == "AED 8,000")
        #expect(aed.income.currency.rawValue == "AED")
    }

    @Test("the money corpus spans the exponents in circulation")
    func moneyExponentsDecode() throws {
        let money = try Fixture.moneyExponents.decode([Money].self)

        #expect(Set(money.map(\.exponent)) == [0, 2, 3])
        // Every one carries a display string, because the client has no formatter to make one (ADR-0003).
        #expect(money.allSatisfy { !$0.display.isEmpty })
    }

    @Test("the session payloads decode")
    func sessionPayloadsDecode() throws {
        let tokens = try Fixture.sessionTokens.decode(SessionTokens.self)
        // Read back through `AccessToken`, which parses the JWT — so a fixture whose middle segment stopped
        // being base64url would fail here rather than in whichever suite happened to use it.
        #expect(!tokens.refreshToken.isEmpty)
        #expect(!tokens.accessToken.isNearExpiry())

        #expect(try Fixture.meVerified.decode(SessionUser.self).emailVerified)
        #expect(try !Fixture.meUnverified.decode(SessionUser.self).emailVerified)
        // The two differ in exactly one field: the pair exists to exercise verification flipping, and two
        // fixtures that also disagreed about the email would prove nothing about it.
        #expect(try Fixture.meVerified.decode(SessionUser.self).email
            == Fixture.meUnverified.decode(SessionUser.self).email)

        #expect(try Fixture.logoutAcknowledged.decode(Acknowledgement.self) == Acknowledgement())
    }

    /// The language payload has no `Decodable` of its own here on purpose — `LanguagePreference` is `private`
    /// to `Networking`, and a copy of it in the test target would be a second shape to keep in step. So the
    /// fixture is exercised the way the app reads it: through `APIClient.setLanguage`.
    @Test("the language payload is read the way the client reads it")
    func languagePayloadDecodes() async throws {
        let transport = try FixtureTransport.serving([.languageArabic])
        let client = await TestBench.client(transport)

        #expect(try await client.setLanguage(.arabic) == .arabic)
    }

    // MARK: - Coverage, read out of the source

    /// **Every endpoint the app calls has a payload in the corpus.**
    ///
    /// The paths come from `Endpoint.swift` rather than from a list in this file, which is the difference
    /// between a coverage assertion and a coverage claim: the six ADR-0020 screen endpoints will arrive
    /// there, and this test will ask for their payloads on the day they do.
    @Test("every endpoint in the app has a fixture behind it")
    func everyEndpointIsCovered() throws {
        let declared = try Self.endpointPaths()
        // A scan that read nothing would pass while asserting nothing, so it is checked to have found the one
        // path that has been there since the walking skeleton.
        #expect(declared.contains(Endpoint.budget), "no paths were found in Endpoint.swift")

        let covered = Set(Fixture.allCases.flatMap(\.endpoints))
        for path in declared {
            #expect(
                covered.contains(path),
                """
                \(path) has no fixture. A screen or a suite that needs it will write a payload inline, and \
                the inline copy is the one that drifts (ADR-0013)
                """
            )
        }
    }

    /// And the converse: a fixture may not answer a path the app does not call — a payload for an endpoint that
    /// does not exist is a guess at a contract, which is what ADR-0020's unwritten screen endpoints must not
    /// have in the client yet.
    ///
    /// Checked as an **absence of literals** rather than by comparing the two lists, because comparing them
    /// proves very little: `Fixture.endpoints` is written in terms of `Endpoint`'s own constants, so the
    /// compiler already refuses a path that does not exist. The way a guessed path would actually get in is as
    /// a string.
    @Test("no fixture hardcodes a path")
    func noFixtureInventsAnEndpoint() throws {
        let declared = Set(try Self.endpointPaths())
        let offenders = try SourceTree.codeLines(
            of: SourceTree.appSources.appending(path: "Fixtures/Fixture.swift")
        )
        .filter { $0.contains("\"/v1") }

        #expect(offenders.isEmpty, "a fixture names a path as a literal instead of through Endpoint: \(offenders)")
        // And the mapping is not empty, or the coverage test above would be reading an empty set.
        #expect(Set(Fixture.allCases.flatMap(\.endpoints)).isSubset(of: declared))
        #expect(!Fixture.allCases.flatMap(\.endpoints).isEmpty)
    }

    /// Every `/v1` path literal declared in `Networking/Endpoint.swift`.
    private static func endpointPaths() throws -> [String] {
        let source = try SourceTree.codeLines(
            of: SourceTree.appSources.appending(path: "Networking/Endpoint.swift")
        )
        let pathShaped = try Regex(#"\"(/v1/[A-Za-z0-9/_-]+)\""#)

        return source.flatMap { line in
            line.matches(of: pathShaped).compactMap { $0[1].substring.map(String.init) }
        }
    }

    // MARK: - Drift

    /// **The claim ADR-0013 rests on, exercised.** A fixture that has drifted from the API must fail a test,
    /// and it must fail for the right reason — a decode that broke on the *month* field would pass this test
    /// while proving nothing about the money the drift is in.
    @Test("a drifted fixture fails to decode, for the reason it drifted")
    func driftFailsDecoding() throws {
        #expect(throws: MoneyDecodingError.missingDisplayString) {
            try Fixture.budgetDrifted.decode(BudgetSummary.self)
        }
    }

    /// And what drift looks like from a *screen*, which is the consequence that matters: the whole chain —
    /// transport, client, `BaseViewModel.load()` — turns it into a failed state rather than into a screen
    /// drawing something wrong. A decoder test alone would leave open whether the client swallowed it.
    @MainActor
    @Test("drift reaches a screen as a failure rather than as bad figures")
    func driftFailsAScreen() async throws {
        let viewModel = HomeViewModel(
            client: TestBench.client(try FixtureTransport.serving([.budgetDrifted]))
        )

        try await viewModel.load()

        #expect(viewModel.state.value == nil)
        #expect(viewModel.state.isFailed)
    }

    /// A drifted fixture is only useful if it is *nearly* right. One that had drifted in every field would
    /// fail whatever the model did, and would stop telling anybody anything.
    ///
    /// It drifts by carrying a **blank** display string rather than by dropping the key, and that is the more
    /// useful of the two: a missing key fails through `Decodable`'s generated initialiser, which would pass this
    /// suite whatever `Money` decided, while a blank one is refused by `Money`'s own guard — the ADR-0003 rule
    /// that the client has no formatter to fall back on. The missing-key case is covered below, without a second
    /// file.
    @Test("the drifted fixture differs from the good one in one field")
    func driftIsMinimal() throws {
        let drifted = try #require(
            try JSONSerialization.jsonObject(with: try Fixture.budgetDrifted.data()) as? [String: Any]
        )
        let income = try #require(drifted["income"] as? [String: Any])
        #expect(income["display"] as? String == "", "the drifted fixture has grown a display string back")

        // And *everything else* is the good fixture, asserted rather than assumed: put the display string back
        // and the two payloads are the same object. That is what stops the drift moving to a different field as
        // `BudgetSummary` grows the rest of §5 — at which point the decode would fail on a missing key instead,
        // and this suite would still be green while proving something else.
        var repaired = drifted
        var repairedIncome = income
        repairedIncome["display"] = "₹65,000"
        repaired["income"] = repairedIncome

        let good = try #require(
            try JSONSerialization.jsonObject(with: try Fixture.budgetINR.data()) as? [String: Any]
        )
        #expect(NSDictionary(dictionary: repaired) == NSDictionary(dictionary: good))
    }

    /// The other shape drift takes: a field that has left the wire entirely. Made by removing the key from the
    /// good fixture rather than by keeping a third file, so the two drifts cannot disagree about anything else.
    @Test("a field that vanishes from the payload fails too")
    func aMissingFieldFails() throws {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: try Fixture.budgetINR.data()) as? [String: Any]
        )
        var income = try #require(payload["income"] as? [String: Any])
        income["display"] = nil
        payload["income"] = income

        let data = try JSONSerialization.data(withJSONObject: payload)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(BudgetSummary.self, from: data)
        }
    }

    // MARK: - The default is rupees

    /// **Defect D1, as a property of the corpus.** The prototype hardcoded `AED 8,000` on Home; the standing
    /// preview fixture is rupees, so a hardcoded dirham figure is visible in Xcode at design time rather than
    /// waiting for a regression test (ADR-0013).
    ///
    /// The two fixtures are deliberately the same *screen* in different currencies, and the AED one carries
    /// the defect's exact figure — so a screen that has gone back to hardcoding looks right against exactly
    /// one fixture in the corpus and wrong against the default.
    @Test("the default preview fixture is rupees, and the dirham one carries D1's own figure")
    func theDefaultIsINR() throws {
        let standard = try Fixture.budgetINR.decode(BudgetSummary.self)

        #expect(standard.income.currency.rawValue == "INR")
        #expect(!standard.income.display.contains("AED"))
        #expect(try Fixture.budgetAED.decode(BudgetSummary.self).income.display == "AED 8,000")
    }

    @MainActor
    @Test("the standing preview view model is the rupee one")
    func thePreviewViewModelIsINR() async throws {
        let viewModel = HomeViewModel.previewINRSalary
        try await viewModel.load()

        #expect(viewModel.state.value?.income.display == "₹65,000")
    }
}
