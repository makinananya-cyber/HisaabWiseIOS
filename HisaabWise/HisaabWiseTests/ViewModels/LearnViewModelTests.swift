import Foundation
@testable import HisaabWise
import Testing

/// Learn reads **two endpoints and joins them by id**, and derives nothing from either (ADR-0020, ADR-0034).
///
/// Three of the four claims the ticket asks for are sections below: the sequential unlock rendering, that a
/// device-clock change cannot move the streak, and that the curriculum survives a cold launch with no network
/// after one successful fetch. The fourth — the exact content counts — is `CurriculumTests`, because it is a
/// property of the corpus rather than of this object.
///
/// **The `LoadState` mapping is not asserted here.** It lives in ``BaseViewModel/load()`` and is asserted in
/// `BaseViewModelTests` — one owner, one suite. What is asserted here is what this object adds: the join, the
/// refusal, and the sheet.
@Suite("LearnViewModel")
@MainActor
struct LearnViewModelTests {
    private static func stubs(
        _ screen: Fixture = .learnInProgress
    ) throws -> [String: FixtureTransport.Outcome] {
        [
            Endpoint.screenLearn: try .ok(screen),
            Endpoint.curriculum: try .ok(.curriculum, etag: "\"v1\""),
        ]
    }

    private static func makeViewModel(
        _ transport: FixtureTransport,
        store: any ContentStore = InMemoryContentStore()
    ) -> LearnViewModel {
        let client = TestBench.client(transport)
        return LearnViewModel(client: client, content: ContentLoader(client: client, store: store))
    }

    private static func loaded(
        _ transport: FixtureTransport
    ) async throws -> (LearnViewModel, LearnMap) {
        let viewModel = makeViewModel(transport)
        try await viewModel.load()
        return (viewModel, try #require(viewModel.state.value))
    }

    @Test("starts loading, before anything has been asked for")
    func startsLoading() {
        #expect(Self.makeViewModel(FixtureTransport()).state == .loading)
    }

    // MARK: - Two reads, and only two

    /// **The two requests, asserted as a count.** One per cache rule (invariant 8) and no more: a screen that
    /// fetched a lesson at a time would be fifteen round trips for one map.
    @Test("asks for the curriculum and the screen once each, and asks for nothing else")
    func asksForBothOnce() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let viewModel = Self.makeViewModel(transport)

        try await viewModel.load()

        #expect(await transport.requestCount(for: Endpoint.curriculum) == 1)
        #expect(await transport.requestCount(for: Endpoint.screenLearn) == 1)
        #expect(await transport.recordedRequests.count == 2)
    }

    /// The cacheable half is fetched **anonymously** and the per-user half asks with a session — which is
    /// invariant 8 as a property of two requests rather than as a sentence in a document. A curriculum carrying an
    /// `Authorization` header would be a response a shared cache could key wrongly, and a per-user response served
    /// out of one is the breach the invariant is about.
    ///
    /// The per-request bypass is `APIClient`'s and applies to both, which is why it is asserted of both rather than
    /// only of the screen: the curriculum is stored by `ContentLoader` with an ETag of its own, deliberately, and
    /// not by `URLCache` — `URLSessionTransport` keeps none at all.
    @Test("the curriculum is anonymous, the screen payload is not, and neither is left to a URL cache")
    func theTwoHalvesHaveOppositeCacheRules() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        _ = try await Self.loaded(transport)

        let requests = await transport.recordedRequests
        let curriculum = try #require(requests.first { $0.path == Endpoint.curriculum })
        let screen = try #require(requests.first { $0.path == Endpoint.screenLearn })

        #expect(curriculum.headers["Authorization"] == nil)
        #expect(curriculum.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(screen.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    /// Either half failing fails the screen, and **offline is offline rather than a fault** — the taxonomy's rule,
    /// exercised through both halves because a screen that only checked one would pass with the other unhandled.
    @Test("either half failing takes the screen with it", arguments: [Endpoint.curriculum, Endpoint.screenLearn])
    func eitherHalfFailingFailsTheScreen(_ failing: String) async throws {
        var stubs = try Self.stubs()
        stubs[failing] = .notConnected
        let viewModel = Self.makeViewModel(FixtureTransport(stubs: stubs))

        try await viewModel.load()

        #expect(viewModel.state == .offline)
        #expect(viewModel.state.value == nil)
    }

