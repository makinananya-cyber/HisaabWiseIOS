import Foundation

/// `GET /v1/screens/learn` — everything about *this reader's* way through the curriculum, **fully computed**
/// (ADR-0020).
///
/// **It carries no lesson titles, and that is the decision worth reading.** Learn is the one screen that reads
/// two endpoints, because the two halves of it have opposite cache rules: the curriculum is the same 100 KB for
/// everybody and is stored with an ETag (``Curriculum``, invariant 8), while progress through it is per-user and
/// must bypass every cache. Folding the titles in here would make editorial content per-user; folding the
/// progress into the curriculum would make a cacheable response describe one reader. So the screen joins them
/// **by lesson id**, which is a lookup and not a calculation — every figure on either side arrived computed.
///
/// **Read the field names as the list of things the design worked out in the browser.** `isOpen(id)` walked a
/// flattened array asking whether the previous lesson was done; `firstOpen()` scanned for the cursor;
/// `unitOpen` reduced over a unit's lessons; `qCount(l)` counted the questions in one. All four are here as
/// values, because a lock, an ordering, and a count are each a calculation (ADR-0020) — and because the client
/// renders the lock while the **server enforces** it, so the two must be the same answer.
///
/// **Both figures arrive three ways**, which is `Money`'s shape rather than duplication — see ``Stat``.
///
/// **The streak is the server's, and there is nothing here to derive one from.** Invariant 6 puts the day
/// boundary in the user's stored timezone, server-side; the design kept `lastActive: dayKey(-1)` and compared
/// it against `new Date()`, so moving the device clock moved the streak. This payload carries no date, no
/// timestamp, and no day key — the stronger form of the fix, the same one `ExpensesScreen` applies to its entry
/// labels: the client could not re-derive the streak if it wanted to.
struct LearnScreen: Sendable, Hashable, Decodable {
    /// The `.stat--streak` pill: days, counted against the server-owned day boundary.
    ///
    /// Its ``Stat/value`` is the same figure `HomeScreen.Learning.streak` carries, from the same source — so the
    /// streak Home shows and the streak Learn shows cannot disagree, and `FixtureCorpusTests` asserts it.
    let streak: Stat

    /// The `.stat--xp` pill: experience points.
    let xp: Stat

    /// One figure in a stats pill: the number, the string that is drawn, and the sentence that is read.
    ///
    /// **Three fields for one figure, and each has a caller the other two cannot serve.** This is `Money`'s shape
    /// applied to something that is not money, for `Money`'s reason (ADR-0003): the client has no formatter, so a
    /// four-digit XP total needs its thousands separator from the server, and a count with a plural in it — "4-day
    /// streak", six forms in Arabic — needs the whole sentence from the server (ADR-0011). ``value`` is drawn by
    /// nothing: it is what makes "Home and Learn agree about the streak" a numeric assertion rather than a
    /// comparison of two formatted strings that could each be wrong in the same way.
    struct Stat: Sendable, Hashable, Decodable {
        /// The raw figure. **Not drawn** — see above.
        let value: Int

        /// "4" · "1,500" — the pill's own text, formatted server-side.
        let display: String

        /// "4-day streak" · "1,500 experience points" — the whole of what VoiceOver reads for the pill. The design
        /// leans on a `title` attribute for this, which touch never surfaces.
        let accessibilityLabel: String
    }

    /// Where the **START** badge goes, or `nil` once every lesson is finished.
    ///
    /// The design's `firstOpen()` — the first lesson that is open and not done — and **selection is an
    /// ordering**, so the server names it. `nil` is a real state and a good one: a reader who has finished the
    /// curriculum should not be pointed at a sixteenth lesson.
    let nextLesson: NextLesson?

    /// One entry per unit in the curriculum, keyed by unit id.
    let units: [UnitProgress]

    /// One entry per lesson in the curriculum, keyed by lesson id.
    let lessons: [LessonProgress]

    // MARK: - Where to go next

    /// The lesson the **START** badge sits on, and the one **Continue** on Home opens.
    struct NextLesson: Sendable, Hashable, Decodable {
        /// Which unit it is in, so the screen can scroll to it without searching the curriculum for its parent.
        let unitID: String
        let lessonID: String

        /// Its title, so Home's mini-card and this screen's own announcement read the same words without the
        /// curriculum in hand. It duplicates ``Curriculum/Unit/Lesson/title`` on purpose: `HomeScreen` carries
        /// the same string for the same reason, and Home does not fetch the curriculum at all.
        let title: String

