import Foundation
@testable import HisaabWise
import Testing

/// The lesson player and the celebration it becomes: **grading is the client's, every total is the server's, and
/// nothing is queued** (#20, invariant 10, ADR-0019).
///
/// The grading rules themselves are `LessonRunTests` — they are a property of a value with no transport in it. What
/// is asserted here is what these two objects add: the submission, the four states it can land in, the interim
/// progress report, and the map re-rendering from the response rather than from a patch.
@Suite("LessonPlayerViewModel")
@MainActor
struct LessonPlayerViewModelTests {
    private static func stubs(
        _ screen: Fixture = .learnInProgress,
        completing lessonID: String = "u1l3",
        with completion: Fixture = .lessonCompleted
    ) throws -> [String: FixtureTransport.Outcome] {
        [
            Endpoint.screenLearn: try .ok(screen),
            Endpoint.curriculum: try .ok(.curriculum, etag: "\"v1\""),
            Endpoint.learnProgress: try .ok(screen),
            Endpoint.lessonCompletion(lessonID: lessonID): try .ok(completion),
        ]
    }

    private static func learn(_ transport: FixtureTransport) async throws -> LearnViewModel {
        let client = TestBench.client(transport)
        let viewModel = LearnViewModel(client: client, content: ContentLoader(client: client, store: InMemoryContentStore()))
        try await viewModel.load()
        return viewModel
    }

