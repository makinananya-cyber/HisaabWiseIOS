import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// The Learn screen: what it maps, what it refuses to work out, and the copy behind every key it renders.
///
/// A whole-screen render is a smoke test here for the reason `CONTEXT.md` records: `ScreenChrome` supplies
/// `.task { load() }`, `load()` writes `.loading` first, and `ImageRenderer` yields to the main actor before it
/// captures — so the pixels are the spinner however loaded the view model was. The claims worth asserting are the
/// **mappings**, which are `static`, `nonisolated`, and total, plus the copy.
@Suite("LearnView")
@MainActor
struct LearnViewTests {
    private static func loaded(_ fixture: Fixture = .learnInProgress) async throws -> LearnMap {
        let client = TestBench.client(
            FixtureTransport(stubs: [
                Endpoint.screenLearn: try .ok(fixture),
                Endpoint.curriculum: try .ok(.curriculum),
            ])
        )
        let viewModel = LearnViewModel(
            client: client,
            content: ContentLoader(client: client, store: InMemoryContentStore())
        )
        try await viewModel.load()
        return try #require(viewModel.state.value)
    }

    // MARK: - Glyphs

    /// **Every icon the curriculum can carry has a glyph**, which is what stops a node drawing a hole in itself. A
    /// name the client does not recognise falls back to `book` in the payload's own decoder, so the mapping only
    /// has to be total over the cases that exist.
    @Test("every lesson icon maps to a symbol, and no two lessons share one")
    func everyIconHasAGlyph() {
        for icon in Curriculum.Unit.Icon.allCases {
            #expect(!LearnView.symbol(icon).isEmpty, "\(icon)")
        }
        // Sixteen cases, sixteen distinct drawings — including the `book` fallback, which no lesson uses
        // (`CurriculumTests`) and which must still be its own glyph rather than a duplicate of one.
        #expect(Set(Curriculum.Unit.Icon.allCases.map(LearnView.symbol)).count
            == Curriculum.Unit.Icon.allCases.count)
    }

    /// No glyph encodes a direction that would point the wrong way in Arabic. `LocalisationTests` scans the source
    /// for the banned names; this asserts it of the *values*, which is the half a source scan cannot see once a
    /// name is returned from a `switch`.
    @Test("no glyph on this screen points left or right")
    func noGlyphEncodesDirection() {
        let banned = [
            "chevron.left", "chevron.right", "arrow.left", "arrow.right",
            "arrowtriangle.left", "arrowtriangle.right",
            "arrow.turn.up.left", "arrow.turn.up.right", "arrow.uturn.left", "arrow.uturn.right",
        ]
        let glyphs = Curriculum.Unit.Icon.allCases.map(LearnView.symbol)
            + HWLessonNodeState.allCases.map(HWLessonRow.glyph)

        for glyph in glyphs {
            #expect(!banned.contains { glyph.hasPrefix($0) }, "\(glyph)")
        }
    }

    // MARK: - The two mappings into the design system

    /// The five accents, mapped onto the five palette slots — **one each**, which is what makes "the five unit
    /// accent colours" a property rather than a coincidence of two tables happening to line up.
    @Test("the five accents map onto five distinct palette slots")
    func theAccentsMapOneToOne() {
        let tints = Curriculum.Accent.allCases.map(LearnView.tint)

        #expect(tints.count == 5)
        #expect(Set(tints).count == 5)
        #expect(Set(tints) == Set(HWUnitTint.allCases))
    }

    /// And the three lesson states, mapped onto the component's three — total and distinct, so no state can draw
    /// as another.
    @Test("the three lesson states map onto three distinct node states")
    func theStatesMapOneToOne() {
        let states = LearnScreen.LessonState.allCases.map(LearnView.state)

        #expect(Set(states).count == 3)
        #expect(Set(states) == Set(HWLessonNodeState.allCases))
        #expect(LearnView.state(.locked) == .locked)
        #expect(LearnView.state(.completed) == .completed)
    }

    /// One mapped lesson carries everything the node draws, **and nothing it worked out**: every field traces to a
    /// payload, including the two ring counts and the progress sentence.
    @Test("a node carries the payload's own counts, label, and cursor")
    func aNodeIsAssembledFromThePayload() async throws {
        let map = try await Self.loaded()
        let cursor = try #require(map.allLessons.filter(\.isNext).first)

        let node = LearnView.node(cursor)

        #expect(node.id == cursor.id)
        #expect(node.title == cursor.content.title)
        #expect(node.progressLabel == cursor.progress.progressLabel)
        #expect(node.segments == cursor.progress.segments)
        #expect(node.filledSegments == cursor.progress.filledSegments)
        #expect(node.state == .available)
        #expect(node.isNext)
        // The part-answered ring the standing fixture exists to draw: some arcs lit, some not.
        #expect(node.filledSegments > 0)
        #expect(node.filledSegments < node.segments)
    }

    /// A finished lesson's ring is **full because the server filled it**, not because the view special-cased it —
    /// which is what keeps the tick and the ring agreeing.
    @Test("a completed lesson's ring is full and its state says so")
    func aCompletedRingIsFull() async throws {
        let map = try await Self.loaded()
        let done = try #require(map.allLessons.first { $0.progress.state == .completed })

        let node = LearnView.node(done)

        #expect(node.state == .completed)
        #expect(node.filledSegments == node.segments)
    }

    // MARK: - Copy

    /// Every key this screen renders has English copy. The app-wide scan in `LocalisationTests` finds them by
    /// reading the source; this names them, so a key deleted from the catalogue fails a suite that says which
    /// screen it belonged to.
    @Test("every key the screen renders has copy behind it")
    func theScreenCopyExists() throws {
        try CatalogueCopy.expectEnglishCopy(forKeys: [
            "learn.eyebrow",
            "learn.title",
            "learn.empty",
            "learn.start",
            "learn.guide.title",
            "learn.notice.locked",
            // Numbered arguments, so a translation can put the subject before the number (ADR-0011).
            "learn.unit.caption %@ %@",
        ])
    }

    /// The components' own four keys, which no screen supplies.
    @Test("the map's component copy is in the catalogue")
    func theComponentCopyExists() throws {
        try CatalogueCopy.expectEnglishCopy(forKeys: [
            HWComponentCopy.unitGuide.key,
            HWComponentCopy.lessonOpenHint.key,
            HWComponentCopy.lessonLockedHint.key,
            HWComponentCopy.lessonNextHint.key,
        ])
    }

    /// **The `START` flag reaches VoiceOver**, which for one build it did not: the flag is hidden — it is a second
    /// element saying something about the node beside it — and `isNext` reached no accessibility surface at all, so
    /// a reader could not tell which of fifteen lessons was the cursor. Review found the comment claiming otherwise.
    ///
    /// Asserted as the property that was missing: the cursor's hint differs from an ordinary open lesson's, and
    /// every combination has copy behind it.
    @Test("the next lesson's hint differs from an open one's, and every hint has copy")
    func theCursorIsAnnounced() throws {
        let next = HWComponentCopy.lessonHint(state: .available, isNext: true)
        let open = HWComponentCopy.lessonHint(state: .available, isNext: false)
        let locked = HWComponentCopy.lessonHint(state: .locked, isNext: false)

        #expect(next.key != open.key, "the lesson to start next reads the same as any other open one")
        #expect(locked.key != open.key)
        // A completed lesson can be the cursor too — nothing in the payload forbids it — and it must not fall
        // through to the locked hint.
        #expect(HWComponentCopy.lessonHint(state: .completed, isNext: true).key == next.key)
        #expect(HWComponentCopy.lessonHint(state: .completed, isNext: false).key == open.key)
        // A locked lesson is never the cursor, and if a payload said so the refusal still has to win: pressing it
        // does not start anything.
        #expect(HWComponentCopy.lessonHint(state: .locked, isNext: true).key == locked.key)

        var keys: [String] = []
        for state in HWLessonNodeState.allCases {
            for isNext in [true, false] {
                keys.append(HWComponentCopy.lessonHint(state: state, isNext: isNext).key)
            }
        }
        try CatalogueCopy.expectEnglishCopy(forKeys: Array(Set(keys)))
    }

    /// **The row's number comes from the payload**, at both call sites. It was `index + 1` in the guide sheet *and*
    /// in the accessibility-size replacement, which is ADR-0020 broken twice — and the two lists could disagree.
    @Test("a node carries the lesson's own number rather than its position")
    func theNodeNumberIsThePayloadsOwn() async throws {
        let map = try await Self.loaded()
        let lessons = map.allLessons

        // Fifteen lessons, but the numbering restarts at 1 in each unit — so it is not the flattened index either.
        #expect(lessons.map { LearnView.node($0).number } == lessons.map(\.content.numberText))
        #expect(map.units.map { $0.lessons.map(\.content.numberText) }
            == [["1", "2", "3"], ["1", "2", "3", "4"], ["1", "2", "3"], ["1", "2"], ["1", "2", "3"]])
    }

    /// One notice, one sentence, and **the choice is the view model's while the words are the catalogue's** — the
    /// split `ExpensesView.copy(for:)` draws for the same reason.
    @Test("every notice has its own sentence, and every sentence has copy")
    func everyNoticeHasCopy() throws {
        var keys: [String] = []
        for notice in LearnViewModel.Notice.allCases {
            keys.append(try #require(LearnView.copy(for: notice), "\(notice) has no sentence").key)
        }

        #expect(Set(keys).count == LearnViewModel.Notice.allCases.count, "two notices share a sentence")
        #expect(LearnView.copy(for: nil) == nil)
        try CatalogueCopy.expectEnglishCopy(forKeys: keys)
    }

    /// The unit caption interpolates the number **and** the subject, so the key it looks up carries two
    /// specifiers — which is the shape that resolved to nothing at all when Home's income label got it wrong.
    ///
    /// Asserted as three things rather than as one `Text` comparison, because two `Text`s built from the same
    /// localised key are **not** `==`: `LocalizedTextStorage` compares by identity, so an equality check here
    /// passes or fails for reasons that have nothing to do with the caption. The same reason
    /// `ExpensesViewTests` only ever asserts that two of them *differ*.
    @Test("the unit caption is one catalogue entry taking two numbered arguments")
    func theUnitCaptionIsOneEntry() async throws {
        let map = try await Self.loaded()
        let units = map.units.map(\.content)

        // The number is spelled where it is computed, which is what makes the key derivable from the source.
        #expect(units.first?.numberText == "1")
        #expect(units.map(\.numberText) == ["1", "2", "3", "4", "5"])

        // The entry takes both arguments and numbers them, so a translation can put the subject first.
        let value = try #require(CatalogueCopy.english(in: try CatalogueCopy.entry("learn.unit.caption %@ %@")))
        #expect(value.contains("%1$@"))
        #expect(value.contains("%2$@"))

        // And two units produce two captions, so neither argument is being dropped on the way in.
        let captions = units.map(LearnView.caption)
        for (index, caption) in captions.enumerated() {
            for other in captions[(index + 1)...] {
                #expect(caption != other, "two units share a caption")
            }
        }
    }

    // MARK: - It renders

    /// A smoke test: the screen's `body` evaluates with the environment it was given. It captures the spinner (see
    /// the note above), so what it proves is that nothing traps.
    @Test("the screen renders")
    func theScreenRenders() {
        #expect(TestBench.render(LearnView(viewModel: .previewInProgress)) != nil)
    }

    /// **The page draws something, and this is the assertion an empty ground cannot pass.**
    ///
    /// `ImageRenderer` does not lay out the content of a `ScrollView` (ADR-0033 found that by looking), which is why
    /// ``LearnMapPage`` exists at all — and why "it rendered" is not enough on its own: an empty ground renders
    /// perfectly well. Three payloads that came out byte-identical would mean none of them drew a map. The same
    /// technique `SnapshotSuiteTests` uses to prove its empty case is not photographing a spinner.
    ///
    /// **At the height the page asks for**, which is about 2,700pt — a `VStack` given less compresses its children
    /// instead of overflowing, and three payloads squashed into 300pt came back as two identical pictures.
    @Test("the page draws a different picture for each state the corpus carries")
    func thePageDrawsTheMap() async throws {
        var pictures: [Fixture: Data] = [:]

        for fixture in [Fixture.learnInProgress, .learnFirstRun, .learnComplete] {
            let map = try await Self.loaded(fixture)
            let page = LearnMapPage(map: map, onOpenGuide: { _ in }, onSelect: { _ in })
            pictures[fixture] = try #require(
                TestBench.render(page, height: nil)?.pngData(),
                "\(fixture.rawValue) did not render"
            )
        }

        #expect(Set(pictures.values).count == 3, "two states drew the same picture — the page may be drawing nothing")
    }
}