        private enum CodingKeys: String, CodingKey {
            case unitID = "unitId"
            case lessonID = "lessonId"
            case title
        }
    }

    // MARK: - A unit's state

    /// Whether a unit has been reached.
    ///
    /// **The server's answer, not `lessons.contains { $0.isOpen }`.** The design reduced over the unit's
    /// lessons; doing that here would mean the client and the server each deciding what "reached" means, which
    /// is the two-owners shape defect D11 was. It also stops being a reduction the moment the rule changes —
    /// a unit gated on the one before it being *finished* is a different rule with the same lesson states.
    struct UnitProgress: Sendable, Hashable, Decodable, Identifiable {
        let id: String
        let isUnlocked: Bool
    }

    // MARK: - A lesson's state

    /// One `.node` on the path: whether it is open, and how much of it is done.
    struct LessonProgress: Sendable, Hashable, Decodable, Identifiable {
        let id: String

        let state: LessonState

        /// How many arcs the ring is drawn in — the lesson's question count.
        ///
        /// **Geometry, and a count the client is not allowed to work out.** The design calls
        /// `qCount(l) = l.steps.filter(s => s.t === 'q').length`, and the client *could* do the same against the
        /// curriculum it already holds — which is exactly why this is here. A count is a calculation (ADR-0020),
        /// and a ring whose segments came from one response while its filled arcs came from another is a ring
        /// with two owners. `FixtureCorpusTests.theCorpusAgreesAboutRingSegments` asserts the corpus's two halves
        /// agree, so a payload that disagreed with its own curriculum would fail rather than draw a ring that is
        /// quietly one arc short.
        ///
        /// An `Int` rather than a fraction, so no new `Double` joins the three geometry exemptions
        /// `MoneyFormattingAbsenceTests` names — the ring is segmented, so the two counts *are* the geometry.
        let segments: Int

        /// How many of those arcs are lit: the design's `done ? segs : (state.progress[id] || 0)`.
        ///
        /// Which is why a **completed** lesson does not need special-casing here — the server fills every arc,
        /// so the ring and the tick agree by construction rather than because the view remembered to.
        let filledSegments: Int

        /// "2 of 5 questions answered" · "Completed" · "Locked" — what VoiceOver reads for the node.
        ///
        /// Server-composed, for ``Stat/accessibilityLabel``'s reason: it is a count and a plural, and the
        /// alternative is the client assembling a sentence out of two numbers (ADR-0011).
        let progressLabel: String

        /// Whether the node can be pressed. `completed` is pressable — the design lets a reader run a finished
        /// lesson again, and the "out of hearts" dialog offers exactly that.
        var isOpen: Bool { state != .locked }
    }

    /// The three states a lesson node is drawn in — the design's `done` / `current` / `locked`.
    ///
    /// **It refuses to guess, and this is the enum on this screen that has to.** ``Curriculum/Accent`` and
    /// ``Curriculum/Unit/Icon`` degrade to a default because they are presentation: a unit in the wrong tint is
    /// a blemish. This decides whether the reader can open a lesson, and **both fallbacks are wrong in a way the
    /// reader cannot get out of** — guessing `locked` strands them in front of a lesson they have earned with no
    /// way to ask again, and guessing `available` offers one the server will refuse. So an unrecognised state
    /// fails the decode and the screen renders `LoadState.failed`, which is honest and has a retry on it. A
    /// fourth state is a coordinated release, exactly as `ExpensesScreen.Kind` is.
    enum LessonState: String, Sendable, Hashable, Decodable, CaseIterable {
        /// Every question answered right at least once. The `.node.done` tick.
        case completed
        /// Open, and not finished. Includes a lesson with partial progress in its ring.
        case available
        /// The lesson before it is not finished. The padlock, and the node is not pressable.
        case locked
    }
}

extension LearnScreen {
    /// One lesson's state by id, or `nil` for a lesson this payload says nothing about.
    ///
    /// **The join, and it is deliberately fallible.** A curriculum that has gained a lesson since the screen
    /// payload was assembled will have one the payload does not mention; drawing nothing for it is better than
    /// inventing a state, and better than failing a screen that is otherwise perfectly good. What the view does
    /// with `nil` is skip the node — see `LearnView`.
    func lesson(id: String) -> LessonProgress? {
        lessons.first { $0.id == id }
    }

    /// One unit's state by id, or `nil`.
    func unit(id: String) -> UnitProgress? {
        units.first { $0.id == id }
    }

    /// Whether this is the lesson the **START** badge sits on.
    func isNext(_ lessonID: String) -> Bool {
        nextLesson?.lessonID == lessonID
    }
}