    /// A player over the lesson `learn-in-progress.json`'s cursor points at, opened the way the screen opens it.
    private static func player(
        _ transport: FixtureTransport,
        lessonID: String = "u1l3"
    ) async throws -> (LearnViewModel, LessonPlayerViewModel) {
        let learn = try await learn(transport)
        learn.openLesson(lessonID: lessonID)
        return (learn, try #require(learn.player))
    }

    /// Answers every question in the run correctly and walks to the end, which is what produces a completion.
    private static func finish(_ player: LessonPlayerViewModel, correctly: Bool = true) throws {
        while player.completion == nil, !player.run.isOutOfHearts {
            switch try #require(player.run.step) {
            case .teach:
                break
            case .singleChoice(let question), .multiSelect(let question):
                let chosen = correctly
                    ? question.answers
                    : [try #require(question.options.indices.first { !question.answers.contains($0) })]
                for option in chosen { player.choose(option) }
                player.primaryAction()
            case .numeric(let question):
                player.type(correctly ? question.answerText : "\(question.answer + 1)")
                player.primaryAction()
            }
            player.primaryAction()
        }
    }

    // MARK: - Opening a lesson

    /// **The player is opened with the map's own material**: the unit for its number and accent, the lesson for its
    /// steps, and the reader's currency token for the `{c}` inside them.
    @Test("opening a lesson hands the player the unit, the lesson, and the currency token")
    func openingALesson() async throws {
        let (learn, player) = try await Self.player(FixtureTransport(stubs: try Self.stubs()))

        #expect(learn.player != nil)
        #expect(player.material.lesson.id == "u1l3")
        #expect(player.material.lesson.content.title == "Needs vs. Wants")
        #expect(player.material.unit.id == "u1")
        #expect(player.material.unit.content.number == 1)
        #expect(player.material.currencyToken.token == "₹")
        #expect(player.run.stepCount == 8)
        #expect(player.run.heartsRemaining == 3)
        #expect(player.completion == nil)
    }

    /// A lesson the map does not carry opens nothing rather than an empty player — the answer an unknown unit gets
    /// from the guide sheet.
    @Test("a lesson the map does not carry opens nothing")
    func anUnknownLessonOpensNothing() async throws {
        let learn = try await Self.learn(FixtureTransport(stubs: try Self.stubs()))

        learn.openLesson(lessonID: "u9l9")

        #expect(learn.player == nil)
    }

    /// **`{c}` becomes the reader's own symbol and nothing else changes** (ADR-0016): the figures in a lesson are
    /// illustrative, so they keep the numbers they were written around.
    @Test("the currency token is substituted into the lesson's own text")
    func theCurrencyTokenIsResolved() async throws {
        let (_, player) = try await Self.player(FixtureTransport(stubs: try Self.stubs()), lessonID: "u1l1")

        let resolved = player.resolved("Two people both earn **{c}8,000** a month.")
        #expect(resolved == "Two people both earn **₹8,000** a month.")
        #expect(!resolved.contains(CurrencyToken.placeholder))
    }

    /// **Opening the player hushes the toast and closes the guide sheet**, because the panel covers both.
    @Test("opening a lesson clears a pending notice and the guide sheet")
    func openingALessonClearsTheScreen() async throws {
        let learn = try await Self.learn(FixtureTransport(stubs: try Self.stubs()))

        learn.refuseLockedLesson()
        learn.openGuide(unitID: "u1")
        learn.openLesson(lessonID: "u1l3")

        #expect(learn.notice == nil)
        #expect(!learn.isShowingGuide)
        #expect(learn.player != nil)
    }

    // MARK: - The one button

    /// The primary control does one of three things and the run decides which: `Continue` past a teaching page,
    /// `Check` an open question, `Continue` past a graded one.
    @Test("the primary action continues, checks, and then continues")
    func thePrimaryAction() async throws {
        let (_, player) = try await Self.player(FixtureTransport(stubs: try Self.stubs()), lessonID: "u1l1")

        // Four teaching pages, each a Continue.
        for step in 0..<4 {
            #expect(player.run.index == step)
            player.primaryAction()
        }
        #expect(player.run.index == 4)

        // The first question: nothing to check until something is chosen.
        player.primaryAction()
        #expect(player.run.index == 4, "an unanswered question advanced")
        #expect(player.run.verdict == nil)

        guard case .singleChoice(let question) = try #require(player.run.step) else {
            Issue.record("u1l1's step 4 is no longer a single-choice question")
            return
        }
        player.choose(try #require(question.answers.first))
        player.primaryAction()
        #expect(player.run.verdict?.isCorrect == true)
        #expect(player.run.index == 4, "grading advanced the step as well")

        player.primaryAction()
        #expect(player.run.index == 5)
    }

    /// **The combo is the run's and the words are the catalogue's.** The number reaches the screen as a value so the
    /// badge and the announcement read the same one.
    @Test("a combo is raised for the screen and can be dismissed")
    func aComboIsRaised() async throws {
        let (_, player) = try await Self.player(FixtureTransport(stubs: try Self.stubs()), lessonID: "u3l3")

        var landed: [Int] = []
        while player.completion == nil {
            if case .singleChoice(let question) = player.run.step {
                player.choose(try #require(question.answers.first))
                player.primaryAction()
                if let milestone = player.comboMilestone { landed.append(milestone) }
                player.dismissCombo()
            }
            player.primaryAction()
        }

        #expect(landed == [3], "a combo landed on something other than the third consecutive answer")
    }

    // MARK: - Hearts

    /// **The run ends at zero hearts**: the dialog is up, nothing advances, and there is no completion to submit.
    @Test("running out of hearts ends the run with no submission")
    func outOfHeartsEndsTheRun() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (_, player) = try await Self.player(transport, lessonID: "u3l3")

        try Self.finish(player, correctly: false)

        #expect(player.run.isOutOfHearts)
        #expect(player.run.heartsRemaining == 0)
        #expect(player.completion == nil, "an exhausted run built a completion")
        #expect(await transport.requestCount(for: Endpoint.lessonCompletion(lessonID: "u3l3")) == 0)
    }

    /// **Try again** is a fresh run: three hearts, the first step, and none of the abandoned attempt's results —
    /// which were never submitted and belong to a run that did not finish.
    @Test("try again restarts the lesson with every heart and no results")
    func tryAgainRestarts() async throws {
        let (_, player) = try await Self.player(FixtureTransport(stubs: try Self.stubs()), lessonID: "u3l3")

        try Self.finish(player, correctly: false)
        #expect(!player.run.results.isEmpty)

        player.restart()

        #expect(player.run.index == 0)
        #expect(player.run.heartsRemaining == 3)
        #expect(player.run.results.isEmpty)
        #expect(!player.run.isOutOfHearts)
        #expect(player.comboMilestone == nil)
    }

    // MARK: - The interim progress report

    /// **Closing a part-finished run reports where the reader got to** — `POST /v1/learn/progress`, with the step
    /// and the results, so the ring behind the player fills and the run survives being interrupted.
    @Test("closing a part-finished run reports the step and the results")
    func closingReportsProgress() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (learn, player) = try await Self.player(transport, lessonID: "u1l1")

        player.primaryAction()
        player.primaryAction()
        learn.closePlayer()

        #expect(learn.player == nil)
        await Self.settle()

        let request = try #require(await transport.recordedRequests.last { $0.path == Endpoint.learnProgress })
        #expect(request.method == "POST")
        let sent = try #require(request.body)
        let body = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(body["lessonId"] as? String == "u1l1")
        #expect(body["stepIndex"] as? Int == 2)
        #expect((body["results"] as? [Any])?.isEmpty == true, "two teaching pages produced a question result")
    }

