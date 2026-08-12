import Foundation

/// `GET /v1/curriculum` — the five units, the fifteen lessons, and the 124 steps inside them.
///
/// **Cacheable, and that is why it is not part of Learn's screen payload** (invariant 8, ADR-0009). The
/// curriculum is the same bytes for every reader; the *progress through it* is per-user and must bypass every
/// cache. So Learn reads two things — this, with an ETag, and ``LearnScreen``, which never touches a cache —
/// and joins them by lesson id. That join is a **lookup**, not a calculation: nothing on the screen is worked
/// out from it, and every figure in the join's per-user half arrived computed (ADR-0020, ADR-0034).
///
/// **The rationale for storing it changed and the storage did not.** ADR-0009 kept the curriculum on disk so
/// the app would work without a connection; ADR-0019 took that job away and gave it to the server-generated
/// PDF (#25). What is left is latency and data use — 100 KB is not worth downloading twice — which is a smaller
/// claim and still a good one.
///
/// **The counts are the acceptance test** the workspace's content rules set: **5** units, **15** lessons, and
/// **124** steps — 58 teaching and 66 question, of which 50 are single-choice, 14 numeric, and 2 multi-select.
/// The prototype's own comment says "115 steps" and is stale. `CurriculumTests` asserts each number **exactly**
/// rather than as a range, because a range would pass a lesson that lost a step.
///
/// **Answer keys ship, deliberately** (invariant 10). Grading is client-side so a tap feels immediate, and the
/// server recomputes XP from the submitted per-question results and rejects impossible ones — so the key being
/// on the device buys a determined user nothing. The justification used to be offline lessons; ADR-0019 removed
/// those and the decision survived it on the responsiveness argument alone.
struct Curriculum: Sendable, Hashable, Decodable {
    /// In teaching order, which is also unlocking order. **The server's ordering** (ADR-0020) — the client
    /// never sorts, and "lesson N+1 unlocks on completing N" is a statement about this sequence.
    let units: [Unit]

    /// Every lesson in the curriculum, flattened, in the order they are unlocked.
    ///
    /// The design keeps a `FLAT` array beside `CURRICULUM` for exactly this and uses it to answer "what comes
    /// after this one". It is here rather than in the view model because it is a property of the content, and a
    /// second copy of "the order is unit order then lesson order" is a second thing to get wrong.
    var allLessons: [Unit.Lesson] { units.flatMap(\.lessons) }

    /// One lesson by id, across every unit. `nil` for an id no unit carries.
    ///
    /// **The join's client half.** A lesson's per-user state arrives in ``LearnScreen`` keyed by the same id;
    /// this is what turns that id back into a title, a glyph, and a blurb.
    func lesson(id: String) -> Unit.Lesson? {
        allLessons.first { $0.id == id }
    }

