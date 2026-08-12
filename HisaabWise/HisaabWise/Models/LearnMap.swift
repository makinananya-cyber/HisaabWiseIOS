import Foundation

/// The unit map, as one value: the curriculum's five units with **this reader's** state attached to each unit
/// and each lesson.
///
/// **It is the join, and the join is a lookup.** Learn reads two endpoints because its two halves have opposite
/// cache rules — ``Curriculum`` is the same bytes for everybody and carries an ETag, ``LearnScreen`` is per-user
/// and bypasses every cache (invariant 8, ADR-0034). Pairing them by lesson id introduces no figure that was not
/// in one of the two responses: every lock, every ring count, every label, and the ordering all arrived computed
/// (ADR-0020). What this type adds is *nothing*, which is the property that makes it allowed.
///
/// **Assembled once, in the view model, rather than looked up in a `body`.** A view that called
/// `progress.lesson(id:)` while drawing would do fifteen linear searches per render and would leave "what happens
/// to a lesson the payload says nothing about" as an answer each call site gives separately. Here it is one
/// answer, given once, and a test can state it.
struct LearnMap: Sendable, Hashable {
    /// In teaching order, which is unlocking order — the server's (ADR-0020).
    let units: [Unit]

    /// The reader's streak, XP, and cursor, carried through so the stats bar reads from one place.
    let progress: LearnScreen

    /// Pairs each unit and each of its lessons with its state, **skipping any lesson the screen payload says
    /// nothing about**.
    ///
    /// A curriculum that has gained a lesson since the payload was assembled will have one with no state. Drawing
    /// nothing for it is the right answer: inventing a state would render a lock or an invitation the server did
    /// not send, and failing the whole screen would throw away fourteen perfectly good nodes over one. The two
    /// halves come from one deployment, so this is a transitional window rather than a steady state — and
    /// `LearnViewModelTests` pins the behaviour so it cannot quietly become one of the other two.
    init(curriculum: Curriculum, progress: LearnScreen) {
        self.progress = progress
        units = curriculum.units.compactMap { unit in
            let lessons = unit.lessons.compactMap { lesson in
                progress.lesson(id: lesson.id).map {
                    Lesson(content: lesson, progress: $0, isNext: progress.isNext(lesson.id))
                }
            }
            // A unit whose every lesson went missing is a unit with nothing in it. The unit *header* would still
            // draw, which is a band of colour over empty space — so the unit goes too.
            guard !lessons.isEmpty else { return nil }
            return Unit(
                content: unit,
                // A unit the payload does not mention reads as **locked**, which is the safe default here for the
                // reason `LearnScreen.LessonState` refuses one: a unit's own flag is decoration over lessons that
                // carry their own locks, so guessing wrong greys a header and strands nobody.
                isUnlocked: progress.unit(id: unit.id)?.isUnlocked ?? false,
                lessons: lessons
            )
        }
    }

    /// One unit on the map: its content, whether it has been reached, and its lessons.
    struct Unit: Sendable, Hashable, Identifiable {
        let content: Curriculum.Unit
        let isUnlocked: Bool
        let lessons: [Lesson]

        var id: String { content.id }
    }

    /// One node on the path: its content, its state, and whether the **START** badge sits on it.
    struct Lesson: Sendable, Hashable, Identifiable {
        let content: Curriculum.Unit.Lesson
        let progress: LearnScreen.LessonProgress

        /// The design's `.has-start` — the badge above the cursor. **One lesson at most**, because the server
        /// names exactly one (``LearnScreen/nextLesson``) and a client that scanned for "the first open, unfinished
        /// one" would be doing the ordering itself.
        let isNext: Bool

        var id: String { content.id }

        /// Whether pressing the node starts the lesson. A **completed** lesson is open: the design lets a reader
        /// run a finished one again, and its own "out of hearts" dialog offers exactly that.
        var isOpen: Bool { progress.isOpen }
    }
}

extension LearnMap {
    /// Every lesson on the map, flattened — the shape a test states the unlock sequence against, and the layout
    /// the map falls back to at accessibility sizes.
    var allLessons: [Lesson] { units.flatMap(\.lessons) }

    /// One unit by id, for the guide sheet — which is opened with an id so that a reload underneath it re-renders
    /// the sheet from the new payload rather than from the copy it was opened with (ADR-0020, the rule
    /// `ExpenseCategoryView` follows).
    func unit(id: String) -> Unit? {
        units.first { $0.id == id }
    }

    /// Everything the lesson player needs to open a lesson: the unit it belongs to, the lesson itself, and the
    /// reader's currency token for the `{c}` in its steps.
    ///
    /// **The map is where this lookup belongs**, because the map is the join: the player draws the unit's number
    /// and accent around the lesson's own steps, and finding a lesson's parent by walking the curriculum at the
    /// call site is the search `LearnScreen.NextLesson.unitID` exists to avoid.
    ///
    /// Unlike the guide sheet, the player takes this **once and keeps it** — see ``LessonPlayerViewModel``: a run
    /// re-read from each reload would be a run that restarted under the reader.
    struct Material: Sendable, Hashable {
        let unit: Unit
        let lesson: Lesson

        /// What `{c}` becomes in this lesson's steps, from the per-user half of the payload (ADR-0016).
        let currencyToken: CurrencyToken
    }

    /// The unit and lesson one id names, or `nil` for a lesson this map does not carry — which is a lesson the
    /// screen payload said nothing about (see ``init(curriculum:progress:)``).
    func material(forLessonID id: String) -> Material? {
        for unit in units {
            if let lesson = unit.lessons.first(where: { $0.id == id }) {
                return Material(unit: unit, lesson: lesson, currencyToken: progress.currencyToken)
            }
        }
        return nil
    }
}
