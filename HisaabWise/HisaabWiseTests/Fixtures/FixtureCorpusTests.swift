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
                covered.contains(path) || covered.contains { $0.hasPrefix("\(path)/") },
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
        // And the mapping is not empty, or the coverage test above would be reading an empty set. **Prefix
        // matching**, because one route is parameterised: `Endpoint.articleBody(id:)` builds
        // `/v1/content/articles/scams` from the declared `/v1/content/articles`, and an instance of a route is
        // still that route. Equality would have forced either a literal per article id or a fixture claiming
        // nothing.
        for path in Set(Fixture.allCases.flatMap(\.endpoints)) {
            #expect(
                declared.contains { path == $0 || path.hasPrefix("\($0)/") },
                "\(path) is not a route Endpoint declares, or an instance of one"
            )
        }
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
    ///
    /// Home no longer reads `/v1/budget` (ADR-0020), so the drifted *budget* payload is exercised through the
    /// screen endpoint's own drift instead: a blank `display` on a nested figure, which is the same `Money` guard
    /// three levels down.
    @MainActor
    @Test("drift reaches a screen as a failure rather than as bad figures")
    func driftFailsAScreen() async throws {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.homeINR)) as? [String: Any]
        )
        var savings = try #require(payload["savings"] as? [String: Any])
        var saved = try #require(savings["saved"] as? [String: Any])
        saved["display"] = ""
        savings["saved"] = saved
        payload["savings"] = savings

        let client = TestBench.client(
            FixtureTransport(stubs: [
                Endpoint.screenHome: .response(
                    status: 200,
                    body: try JSONSerialization.data(withJSONObject: payload)
                ),
            ])
        )
        let viewModel = HomeViewModel(
            client: client,
            content: ContentLoader(client: client, store: InMemoryContentStore())
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

        #expect(viewModel.state.value?.spending.total.display == "₹5,539")
        #expect(viewModel.state.value?.savings.saved.display == "₹23,000")
    }

    // MARK: - The Expenses payloads

    @Test("the expenses payloads decode into the type the app decodes them into")
    func expensesDecode() throws {
        let populated = try Fixture.expensesINR.decode(ExpensesScreen.self)
        #expect(populated.categories.count == 7)
        #expect(populated.summary.total.display == "₹5,539")
        #expect(!populated.wants.isOver)

        let firstRun = try Fixture.expensesFirstRun.decode(ExpensesScreen.self)
        #expect(firstRun.categories.count == 7)
        #expect(firstRun.categories.allSatisfy { $0.entries.isEmpty && $0.lines.isEmpty })

        // The one payload that carries the over-budget verdict, which is one of the screen's criteria.
        #expect(try Fixture.expensesOverBudget.decode(ExpensesScreen.self).wants.isOver)
    }

    /// **The counts are the acceptance test** the workspace's content rules set: 22 transport modes and 20 "Other"
    /// types. Asserted exactly rather than as a range, and the ids are asserted unique because the id is what
    /// crosses the wire — two options sharing one would file the wrong label.
    @Test("the pick lists carry the counts the content rules require")
    func picklistCountsAreExact() throws {
        let picklists = try Fixture.picklists.decode(Picklists.self)

        #expect(picklists.transport.count == 22)
        #expect(picklists.other.count == 20)
        #expect(Set(picklists.transport.map(\.id)).count == 22)
        #expect(Set(picklists.other.map(\.id)).count == 20)
        // Exactly one option asks the user what it actually was, and it is the last of the "Other" list — the
        // design's "Something else…". A **flag**, not a name match (ADR-0033).
        #expect(picklists.other.filter(\.opensFreeText).count == 1)
        #expect(picklists.other.last?.opensFreeText == true)
    }

    /// **The two screens tell one story about one month**, and this is what keeps them doing it.
    ///
    /// Home's donut and Expenses' summary both read the one budget engine (invariant 3), so the total spent has to
    /// be the *same* figure in both payloads. A difference is one of the two assemblies having summed something —
    /// exactly the class of mistake defect D1 was, and the same anchor the `saved` assertion below is.
    @Test("the home payload and the expenses payload agree about the month's spending")
    func theCorpusAgreesAboutSpending() throws {
        let home = try Fixture.homeINR.decode(HomeScreen.self)
        let expenses = try Fixture.expensesINR.decode(ExpensesScreen.self)

        #expect(home.spending.total.display == expenses.summary.total.display)
        #expect(home.spending.total.minor == expenses.summary.total.minor)
        #expect(home.monthLabel == expenses.monthLabel)

        // And each category Home draws a slice for is the same figure Expenses draws a row for. Home's donut
        // excludes Additional Income, so it has six of the seven — asserted as a subset rather than an equality,
        // which is what "money in is not spending" means for the corpus.
        for category in home.spending.categories {
            let row = try #require(
                expenses.category(id: category.id),
                "Home draws \(category.id) and Expenses has no such category"
            )
            #expect(row.total.minor == category.amount.minor, "\(category.id) differs between the two screens")
            #expect(row.total.display == category.amount.display, "\(category.id) reads differently")
        }
        #expect(expenses.categories.count == home.spending.categories.count + 1)
        #expect(expenses.categories.filter { $0.flow == .incoming }.count == 1)
    }

    // MARK: - The Learn payloads

    @Test("the learn payloads decode into the type the app decodes them into")
    func learnPayloadsDecode() throws {
        let inProgress = try Fixture.learnInProgress.decode(LearnScreen.self)
        #expect(inProgress.units.count == 5)
        #expect(inProgress.lessons.count == 15)
        #expect(inProgress.nextLesson?.lessonID == "u1l3")

        let firstRun = try Fixture.learnFirstRun.decode(LearnScreen.self)
        #expect(firstRun.streak.value == 0)
        #expect(firstRun.lessons.filter { $0.state == .locked }.count == 14)

        // The one payload with no cursor, which is a state a screen that assumed one draws wrongly.
        #expect(try Fixture.learnComplete.decode(LearnScreen.self).nextLesson == nil)
    }

    /// **Home and Learn tell one story about one reader**, the way the Home/Expenses pair tells one about one
    /// month.
    ///
    /// Both read the same streak and the same XP total from the same source, so a difference between the two
    /// payloads is one of the two assemblies having worked something out — exactly the class of mistake defect D1
    /// was. Asserted on `Stat.value` rather than on the display strings, which is what that field is for: two
    /// strings can be wrong in the same way, and two numbers cannot be equal by accident.
    @Test("the home payload and the learn payload agree about the streak, the XP, and what is next")
    func theCorpusAgreesAboutLearning() throws {
        let home = try Fixture.homeINR.decode(HomeScreen.self)
        let learn = try Fixture.learnInProgress.decode(LearnScreen.self)
        // Unwrapped rather than defaulted: `contains(learn.nextLesson?.title ?? "")` is `contains("")`, which is
        // always true — so the assertion below would have gone silently vacuous the day a payload had no cursor.
        // Review caught it. This fixture has one, and requiring it is what says so.
        let next = try #require(learn.nextLesson)

        #expect(home.learning.streak == learn.streak.value)
        #expect(home.learning.nextLesson == next.title)
        // Home's mini-card composes "120 XP · next up, Needs vs. Wants" server-side, so the figure and the lesson
        // it names both have to be in it — a summary that had drifted from the XP total is the drift this catches.
        #expect(home.learning.summary.contains(learn.xp.display))
        #expect(home.learning.summary.contains(next.title))

        // And the first-run pair, where the two payloads have to agree that there is no streak and no XP.
        let newHome = try Fixture.homeFirstRun.decode(HomeScreen.self)
        let newLearn = try Fixture.learnFirstRun.decode(LearnScreen.self)
        #expect(newHome.learning.streak == newLearn.streak.value)
        #expect(newHome.learning.nextLesson == (try #require(newLearn.nextLesson)).title)
    }

    /// **Every lesson Home or Learn names is a lesson the curriculum has.**
    ///
    /// Which is a check the corpus could not make before #19: `home-first-run.json` pointed **Continue** at a
    /// lesson called "Money, plainly" that no unit carries, because #17 had no curriculum to check it against. The
    /// teaser is a title rather than an id, so nothing about it would ever have failed — this is what makes it
    /// fail.
    @Test("every lesson the payloads name exists in the curriculum")
    func everyNamedLessonExists() throws {
        let curriculum = try Fixture.curriculum.decode(Curriculum.self)
        let titles = Set(curriculum.allLessons.map(\.title))

        for fixture in [Fixture.homeINR, .homeFirstRun] {
            let named = try fixture.decode(HomeScreen.self).learning.nextLesson
            #expect(titles.contains(named), "\(fixture.rawValue) points Continue at \"\(named)\", which no unit has")
        }

        for fixture in [Fixture.learnInProgress, .learnFirstRun] {
            let next = try #require(try fixture.decode(LearnScreen.self).nextLesson)
            let lesson = try #require(
                curriculum.lesson(id: next.lessonID),
                "\(fixture.rawValue) names the lesson \(next.lessonID), which no unit has"
            )
            #expect(lesson.title == next.title, "the payload's title for \(next.lessonID) is not the curriculum's")
            #expect(curriculum.units.contains { $0.id == next.unitID })
        }
    }

    /// **The screen payload and the curriculum agree about the questions in a lesson.**
    ///
    /// A ring's segment count is the server's (`LearnScreen.LessonProgress.segments`) precisely so the client does
    /// not count the curriculum's own question steps — which means the two can disagree, and a corpus that let them
    /// would be a corpus in which a ring is quietly one arc short. `LearnViewModelTests` asserts the *client* draws
    /// the payload's figure; this asserts the corpus does not need it to.
    @Test("every ring's segment count is the lesson's own question count")
    func theCorpusAgreesAboutRingSegments() throws {
        let curriculum = try Fixture.curriculum.decode(Curriculum.self)

        for fixture in [Fixture.learnInProgress, .learnFirstRun, .learnComplete] {
            let screen = try fixture.decode(LearnScreen.self)
            #expect(screen.lessons.count == curriculum.allLessons.count)

            for lesson in curriculum.allLessons {
                let progress = try #require(
                    screen.lesson(id: lesson.id),
                    "\(fixture.rawValue) says nothing about \(lesson.id)"
                )
                #expect(
                    progress.segments == lesson.questionCount,
                    "\(fixture.rawValue) draws \(lesson.id)'s ring in \(progress.segments) arcs over \(lesson.questionCount) questions"
                )
                // And no ring is fuller than it has arcs, which would draw an eighth segment of five.
                #expect((0...progress.segments).contains(progress.filledSegments))
                // A finished lesson's ring is full, which is what makes the tick and the ring agree.
                if progress.state == .completed { #expect(progress.filledSegments == progress.segments) }
                // A locked one has nothing lit, because nothing in it has been answered.
                if progress.state == .locked { #expect(progress.filledSegments == 0) }
            }
        }
    }

    /// **The sequential unlock rule holds in every Learn payload**, checked against the curriculum's own flattened
    /// order: a lesson is locked unless the one before it is completed, and the first is never locked.
    ///
    /// The client renders this and the server enforces it, so what the corpus has to guarantee is that the fixtures
    /// are *possible* states — a payload with lesson 5 open and lesson 4 locked would be a screen nobody could
    /// reach, and a test written against it would be asserting a state the server cannot produce.
    @Test("every learn payload is a state the unlock rule can produce")
    func theCorpusRespectsTheUnlockRule() throws {
        let curriculum = try Fixture.curriculum.decode(Curriculum.self)

        for fixture in [Fixture.learnInProgress, .learnFirstRun, .learnComplete] {
            let screen = try fixture.decode(LearnScreen.self)
            var previousWasCompleted = true

            for lesson in curriculum.allLessons {
                let progress = try #require(screen.lesson(id: lesson.id))
                #expect(
                    progress.isOpen == previousWasCompleted,
                    "\(fixture.rawValue): \(lesson.id) is \(progress.state) where the rule says otherwise"
                )
                previousWasCompleted = progress.state == .completed
            }
        }
    }

    // MARK: - The completion payloads

    @Test("the completion payloads decode into the type the app decodes them into")
    func completionPayloadsDecode() throws {
        let completed = try Fixture.lessonCompleted.decode(LessonCompletion.self)
        #expect(completed.isFirstCompletion)
        #expect(completed.xpEarned.value == 50)
        #expect(completed.xpEarned.display == "+50")
        #expect(completed.accuracy.display == "75%")
        #expect(completed.week.count == 7)
        #expect(completed.week.count { $0.isToday } == 1)
        #expect(!completed.streakLine.isEmpty)

        // The screen inside it is a whole Learn screen, which is what the map re-renders from (ADR-0020).
        #expect(completed.screen.lessons.count == 15)
        #expect(completed.screen.nextLesson?.lessonID == "u2l1")
    }

    /// **Defect D13, as the two payloads that describe it.** A first completion earns the run's XP; a replay earns
    /// **nothing** and leaves the total where it was.
    ///
    /// Asserted on `Stat.value` and against `learn-in-progress.json`'s own total, because that is what the field is
    /// for: a headline saying "Lesson revisited!" over a total that had quietly grown is exactly the bug, and only
    /// the numbers can tell the two apart.
    @Test("a replay earns no XP and leaves the total where it was")
    func aReplayEarnsNothing() throws {
        let before = try Fixture.learnInProgress.decode(LearnScreen.self)
        let replay = try Fixture.lessonRevisited.decode(LessonCompletion.self)

        #expect(!replay.isFirstCompletion)
        #expect(replay.xpEarned.value == 0)
        #expect(replay.screen.xp.value == before.xp.value)
        #expect(replay.screen.xp.display == before.xp.display)
        // The streak has not moved either: the reader had already learned something today.
        #expect(replay.screen.streak.value == before.streak.value)

        // And the first completion does move both, or the assertion above would pass against a payload that never
        // awards anything.
        let first = try Fixture.lessonCompleted.decode(LessonCompletion.self)
        #expect(first.screen.xp.value == before.xp.value + first.xpEarned.value)
        #expect(first.screen.streak.value == before.streak.value + 1)
    }

    /// The completion carries **no date, no timestamp, and no day key**, exactly as the three Learn payloads carry
    /// none (invariant 6) — the week strip is seven labels and three flags the *server* decided.
    ///
    /// `LearnViewModelTests` makes the same assertion about the screen payloads; this extends it to the one payload
    /// that has a calendar drawn on it, which is where a timestamp would be most tempting.
    @Test("the completion payloads carry no date, timestamp, or day key")
    func theCompletionCarriesNoDate() throws {
        for fixture in [Fixture.lessonCompleted, .lessonRevisited] {
            let json = String(decoding: TestBench.payload(fixture), as: UTF8.self)
            for field in ["date", "Date", "timestamp", "dayKey", "lastActive", "updatedAt"] {
                #expect(!json.contains(field), "\(fixture.rawValue) carries \(field)")
            }
        }
    }

    /// The embedded screen is a state the unlock rule can produce, and it is the state **finishing the cursor
    /// leaves behind**: the lesson completed with a full ring, and the next one open.
    @Test("the completion's screen is the map after the lesson it completed")
    func theCompletionScreenFollowsTheLesson() throws {
        let before = try Fixture.learnInProgress.decode(LearnScreen.self)
        let after = try Fixture.lessonCompleted.decode(LessonCompletion.self).screen
        let finished = try #require(before.nextLesson).lessonID

        let progress = try #require(after.lesson(id: finished))
        #expect(progress.state == .completed)
        #expect(progress.filledSegments == progress.segments, "the ring of a finished lesson is full")
        #expect(after.nextLesson?.lessonID != finished, "the cursor stayed on the lesson that was finished")

        // The rule the whole map is drawn from still holds, so the map this re-renders is one a reader could reach.
        let curriculum = try Fixture.curriculum.decode(Curriculum.self)
        var previousWasCompleted = true
        for lesson in curriculum.allLessons {
            let state = try #require(after.lesson(id: lesson.id))
            #expect(state.isOpen == previousWasCompleted, "\(lesson.id) is \(state.state) where the rule says otherwise")
            previousWasCompleted = state.state == .completed
        }
    }

    /// **Every Learn payload carries the token its lesson steps need** (``CurrencyToken``, ADR-0016), and the
    /// curriculum carries `{c}` verbatim rather than anybody's symbol.
    ///
    /// The two halves of that are one claim: content is cacheable and identical for everybody, so a hardcoded
    /// symbol in the curriculum would be one reader's currency shipped to all of them — and a screen payload with
    /// no token would leave `{c}` on screen.
    @Test("the learn payloads carry a currency token and the curriculum carries none")
    func theCorpusCarriesTheCurrencyToken() throws {
        for fixture in [Fixture.learnInProgress, .learnFirstRun, .learnComplete] {
            let screen = try fixture.decode(LearnScreen.self)
            #expect(!screen.currencyToken.token.isEmpty, "\(fixture.rawValue) has no currency token")
        }

        // And Home's tip token is the same reader's, so a lesson and a tip cannot show two currencies.
        let tipToken = try Fixture.homeINR.decode(HomeScreen.self).tip.currencyToken
        let lessonToken = try Fixture.learnInProgress.decode(LearnScreen.self).currencyToken.token
        #expect(tipToken == lessonToken)

        let curriculum = String(decoding: TestBench.payload(.curriculum), as: UTF8.self)
        #expect(curriculum.contains(CurrencyToken.placeholder), "the curriculum no longer carries {c} at all")
        for symbol in ["₹", "AED", "د.إ", "$"] {
            #expect(!curriculum.contains(symbol), "the curriculum hardcodes \(symbol) where {c} belongs")
        }
    }

    /// **Defect D1's anchor, in the corpus itself.** The screen payload is assembled from the budget engine, so
    /// `saved` has to be the *same* figure in both — a difference between them is the assembly having derived
    /// rather than read, which is exactly the class of mistake D1 was.
    @Test("the home payload and the budget payload agree about what was saved")
    func theCorpusAgreesAboutSaved() throws {
        let budget = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.budgetINR)) as? [String: Any]
        )
        let home = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.homeINR)) as? [String: Any]
        )
        let budgetSaved = try #require(budget["saved"] as? [String: Any])
        let homeSaved = try #require((home["savings"] as? [String: Any])?["saved"] as? [String: Any])

        #expect(homeSaved["minor"] as? Int == budgetSaved["minor"] as? Int)
        #expect(homeSaved["display"] as? String == budgetSaved["display"] as? String)
        #expect(homeSaved["currency"] as? String == budgetSaved["currency"] as? String)
    }

    // MARK: - The Reports payloads

    @Test("the reports payloads decode into the type the app decodes them into")
    func reportsPayloadsDecode() throws {
        let archive = try Fixture.reportsINR.decode(ReportsScreen.self)
        #expect(archive.allMonths.count == 6)
        #expect(archive.years.count == 1)
        #expect(archive.summary.totalSaved.display == "₹76,700")

        // The two payloads that claim no path, each carrying a state the standing one cannot show.
        #expect(try Fixture.reportsTwoYears.decode(ReportsScreen.self).years.count == 2)

        let empty = try Fixture.reportsEmpty.decode(ReportsScreen.self)
        #expect(empty.years.isEmpty)
        #expect(empty.trend.bars.isEmpty)
    }

    /// **The trio the screen's own criterion asks for**, in the standing payload rather than in a special one:
    /// one of each verdict, and §3.6's own count of two months in six that met the goal.
    @Test("the standing archive carries a hit, a near, and a miss — and two hits in six")
    func theArchiveCarriesEveryVerdict() throws {
        let archive = try Fixture.reportsINR.decode(ReportsScreen.self)
        let verdicts = archive.allMonths.map(\.verdict)

        #expect(Set(verdicts) == Set(ReportsScreen.Verdict.allCases))
        #expect(verdicts.filter { $0 == .hit }.count == 2, "§3.6 seeds two met months in six")
        #expect(archive.summary.goalsMetLabel.contains("2 of 6"))
    }

    /// **The archive and the trend agree about every month, which is defect D11 as a property of the corpus.**
    ///
    /// The two arrays are two orderings of the same closed months, and each carries a verdict and a percentage.
    /// A month whose bar said `hit` while its row said `near` would be one payload thresholding the same number
    /// twice — the mistake D11 *is*, moved from the client into the assembly. Matched by `monthKey`, which is why
    /// both arrays carry one.
    @Test("every bar and its month row carry the same verdict and the same percentage")
    func theTrendAndTheArchiveAgree() throws {
        for fixture in [Fixture.reportsINR, .reportsTwoYears] {
            let screen = try fixture.decode(ReportsScreen.self)
            let months = Dictionary(uniqueKeysWithValues: screen.allMonths.map { ($0.monthKey, $0) })

            #expect(screen.trend.bars.count == screen.allMonths.count, "\(fixture.rawValue)")
            for bar in screen.trend.bars {
                let month = try #require(months[bar.monthKey], "\(fixture.rawValue) charts a month the archive has not")
                #expect(bar.verdict == month.verdict, "\(bar.monthKey) is \(bar.verdict) charted and \(month.verdict) listed")
                #expect(bar.percentageLabel == month.percentageLabel, "\(bar.monthKey) reads two percentages")
            }
        }
    }

    /// **The grouping is the server's, and the two-year payload is what makes that checkable.**
    ///
    /// Every month in a group belongs to that group's year — asserted through `monthKey`, which is the one field
    /// carrying the year as data rather than as a label — and the groups run newest first, as do the months
    /// inside them. One group would prove that a header renders and nothing at all about the grouping.
    @Test("the archive is grouped by year, newest first, and every month is in the right group")
    func theArchiveIsGroupedByYear() throws {
        let screen = try Fixture.reportsTwoYears.decode(ReportsScreen.self)

        #expect(screen.years.map(\.label) == ["2026", "2025"])
        #expect(screen.years.map { $0.months.count } == [2, 1])
        #expect(screen.years.map { $0.totalSaved.display } == ["₹16,380", "₹13,200"])

        for year in screen.years {
            for month in year.months {
                #expect(month.monthKey.hasPrefix(year.label), "\(month.monthKey) is filed under \(year.label)")
            }
            // Newest first inside the group, which the design's list is and the trend's is not.
            #expect(year.months.map(\.monthKey) == year.months.map(\.monthKey).sorted(by: >))
        }
        // And the trend runs the other way — oldest to newest, as the design draws time.
        #expect(screen.trend.bars.map(\.monthKey) == screen.trend.bars.map(\.monthKey).sorted())
    }

    /// **The hero counts the months the archive holds**, which is what `Count.value` is for: two formatted
    /// strings can be wrong in the same way, and two numbers cannot be equal by accident.
    @Test("the hero's month count is the number of months in the archive", arguments: [
        Fixture.reportsINR, .reportsTwoYears, .reportsEmpty,
    ])
    func theHeroCountsTheArchive(_ fixture: Fixture) throws {
        let screen = try fixture.decode(ReportsScreen.self)

        #expect(screen.summary.monthCount.value == screen.allMonths.count)
        #expect(screen.summary.monthCount.display == "\(screen.allMonths.count)")
    }

    /// The geometry stays geometry: every fraction is inside its range, and a month's stripes account for the
    /// whole row rather than for some of it.
    ///
    /// **There is deliberately nothing here about the year totals or the mean**, and that absence is the point —
    /// the payload carries no per-month `saved`, so there is no sum for the corpus to check and none for a client
    /// to make. The assertion that they are the server's is the *shape* of the payload, which
    /// `ReportsViewModelTests` states directly.
    @Test("every fraction in the payload is a fraction", arguments: [Fixture.reportsINR, .reportsTwoYears])
    func theGeometryIsInRange(_ fixture: Fixture) throws {
        let screen = try fixture.decode(ReportsScreen.self)

        #expect((0...1).contains(screen.trend.goalPosition))
        for bar in screen.trend.bars {
            #expect((0...1).contains(bar.fill), "\(bar.monthKey) fills \(bar.fill) of the plot")
        }
        for month in screen.allMonths {
            // **One stripe per category that has something in it**, so a quiet month has fewer than six — the
            // design's own `t > 0 ? … : ''`. Asserted as "at most six, each slot once" rather than "six", which
            // the first version said and which would have made the design's normal case a corpus failure.
            #expect((1...6).contains(month.segments.count), "\(month.monthKey) has \(month.segments.count) stripes")
            #expect(Set(month.segments.map(\.slot)).count == month.segments.count, "\(month.monthKey) repeats a slot")
            #expect(month.segments.allSatisfy { (1...6).contains($0.slot) }, "\(month.monthKey) has a slot off the palette")
            // Whatever the count, the stripes still cover the whole row: they are shares of that month's spend.
            let total = month.segments.map(\.share).reduce(0, +)
            #expect(abs(total - 1) < 0.001, "\(month.monthKey)'s stripes cover \(total) of the row")
        }
    }

    /// **A quiet month has fewer stripes**, which the two-year payload carries so the branch both the model and
    /// `HWMonthRow` handle is a state the corpus actually contains rather than one only a preview shows.
    @Test("a month with an untouched category has fewer than six stripes")
    func aQuietMonthHasFewerStripes() throws {
        let screen = try Fixture.reportsTwoYears.decode(ReportsScreen.self)
        let quiet = try #require(screen.allMonths.first { $0.monthKey == "2025-12" })

        #expect(quiet.segments.count == 4, "December 2025 is the corpus's quiet month")
        #expect(!quiet.segments.contains { $0.slot == 5 }, "a month with no entertainment draws no violet stripe")
    }
}