    /// One unit's five accent slots, as a name.
    ///
    /// A **name**, not a hex triad: the design sets `--acc`, `--acc-soft`, and `--acc-deep` per unit from a
    /// palette the app already has (`HWPalette.Units`), and shipping three colours per unit over the wire would
    /// be shipping the design system in a JSON payload. A colour reaching a use site by name is also what keeps
    /// the later dark-mode swap a swap (ADR-0001).
    ///
    /// Unknown names degrade to ``sky``, which is the design's own fallback — its `:root` sets
    /// `--acc: var(--planetary)` "so anything outside a unit block still renders". A unit drawn in the wrong
    /// tint is a blemish; there is nothing here that could file or refuse anything, which is why this enum
    /// degrades where ``LearnScreen/LessonState`` does not.
    enum Accent: String, Sendable, Hashable, Decodable, CaseIterable {
        case sun
        case mint
        case coral
        case sky
        case violet

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Accent(rawValue: raw) ?? .sky
        }
    }

    // MARK: - A unit

    /// One `.unit` — a numbered band of lessons under one accent.
    struct Unit: Sendable, Hashable, Decodable, Identifiable {
        /// `u1`…`u5`. Stable, because the guide sheet is opened with one and `LearnScreen` keys unit state by it.
        let id: String

        /// The `1`…`5` in the `.unit-n` tile, and the "Unit 3" caption.
        ///
        /// **From the payload rather than from the array index**, which is the same rule ADR-0033 applies to
        /// ordering: a number the user reads is a figure, and a figure comes from the server. It also survives a
        /// curriculum that one day ships a subset — the index would silently renumber it.
        let number: Int

        /// The number as the tile and the caption draw it.
        ///
        /// **Spelled here rather than at the call site**, which is the convention every interpolated catalogue key
        /// in this app depends on: a number is converted where it is *computed*, because the localisation scan
        /// derives `key %@` from the source and cannot know that `\(anInt)` resolves to `%lld`.
        ///
        /// It does **not** arrive formatted from the server the way ``LearnScreen/Stat/display`` does, and the
        /// difference is real rather than an inconsistency: 1…5 has no thousands separator and no plural, so
        /// `String(_:)` is the whole of its formatting, and Latin digits are pinned in both languages (ADR-0011).
        var numberText: String { String(number) }

        let accent: Accent

        /// "Build the Foundation". Server content, in the reader's language.
        let title: String
        /// "Income & Mindset" — the `.unit-sub`, and the second half of the guide sheet's caption.
        let subtitle: String
        /// The paragraph the guide sheet opens with.
        let blurb: String

        /// Two to four of them, in order.
        let lessons: [Lesson]

        // MARK: - A lesson

        /// One `.node` on the path, and everything the guide sheet's row draws.
        ///
        /// **It carries no progress and no lock.** Both are per-user and both live in ``LearnScreen``; a lesson
        /// that knew whether it was finished would be cacheable content describing one reader, which is
        /// invariant 8 broken at the model layer rather than at the cache.
        struct Lesson: Sendable, Hashable, Decodable, Identifiable {
            /// `u1l1`…`u5l3`. What `POST /v1/learn/lessons/:id/complete` is addressed to (#20), and the key the
            /// screen payload's per-lesson state is looked up by.
            let id: String

            /// The `1`…`n` on the guide sheet's row chip — the lesson's place **within its unit**.
            ///
            /// **From the payload rather than from the array index**, for the reason ``Unit/number`` is: a number
            /// the reader sees is a figure, and a figure comes from a response (ADR-0020). It was `index + 1` at
            /// two call sites until review, which is the same rule broken twice — and it would have renumbered
            /// silently the first time a curriculum shipped a subset of a unit.
            let number: Int

            /// The number as the chip draws it. Spelled here, where it is computed — see ``Unit/numberText``.
            var numberText: String { String(number) }

            let icon: Icon

            /// "Gross vs. Net Income" — the `.node-lab` and the guide row's title.
            let title: String
            /// "Know what really lands in your bank account." — the guide row's second line.
            let blurb: String

            /// The teaching and the questions, in order. **The lesson player's material** (#20); the map draws
            /// none of it.
            ///
            /// They are here rather than on their own endpoint because the design has them in one constant and
            /// the whole document is one ETag: a per-lesson fetch would be fifteen round trips for a
            /// 100 KB file that changes when an editor changes it.
            let steps: [Step]

            /// How many of the steps are questions.
            ///
            /// **Not what the ring is drawn from.** The ring's segment count arrives in the screen payload
            /// (``LearnScreen/LessonProgress/segments``), because a count is a calculation and the screen's
            /// figures all come from one response (ADR-0020). This exists so the *content test* can assert the
            /// 66 the content rules require, and so a payload whose segment count disagrees with its own
            /// curriculum is something a test can notice.
            var questionCount: Int { steps.filter(\.isQuestion).count }
        }

        /// The design's fifteen lesson glyphs, as a closed set of names.
        ///
        /// One per lesson, and every one is a 24×24 stroke drawing in the design. A **name** rather than the
        /// path, for the reason `HomeScreen.Icon` and `ExpensesScreen.Icon` are names: shipping fifteen
        /// drawings in a JSON payload is shipping the design system over the wire. Unknown names fall back to
        /// ``book``, which is the design's own default (`ICON[l.icon] || ICON.book`).
        enum Icon: String, Sendable, Hashable, Decodable, CaseIterable {
            case wallet
            case clock
            case split
            case flow
            case pie
            case shield
            case bank
            case gauge
            case scales
            case steps
            case umbrella
            case lock
            case spark
            case layers
            case grid
            /// The generic lesson glyph, and the fallback.
            case book

            init(from decoder: any Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = Icon(rawValue: raw) ?? .book
            }
        }
    }

    // MARK: - A step

    /// One step inside a lesson: a page of teaching, or a question.
    ///
    /// **One discriminator, four cases.** The design carries two — `t: "teach" | "q"` and then `kind` on the
    /// questions — and collapsing them means the client has one closed vocabulary and one `switch` rather than
    /// a nested pair whose invalid combinations (a teaching step with a `kind`, a question without one) are
    /// representable.
    ///
    /// **It refuses to guess, for `ExpensesScreen.Kind`'s reason.** A step's kind decides what the player
    /// *does* — draw prose, offer one answer, offer several, or take a typed number — and a wrong guess grades
    /// the wrong thing. Since grading is client-side (invariant 10), grading the wrong thing means telling a
    /// learner they are wrong when they are right. So an unrecognised kind fails the decode and the screen
    /// renders `LoadState.failed`; a new kind is a coordinated release.
    enum Step: Sendable, Hashable, Decodable {
        /// A page of prose — the design's `t: "teach"`.
        case teach(Teach)
        /// One right answer out of four — the design's `kind: "choice"`, and 50 of the 66.
        case singleChoice(Question)
        /// Several right answers — `kind: "multi"`, and 2 of the 66.
        case multiSelect(Question)
        /// A figure the learner types — `kind: "num"`, and 14 of the 66.
        case numeric(Numeric)

        /// Whether this step is one the learner answers, which is what the progress ring counts.
        var isQuestion: Bool {
            if case .teach = self { return false }
            return true
        }

        private enum CodingKeys: String, CodingKey { case kind }

        private enum Kind: String, Decodable {
            case teach
            case singleChoice
            case multiSelect
            case numeric
        }

        init(from decoder: any Decoder) throws {
            let kind = try decoder.container(keyedBy: CodingKeys.self).decode(Kind.self, forKey: .kind)
            switch kind {
            case .teach: self = .teach(try Teach(from: decoder))
            case .singleChoice: self = .singleChoice(try Question(from: decoder))
            case .multiSelect: self = .multiSelect(try Question(from: decoder))
            case .numeric: self = .numeric(try Numeric(from: decoder))
            }
        }

        /// A teaching page: a heading, prose, and whichever of the three optional blocks it carries.
        ///
        /// **Emphasis is markdown**, not the design's inline `<b>`/`<i>` — HTML cannot reach a SwiftUI `Text`,
        /// and the conversion happens once in the extraction rather than at every render (ADR-0032,
        /// ``HWMarkdown``). `{c}` is left verbatim, as the content rules require: the figures in a teaching
        /// example are illustrative and are never converted (ADR-0016).
        struct Teach: Sendable, Hashable, Decodable {
            /// The `.t-h`.
            let heading: String

            /// The `.t-p` paragraphs above the list.
            let paragraphs: [String]

            /// The `.t-list` — term-and-explanation pairs, the same `{k, v}` shape `ArticleBody.Entry` has.
            let list: [Entry]

            /// The paragraphs the design writes as `p2`, **after** the list.
            ///
            /// One step in the curriculum uses it, and the position is load-bearing rather than incidental: the
            /// sentence refers back to the three items above it ("A password plus a code from an app is two
            /// factors"). Folding it into ``paragraphs`` would move it above the list it is about.
            let afterList: [String]

            /// The `.eg` panel — a worked example, or `nil`.
            let example: Example?

            /// The `.tip` — the dashed "Remember it:" box, or `nil`. The words "Remember it:" are the *view's*,
            /// because they are app copy rather than content.
            let tip: String?

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                heading = try container.decode(String.self, forKey: .heading)
                // Absent rather than empty for the blocks a step does not have, so the payload reads as the
                // design's own steps do — the alternative is 124 steps each carrying four empty arrays.
                paragraphs = try container.decodeIfPresent([String].self, forKey: .paragraphs) ?? []
                list = try container.decodeIfPresent([Entry].self, forKey: .list) ?? []
                afterList = try container.decodeIfPresent([String].self, forKey: .afterList) ?? []
                example = try container.decodeIfPresent(Example.self, forKey: .example)
                tip = try container.decodeIfPresent(String.self, forKey: .tip)
            }

            private enum CodingKeys: String, CodingKey {
                case heading, paragraphs, list, afterList, example, tip
            }
        }

        /// One row of a teaching list.
        struct Entry: Sendable, Hashable, Decodable, Identifiable {
            let term: String
            let detail: String

            /// The term, which is unique within a step. An index would be an identity that moves when a row is
            /// inserted above it — the same reasoning `ArticleBody.Section` records.
            var id: String { term }
        }

        /// The `.eg` panel: a heading and a body, the body carrying its own paragraph breaks.
        struct Example: Sendable, Hashable, Decodable {
            let heading: String
            /// The design writes `<br><br>` between the lines of a worked example; the extraction turns them
            /// into blank lines, so this is one string with newlines rather than an array — the breaks are
            /// *inside* a single worked calculation rather than between paragraphs.
            let body: String
        }

        /// A question with options: single-choice or multi-select.
        ///
        /// **One type for both**, because the shape is identical and only the arity of the answer differs —
        /// which the enclosing ``Step`` case already says. Two structs would be two decoders to keep in step.
        struct Question: Sendable, Hashable, Decodable {
            /// The `.q-h`.
            let prompt: String

            /// The `.opt` buttons, in the order the design lists them. Ordering is the server's (ADR-0020) —
            /// and shuffling would move the answer indices with it.
            let options: [String]

            /// Which options are right, as **indices into ``options``**, ascending.
            ///
            /// An array for both kinds: a single-choice question carries one element. The design uses a bare
            /// number for one and an array for the other, which would be two shapes for one idea — and the
            /// grading code would have to know which it had before it could compare anything.
            let answers: [Int]

            /// The `.fb-p` — why that is the answer. Shown after grading, right or wrong.
            let explanation: String
        }

        /// A question the learner types a figure into.
        struct Numeric: Sendable, Hashable, Decodable {
            let prompt: String

            /// The right answer, as a whole number.
            ///
            /// **An `Int`, and that is a content rule rather than a convenience.** All fourteen numeric answers
            /// in the curriculum are whole — a net pay, a number of years, a percentage — and `Models` may not
            /// hold a `Double` outside the geometry fractions `MoneyFormattingAbsenceTests` names. A fractional
            /// answer would therefore be a coordinated content-and-client change, which is the right price for
            /// it: the tolerance below is what makes typing `3600.0` work, not a fractional key.
            ///
            /// The comparison itself — the strict `< 0.5` tolerance the design grades with — is
            /// ``LessonRun/isWithinTolerance(typed:of:)``, because that is where a typed string becomes a number.
            let answer: Int

            /// The answer as the feedback footer names it after a wrong one.
            ///
            /// **Spelled here, where the number is**, which is the convention every interpolated catalogue key in
            /// this app depends on (see ``Curriculum/Unit/numberText``). It carries no thousands separator and no
            /// currency symbol, and neither is an omission: the client owns no formatter (ADR-0003), and a symbol
            /// pushed onto the front of a string lands on the wrong side of an Arabic figure — which is why the
            /// *input* box draws its symbol as a view beside the field rather than inside the string.
            var answerText: String { String(answer) }

            /// Whether the field shows the display currency's symbol beside the box.
            ///
            /// The design's `prefix`, and it distinguishes a money question from a percentage or a number of
            /// years: "what is his net pay" wants a symbol, "how many years until prices double" does not. The
            /// curriculum sends it on **every** numeric step — eleven `true`, three `false` — and the default here
            /// is tolerance rather than the common case, which is the correction review made to this sentence.
            let showsCurrencySymbol: Bool

            let explanation: String

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                prompt = try container.decode(String.self, forKey: .prompt)
                answer = try container.decode(Int.self, forKey: .answer)
                showsCurrencySymbol = try container.decodeIfPresent(Bool.self, forKey: .showsCurrencySymbol) ?? false
                explanation = try container.decode(String.self, forKey: .explanation)
            }

            private enum CodingKeys: String, CodingKey {
                case prompt, answer, showsCurrencySymbol, explanation
            }
        }
    }
}