    /// A `501` — what every screen endpoint answers with until the backend has written it — is a **failure** and
    /// not an absence, which is the state this screen was built against.
    @Test("a 501 from the screen endpoint is a failed state")
    func aNotImplementedScreenIsFailed() async throws {
        var stubs = try Self.stubs()
        stubs[Endpoint.screenLearn] = .response(status: 501, body: Data())
        let viewModel = Self.makeViewModel(FixtureTransport(stubs: stubs))

        try await viewModel.load()

        #expect(viewModel.state.isFailed)
    }

    // MARK: - Sequential unlocking

    /// **The unlock rule, rendered.** Lesson 1 is open because nothing precedes it; every lesson after the last
    /// completed one is locked; exactly one is the cursor.
    ///
    /// Asserted against the *flattened* order, because that is what "the lesson before it" means — the design's
    /// own `FLAT` array — and the payload is the only thing that says so. The client reads the sequence; it does
    /// not compute it, which is why this test states what the map *drew* rather than what it worked out.
    @Test("the map renders the payload's unlock sequence: two done, one open, twelve locked")
    func theUnlockSequenceIsRendered() async throws {
        let (_, map) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))
        let lessons = map.allLessons

        #expect(lessons.count == 15)
        #expect(lessons.filter { $0.progress.state == .completed }.count == 2)
        #expect(lessons.filter { $0.progress.state == .available }.count == 1)
        #expect(lessons.filter { $0.progress.state == .locked }.count == 12)

        // And the shape of it: everything after the open one is shut, in order.
        let states = lessons.map(\.progress.state)
        #expect(states.prefix(2).allSatisfy { $0 == .completed })
        #expect(states[2] == .available)
        #expect(states.dropFirst(3).allSatisfy { $0 == .locked })
    }

    /// **The first lesson is open with nothing completed at all** — the one arrangement where "the lesson before
    /// it" has no lesson before it, and the case the design writes as `i === 0 || isDone(prev)`.
    @Test("a brand-new account has exactly one lesson open, and it is the first")
    func theFirstLessonIsAlwaysOpen() async throws {
        let (_, map) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs(.learnFirstRun)))
        let lessons = map.allLessons

        #expect(lessons.first?.progress.state == .available)
        #expect(lessons.first?.isNext == true)
        #expect(lessons.dropFirst().allSatisfy { $0.progress.state == .locked })
        #expect(lessons.filter(\.isOpen).count == 1)
    }

    /// A finished curriculum has **no cursor**, and a screen that assumed one would draw a badge on nothing or
    /// crash reaching for it. Absent rather than pointing at a sixteenth lesson.
    @Test("a finished curriculum has every lesson open and no START badge")
    func aFinishedCurriculumHasNoCursor() async throws {
        let (_, map) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs(.learnComplete)))
        let states = map.allLessons.map(\.progress.state)

        #expect(map.progress.nextLesson == nil)
        #expect(states == Array(repeating: .completed, count: 15))
        #expect(map.allLessons.filter(\.isOpen).count == 15)
        #expect(map.allLessons.filter(\.isNext).isEmpty)
        #expect(map.units.filter(\.isUnlocked).count == 5)
    }

    /// **At most one cursor on the whole map**, because the server names exactly one — a client that scanned for
    /// "the first open, unfinished lesson" would be doing the ordering itself (ADR-0020).
    @Test("exactly one lesson carries the START badge, and it is the one the payload names")
    func exactlyOneLessonIsNext() async throws {
        let (_, map) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        let next = map.allLessons.filter(\.isNext)
        #expect(next.count == 1)
        #expect(next.first?.id == map.progress.nextLesson?.lessonID)
        #expect(next.first?.content.title == map.progress.nextLesson?.title)
    }

    /// **A unit's lock is the payload's, not a reduction over its lessons.** Asserted against a payload whose unit
    /// flags *disagree* with its lessons: the design computed `u.lessons.some(isOpen)`, and a client still doing
    /// that would draw the unit as reached. The screen draws what the server said (ADR-0020, invariant 3's shape).
    @Test("a unit's lock is read, not reduced over its lessons")
    func aUnitLockIsRead() async throws {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.learnInProgress)) as? [String: Any]
        )
        var units = try #require(payload["units"] as? [[String: Any]])
        // Unit 1 has two finished lessons in it, and the server says it is shut. A reduction would say otherwise.
        units[0]["isUnlocked"] = false
        payload["units"] = units

        var stubs = try Self.stubs()
        stubs[Endpoint.screenLearn] = .response(
            status: 200,
            body: try JSONSerialization.data(withJSONObject: payload)
        )
        let (_, map) = try await Self.loaded(FixtureTransport(stubs: stubs))

        #expect(map.units.first?.isUnlocked == false)
        #expect(map.units.first?.lessons.contains { $0.progress.state == .completed } == true)
    }

    /// **The ring's two counts are read, not counted.** A client that counted the curriculum's own question steps
    /// would be right against a consistent payload and wrong here — which is the only way to tell the two apart,
    /// and the same trick `ExpensesViewModelTests` plays with a per-category total.
    @Test("a ring is drawn from the payload's counts even when they disagree with the curriculum")
    func theRingCountsAreRead() async throws {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.learnInProgress)) as? [String: Any]
        )
        var lessons = try #require(payload["lessons"] as? [[String: Any]])
        lessons[0]["segments"] = 9
        lessons[0]["filledSegments"] = 7
        payload["lessons"] = lessons

        var stubs = try Self.stubs()
        stubs[Endpoint.screenLearn] = .response(
            status: 200,
            body: try JSONSerialization.data(withJSONObject: payload)
        )
        let (_, map) = try await Self.loaded(FixtureTransport(stubs: stubs))

        let first = try #require(map.allLessons.first)
        #expect(first.progress.segments == 9)
        #expect(first.progress.filledSegments == 7)
        // And the curriculum disagrees, which is what makes the assertion above mean something.
        #expect(first.content.questionCount == 4)
    }

    /// **An unrecognised lesson state fails the decode**, which is ``LearnScreen/LessonState``'s decision: both
    /// fallbacks are wrong in a way the reader cannot get out of, so a fourth state is a coordinated release.
    @Test("an unrecognised lesson state fails the screen rather than being guessed at")
    func anUnknownLessonStateFails() async throws {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.learnInProgress)) as? [String: Any]
        )
        var lessons = try #require(payload["lessons"] as? [[String: Any]])
        lessons[0]["state"] = "inReview"
        payload["lessons"] = lessons

        var stubs = try Self.stubs()
        stubs[Endpoint.screenLearn] = .response(
            status: 200,
            body: try JSONSerialization.data(withJSONObject: payload)
        )
        let viewModel = Self.makeViewModel(FixtureTransport(stubs: stubs))

        try await viewModel.load()

        #expect(viewModel.state.value == nil)
        #expect(viewModel.state.isFailed)
    }

    // MARK: - The join

    /// The whole map joins by id, and the corpus's two halves agree — every lesson in the curriculum has a state
    /// and no state is orphaned.
    @Test("every lesson in the curriculum is joined to a state, and none is left over")
    func theJoinIsComplete() async throws {
        let (_, map) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))
        let curriculum = try Fixture.curriculum.decode(Curriculum.self)

        #expect(map.allLessons.map(\.id) == curriculum.allLessons.map(\.id))
        #expect(map.units.map(\.id) == curriculum.units.map(\.id))
    }

    /// **A lesson the payload says nothing about is skipped** — not invented, and not fatal (``LearnMap``). The
    /// transitional window is a curriculum deployed ahead of the screen assembly; dropping one node beats
    /// rendering a lock the server did not send or failing fourteen good ones.
    @Test("a lesson with no state is left off the map rather than guessed at or fatal")
    func aLessonWithNoStateIsSkipped() async throws {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.learnInProgress)) as? [String: Any]
        )
        var lessons = try #require(payload["lessons"] as? [[String: Any]])
        let dropped = try #require(lessons.removeLast()["id"] as? String)
        payload["lessons"] = lessons

        var stubs = try Self.stubs()
        stubs[Endpoint.screenLearn] = .response(
            status: 200,
            body: try JSONSerialization.data(withJSONObject: payload)
        )
        let (_, map) = try await Self.loaded(FixtureTransport(stubs: stubs))

        #expect(map.allLessons.count == 14)
        #expect(!map.allLessons.contains { $0.id == dropped })
        // And the unit it belonged to is still drawn, because it has other lessons in it.
        #expect(map.units.count == 5)
    }

    /// A curriculum with no units at all is `.empty` rather than `.loaded` — a stats bar over white space looks
    /// broken in a way the empty state does not.
    @Test("a curriculum with no units renders as empty")
    func anEmptyCurriculumIsEmpty() async throws {
        var stubs = try Self.stubs()
        stubs[Endpoint.curriculum] = .response(status: 200, body: Data(#"{"units":[]}"#.utf8))
        let viewModel = Self.makeViewModel(FixtureTransport(stubs: stubs))

        try await viewModel.load()

        #expect(viewModel.state == .empty)
    }

    // MARK: - The streak, and the clock

    /// **A device-clock change does not move the streak** (invariant 6).
    ///
    /// It is asserted as an **absence**, because that is the whole of the fix and the only form a test can take:
    /// the payload carries no date, no timestamp, and no day key, so there is nothing on the client from which a
    /// streak could be re-derived — and no clock is read to compare one against. A test that moved a clock and
    /// checked the number had not changed would be asserting that a number the client copies is a number the
    /// client copies.
    ///
    /// The same reasoning `ExpensesScreen`'s date labels use, and the same shape of test: the design kept
    /// `lastActive: dayKey(-1)` and diffed it against `new Date()`, which is exactly what is now unrepresentable.
    ///
    /// **The literal form — move the clock and reload — is deliberately not written**, and the reason is not
    /// squeamishness. The only process-wide lever is `NSTimeZone.default`, and three suites here assert that a
    /// request body's `timeZone` equals `TimeZone.current.identifier` *at assertion time*
    /// (`SessionCoordinatorTests`, `SessionTests`, `RegistrationViewModelTests`). Swift Testing runs suites in
    /// parallel, so mutating it would make those three flaky — a test that breaks other tests to assert an absence
    /// is a worse deal than asserting the absence directly.
    @Test("nothing in Learn's payload or its view model can read a clock")
    func theStreakCannotBeReDerived() throws {
        for path in [
            "Models/LearnScreen.swift",
            "Models/LearnMap.swift",
            "Models/Curriculum.swift",
            "ViewModels/LearnViewModel.swift",
            "Views/LearnView.swift",
        ] {
            let code = try SourceTree.codeLines(of: SourceTree.appSources.appending(path: path))
            for symbol in ["Date(", "Date.now", "Calendar", "DateComponents", "timeIntervalSince", "dayKey"] {
                #expect(
                    code.first { $0.contains(symbol) } == nil,
                    "\(path) references \(symbol) — the streak's day boundary is the server's (invariant 6)"
                )
            }
        }
    }

    /// And the payload itself carries nothing to derive one from. Read out of the **JSON** rather than the model,
    /// because the model not having a field is the consequence — the claim is about the wire.
    @Test("the screen payload carries no date, timestamp, or day key")
    func thePayloadCarriesNoDate() throws {
        for fixture in [Fixture.learnInProgress, .learnFirstRun, .learnComplete] {
            let json = String(decoding: TestBench.payload(fixture), as: UTF8.self)
            for field in ["date", "Date", "timestamp", "dayKey", "lastActive", "updatedAt"] {
                #expect(!json.contains(field), "\(fixture.rawValue) carries \(field)")
            }
        }
    }

    /// The streak and the XP are **copied through**, and the figure the reader sees is the server's string rather
    /// than a client-spelled `Int`. `Stat.value` is drawn by nothing; it exists so the corpus can assert agreement
    /// numerically.
    @Test("the streak and the XP reach the screen exactly as the payload spelled them")
    func theStatsAreCopiedThrough() async throws {
        let (_, map) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        #expect(map.progress.streak.value == 4)
        #expect(map.progress.streak.display == "4")
        #expect(map.progress.streak.accessibilityLabel == "4-day streak")
        #expect(map.progress.xp.value == 120)
        #expect(map.progress.xp.display == "120")

        // A four-digit total arrives with its separator already in it, because the client has none to add.
        let (_, finished) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs(.learnComplete)))
        #expect(finished.progress.xp.value == 1500)
        #expect(finished.progress.xp.display == "1,500")
    }

    // MARK: - The curriculum survives a cold launch

    /// **After one successful fetch, a cold launch with no network still has the curriculum** (ADR-0009, as
    /// amended by ADR-0019 — for latency and data use, not to make the app usable offline).
    ///
    /// A *cold launch* is modelled as what it is: a **new** loader and a new view model over the same store, with
    /// a transport that answers nothing. The store is the only thing that crosses, which is the claim.
    ///
    /// The screen is `.offline` on the second launch, and that is correct rather than a shortfall: progress is
    /// per-user and there is no offline read of it (ADR-0019). What the store buys is that the *content* half does
    /// not have to be downloaded again — so the assertion is about the loader, which is where the guarantee lives.
    @Test("the curriculum survives a cold launch with no network, after one successful fetch")
    func theCurriculumSurvivesAColdLaunch() async throws {
        let store = InMemoryContentStore()

        // Launch one: online, and the bytes and their ETag land in the store.
        let first = Self.makeViewModel(FixtureTransport(stubs: try Self.stubs()), store: store)
        try await first.load()
        #expect(first.state.value?.units.count == 5)
        #expect(try await store.data(for: .curriculum) == TestBench.payload(.curriculum))
        #expect(try await store.etag(for: .curriculum) == "\"v1\"")

        // Launch two: a fresh object graph over the same store, and nothing answering.
        let offline = FixtureTransport(stubs: [
            Endpoint.curriculum: .notConnected,
            Endpoint.screenLearn: .notConnected,
        ])
        let client = TestBench.client(offline)
        let loader = ContentLoader(client: client, store: store)

        let curriculum = try await loader.load(.curriculum, as: Curriculum.self)

        #expect(curriculum.units.count == 5)
        #expect(curriculum.allLessons.count == 15)
        #expect(curriculum.lesson(id: "u1l1")?.title == "Gross vs. Net Income")

        // And the screen half is honestly offline, which is the other side of the same rule.
        let second = LearnViewModel(client: client, content: loader)
        try await second.load()
        #expect(second.state == .offline)
    }

    /// The second launch **revalidates** rather than trusting the store blindly: a `304` is what the ETag buys, and
    /// a loader that skipped the request would never notice an editor changing a lesson.
    @Test("a second launch revalidates with the stored ETag and reads a 304 from the store")
    func aSecondLaunchRevalidates() async throws {
        let store = InMemoryContentStore()
        let transport = FixtureTransport(sequences: [
            Endpoint.curriculum: [try .ok(.curriculum, etag: "\"v1\""), .notModified],
        ], stubs: [
            Endpoint.screenLearn: try .ok(.learnInProgress),
        ])

        let first = Self.makeViewModel(transport, store: store)
        try await first.load()
        let second = Self.makeViewModel(transport, store: store)
        try await second.load()

        #expect(second.state.value?.units.count == 5)
        #expect(await transport.requestCount(for: Endpoint.curriculum) == 2)
        let revalidation = try #require(
            await transport.recordedRequests.last { $0.path == Endpoint.curriculum }
        )
        #expect(revalidation.headers["If-None-Match"] == "\"v1\"")
    }

    // MARK: - What the reader does

    /// **Pressing a locked lesson says why**, which is the design's own behaviour, and nothing else happens: the
    /// client renders the lock and the server enforces it, so a refusal here costs nothing if the two disagree.
    @Test("pressing a locked lesson raises a notice and changes no state")
    func aLockedLessonRefuses() async throws {
        let (viewModel, map) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))
        let before = viewModel.state

        #expect(viewModel.notice == nil)
        viewModel.refuseLockedLesson()

        #expect(viewModel.notice == .lessonLocked)
        #expect(viewModel.state == before, "a refusal reloaded or replaced the screen")
        #expect(map.allLessons.filter { $0.progress.state == .locked }.count == 12)

        viewModel.dismissNotice()
        #expect(viewModel.notice == nil)
    }

    /// The guide sheet holds an **id** and re-reads the unit, so a reload underneath it re-renders the sheet from
    /// the new payload rather than from the unit it was opened with (ADR-0020).
    @Test("the guide sheet holds an id and re-reads its unit from the current payload")
    func theGuideSheetReReadsItsUnit() async throws {
        let (viewModel, _) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        #expect(viewModel.openGuideUnit == nil)

        viewModel.openGuide(unitID: "u3")
        #expect(viewModel.openGuideUnit?.id == "u3")
        #expect(viewModel.openGuideUnit?.content.title == "Master Borrowing")
        #expect(viewModel.openGuideUnit?.lessons.count == 3)

        viewModel.closeGuide()
        #expect(viewModel.openGuideUnit == nil)
    }

    /// Opening a sheet hushes a toast, as the design's `hushToast()` does: the panel covers it, and a toast left
    /// behind reappears from under a sheet the reader has just dismissed.
    @Test("opening the guide clears a pending notice")
    func openingTheGuideHushesTheToast() async throws {
        let (viewModel, _) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        viewModel.refuseLockedLesson()
        #expect(viewModel.notice != nil)

        viewModel.openGuide(unitID: "u1")

        #expect(viewModel.notice == nil)
    }

    /// A unit id nothing carries opens no sheet, rather than an empty one.
    @Test("a unit id the payload does not carry opens nothing")
    func anUnknownUnitOpensNothing() async throws {
        let (viewModel, _) = try await Self.loaded(FixtureTransport(stubs: try Self.stubs()))

        viewModel.openGuide(unitID: "u9")

        #expect(viewModel.openGuideUnit == nil)
    }

    /// **Presentation follows the id, not the resolved unit** — the bug review found. A sheet presented off
    /// `openGuideUnit` goes hidden when a reload drops that unit, without any dismissal writing through, so the id
    /// stays set and the sheet re-presents itself the moment the unit comes back.
    ///
    /// The two properties are asserted to *disagree* in exactly that state, which is what makes them two properties
    /// rather than one: the screen stays presented and closes itself, instead of silently re-arming.
    @Test("a reload that drops the open unit leaves the sheet presented and closable, not re-arming")
    func theSheetFollowsTheIDRatherThanTheUnit() async throws {
        let full = try Self.stubs()
        var trimmed = full
        // The same payload with unit 5's lessons removed, which is what makes `LearnMap` drop the unit.
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.learnInProgress)) as? [String: Any]
        )
        let lessons = try #require(payload["lessons"] as? [[String: Any]])
        payload["lessons"] = lessons.filter { !(($0["id"] as? String) ?? "").hasPrefix("u5") }
        trimmed[Endpoint.screenLearn] = .response(
            status: 200,
            body: try JSONSerialization.data(withJSONObject: payload)
        )

        let viewModel = Self.makeViewModel(FixtureTransport(stubs: full))
        try await viewModel.load()
        viewModel.openGuide(unitID: "u5")
        #expect(viewModel.isShowingGuide)
        #expect(viewModel.openGuideUnit?.id == "u5")

        // The reload, over a payload that no longer mentions unit 5.
        let reloaded = Self.makeViewModel(FixtureTransport(stubs: trimmed))
        try await reloaded.load()
        reloaded.openGuide(unitID: "u5")

        #expect(reloaded.state.value?.units.count == 4, "unit 5 is still on the map")
        #expect(reloaded.openGuideUnit == nil)
        #expect(reloaded.isShowingGuide, "presentation followed the unit rather than the id")

        reloaded.closeGuide()
        #expect(!reloaded.isShowingGuide)
    }
}