    /// A player opened and closed on the first step reports **nothing**: there is no position to save, and a request
    /// per curious tap is a request for nothing.
    @Test("closing a run that never started reports nothing")
    func closingAnUnstartedRunReportsNothing() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (learn, _) = try await Self.player(transport, lessonID: "u1l1")

        learn.closePlayer()
        await Self.settle()

        #expect(await transport.requestCount(for: Endpoint.learnProgress) == 0)
    }

    /// A **finished** run reports nothing either: the completion has already said everything the progress route
    /// would, and an interim report filed after it would be an older truth landing on a newer one.
    @Test("closing a finished run does not report progress after the completion")
    func aFinishedRunDoesNotReportProgress() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (learn, player) = try await Self.player(transport)

        try Self.finish(player)
        #expect(player.completion != nil)
        learn.closePlayer()
        await Self.settle()

        #expect(await transport.requestCount(for: Endpoint.learnProgress) == 0)
    }

    /// A progress report that lands **re-renders the map from its response** rather than reloading (ADR-0020): the
    /// route answers with the updated Learn screen, so nothing is asked twice.
    @Test("a progress report that lands re-renders the map from its own response")
    func progressRerendersTheMap() async throws {
        var stubs = try Self.stubs()
        // The same payload with `u1l3`'s ring one arc fuller, which is what an interim save produces.
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.learnInProgress)) as? [String: Any]
        )
        var lessons = try #require(payload["lessons"] as? [[String: Any]])
        for index in lessons.indices where lessons[index]["id"] as? String == "u1l3" {
            lessons[index]["filledSegments"] = 3
        }
        payload["lessons"] = lessons
        stubs[Endpoint.learnProgress] = .response(
            status: 200,
            body: try JSONSerialization.data(withJSONObject: payload)
        )

        let transport = FixtureTransport(stubs: stubs)
        let (learn, player) = try await Self.player(transport)
        #expect(learn.state.value?.allLessons.first { $0.id == "u1l3" }?.progress.filledSegments == 2)

        player.primaryAction()
        learn.closePlayer()
        await Self.settle()

        #expect(learn.state.value?.allLessons.first { $0.id == "u1l3" }?.progress.filledSegments == 3)
        #expect(await transport.requestCount(for: Endpoint.screenLearn) == 1, "the map reloaded instead of reading the response")
    }

    /// A progress report that **fails leaves the screen alone**: the reader has left the lesson, there is no queue
    /// (ADR-0019), and replacing a working map with an error over a best-effort save would be the app breaking a
    /// screen that is fine.
    @Test("a progress report that fails leaves the map alone and is not retried")
    func aFailedProgressReportIsSilent() async throws {
        var stubs = try Self.stubs()
        stubs[Endpoint.learnProgress] = .notConnected

        let transport = FixtureTransport(stubs: stubs)
        let (learn, player) = try await Self.player(transport)
        let before = learn.state

        player.primaryAction()
        learn.closePlayer()
        await Self.settle()

        #expect(learn.state == before)
        #expect(await transport.requestCount(for: Endpoint.learnProgress) == 1, "a best-effort save was retried")
    }

    // MARK: - Finishing the lesson

    /// **A finished run submits per-question results and nothing else** (invariant 10): which step, and whether it
    /// was right. No XP, no accuracy, no hearts — each is derivable from these, and a client that sent one would be
    /// a client the server had to trust.
    @Test("a finished run submits one result per question, naming its step")
    func theSubmissionCarriesTheResults() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (_, player) = try await Self.player(transport)

        try Self.finish(player)
        let completion = try #require(player.completion)
        try await completion.load()

        let request = try #require(
            await transport.recordedRequests.last { $0.path == Endpoint.lessonCompletion(lessonID: "u1l3") }
        )
        #expect(request.method == "POST")
        #expect(request.headers["Idempotency-Key"] != nil)

        let sent = try #require(request.body)
        let body = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        let results = try #require(body["results"] as? [[String: Any]])
        #expect(results.count == 4, "u1l3 has four questions in it")
        #expect(results.allSatisfy { $0["isCorrect"] as? Bool == true })
        #expect(results.compactMap { $0["stepIndex"] as? Int } == [4, 5, 6, 7])
        // The three figures the reader will read are asked for, not offered.
        for absent in ["xp", "accuracy", "hearts", "lessonId"] {
            #expect(!body.keys.contains(absent), "the submission carries \(absent)")
        }
    }

    /// **Every figure on the completion screen is read from the response.** The client held the results it
    /// submitted and could have divided them; ADR-0020 says it may not, and this is the screen where that matters
    /// most — it exists to tell the reader what they earned.
    @Test("the completion screen's figures come from the response")
    func theCompletionFiguresAreRead() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (_, player) = try await Self.player(transport)

        try Self.finish(player)
        let completion = try #require(player.completion)
        try await completion.load()

        let landed = try #require(completion.state.value)
        #expect(landed.isFirstCompletion)
        #expect(landed.xpEarned.display == "+50")
        #expect(landed.accuracy.display == "75%")
        #expect(landed.screen.streak.display == "5")
        #expect(landed.week.count == 7)
        // Every question was answered correctly above, so a client working the accuracy out itself would have
        // said 100% — which is what makes this assertion mean something.
        #expect(landed.accuracy.value == 75)
    }

    /// **The map re-renders from the completion's own response** (ADR-0020): the ring fills, the next lesson
    /// unlocks, and the stats bar moves without a second request.
    @Test("a completion re-renders the map behind the player from its own response")
    func aCompletionRerendersTheMap() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let (learn, player) = try await Self.player(transport)

        try Self.finish(player)
        let completion = try #require(player.completion)
        try await completion.load()

        let map = try #require(learn.state.value)
        #expect(map.progress.xp.display == "170")
        #expect(map.progress.streak.display == "5")
        #expect(map.allLessons.first { $0.id == "u1l3" }?.progress.state == .completed)
        #expect(map.allLessons.first { $0.id == "u2l1" }?.progress.state == .available)
        #expect(map.progress.nextLesson?.lessonID == "u2l1")
        #expect(await transport.requestCount(for: Endpoint.screenLearn) == 1, "the map reloaded instead of reading the response")
    }

    /// **A replay earns no XP** (defect D13). The design adds the run's points on every attempt, so an easy lesson
    /// farms them; here the response says zero and the total behind the player has not moved.
    @Test("a replay earns nothing and leaves the XP total where it was")
    func aReplayEarnsNothing() async throws {
        let transport = FixtureTransport(
            stubs: try Self.stubs(completing: "u1l1", with: .lessonRevisited)
        )
        let (learn, player) = try await Self.player(transport, lessonID: "u1l1")
        let before = try #require(learn.state.value).progress.xp.value

        try Self.finish(player)
        let completion = try #require(player.completion)
        try await completion.load()

        let landed = try #require(player.completion?.state.value)
        #expect(!landed.isFirstCompletion)
        #expect(landed.xpEarned.value == 0)
        #expect(landed.screen.xp.value == before)
        #expect(learn.state.value?.progress.xp.value == before)
    }

    /// **A completion with no connection is `LoadState.offline`, and nothing is queued** (ADR-0019). The retry is
    /// the reader's — the shared chrome's CTA — so the submission reaches the transport once and once only until
    /// they ask again.
    @Test("a completion with no connection is offline, and is not retried behind the user's back")
    func anOfflineCompletion() async throws {
        var stubs = try Self.stubs()
        stubs[Endpoint.lessonCompletion(lessonID: "u1l3")] = .notConnected

        let transport = FixtureTransport(stubs: stubs)
        let (learn, player) = try await Self.player(transport)

        try Self.finish(player)
        let completion = try #require(player.completion)
        try await completion.load()

        #expect(completion.state == .offline)
        #expect(completion.state.value == nil)
        #expect(await transport.requestCount(for: Endpoint.lessonCompletion(lessonID: "u1l3")) == 1)
        // Nothing was patched either: the map still says what the server last said about it.
        #expect(learn.state.value?.progress.xp.display == "120")

        // And a moment later it is still one request — there is no queue and no drain (ADR-0019).
        await Self.settle()
        #expect(await transport.requestCount(for: Endpoint.lessonCompletion(lessonID: "u1l3")) == 1)
    }

    /// **The retry re-sends the same submission with the same key.** Finishing a lesson happens once, so a write
    /// that reached the server and lost its response has to be recognised rather than counted twice (ADR-0022).
    @Test("the retry re-sends the same body under the same idempotency key")
    func theRetryReusesTheKey() async throws {
        let transport = FixtureTransport(
            // A sequence rather than two stubs: the first attempt finds no network and the second is answered,
            // which is the shape a reader pressing **Try again** produces.
            sequences: [Endpoint.lessonCompletion(lessonID: "u1l3"): [.notConnected, try .ok(.lessonCompleted)]],
            stubs: try Self.stubs()
        )

        let (_, player) = try await Self.player(transport)
        try Self.finish(player)
        let completion = try #require(player.completion)

        try await completion.load()
        #expect(completion.state == .offline)
        try await completion.load()
        #expect(completion.state.value != nil)

        let submissions = await transport.recordedRequests.filter {
            $0.path == Endpoint.lessonCompletion(lessonID: "u1l3")
        }
        #expect(submissions.count == 2)
        #expect(submissions[0].headers["Idempotency-Key"] == submissions[1].headers["Idempotency-Key"])
        // Decoded rather than compared as bytes: `JSONEncoder` does not promise a key order, so two encodes of one
        // value are the same submission and not necessarily the same 145 bytes.
        let first = try JSONDecoder().decode(SubmittedResults.self, from: try #require(submissions[0].body))
        let second = try JSONDecoder().decode(SubmittedResults.self, from: try #require(submissions[1].body))
        #expect(first == second)
        #expect(first.results.count == 4)
    }

    /// **A `422` is a definite failure.** The server refuses an impossible submission — a lesson whose predecessor
    /// is unfinished, a result naming a step that is not a question — and there is nothing for the client to
    /// correct, so it renders as failed rather than as offline and rather than as a form error.
    @Test("a 422 renders a definite failure")
    func aRefusedSubmission() async throws {
        var stubs = try Self.stubs()
        stubs[Endpoint.lessonCompletion(lessonID: "u1l3")] = .response(
            status: 422,
            body: Data(#"{"error":{"code":"VALIDATION_FAILED"}}"#.utf8)
        )

        let (learn, player) = try await Self.player(FixtureTransport(stubs: stubs))

        try Self.finish(player)
        let completion = try #require(player.completion)
        try await completion.load()

        #expect(completion.state.isFailed)
        #expect(!completion.state.isOffline, "a refusal was drawn as a connection problem")
        #expect(completion.state.value == nil)
        #expect(learn.state.value?.progress.xp.display == "120", "a refused submission moved the total")
    }

    /// A `501` — what every unwritten route answers with — is a failure too, which is the state this screen was
    /// built against.
    @Test("a 501 from the completion route is a failed state")
    func aNotImplementedCompletion() async throws {
        var stubs = try Self.stubs()
        stubs[Endpoint.lessonCompletion(lessonID: "u1l3")] = .response(status: 501, body: Data())

        let (_, player) = try await Self.player(FixtureTransport(stubs: stubs))
        try Self.finish(player)
        let completion = try #require(player.completion)

        try await completion.load()

        #expect(completion.state.isFailed)
    }

    /// The completion is built **once**, so finishing a lesson cannot submit twice however many times the screen
    /// re-renders.
    @Test("finishing builds one completion")
    func oneCompletionPerRun() async throws {
        let (_, player) = try await Self.player(FixtureTransport(stubs: try Self.stubs()))

        try Self.finish(player)
        let first = try #require(player.completion)
        player.primaryAction()

        #expect(player.completion === first)
    }

    /// Lets an unstructured `Task` — the progress report's — run to completion before the assertion reads the
    /// transport. Yielding rather than sleeping: the work is a single `await` on a fixture, so there is nothing to
    /// wait *for* beyond giving the actor a turn.
    /// `LessonResults` read back from the wire — the reading half of a write-only type, so that "the retry sent the
    /// same submission" is a claim about a value rather than about a byte count.
    private struct SubmittedResults: Decodable, Equatable {
        struct Result: Decodable, Equatable {
            let stepIndex: Int
            let isCorrect: Bool
        }

        let results: [Result]
    }

    private static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}
