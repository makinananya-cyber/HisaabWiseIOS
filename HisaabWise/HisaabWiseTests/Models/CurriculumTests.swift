import Foundation
@testable import HisaabWise
import Testing

/// **The content acceptance test.** The workspace's content rules set the counts, and the counts are the test:
/// 5 units, 15 lessons, and 124 steps — 58 teaching and 66 question, of which 50 are single-choice, 14 numeric,
/// and 2 multi-select.
///
/// **Asserted exactly, never as a range**, which is the instruction and also the only useful form: a range passes
/// a lesson that lost a step, and losing a step is precisely what a content pipeline does quietly. The prototype's
/// own comment says "115 steps" and is stale — the verified count is 124, and the number in this file is the one
/// that decides.
///
/// The rest of the suite is about the shapes those steps take, because a count on its own would pass a curriculum
/// of 124 empty objects.
@Suite("The curriculum")
struct CurriculumTests {
    private static func curriculum() throws -> Curriculum {
        try Fixture.curriculum.decode(Curriculum.self)
    }

    private static func steps() throws -> [Curriculum.Step] {
        try curriculum().units.flatMap { $0.lessons.flatMap(\.steps) }
    }

    // MARK: - The counts

    @Test("the curriculum carries exactly 5 units, 15 lessons, and 124 steps")
    func theCountsAreExact() throws {
        let curriculum = try Self.curriculum()

        #expect(curriculum.units.count == 5)
        #expect(curriculum.allLessons.count == 15)
        #expect(try Self.steps().count == 124)
    }

    @Test("the 124 steps are 58 teaching and 66 question")
    func theStepSplitIsExact() throws {
        let steps = try Self.steps()

        #expect(steps.filter { !$0.isQuestion }.count == 58)
        #expect(steps.filter(\.isQuestion).count == 66)
    }

    /// 50 + 14 + 2 = 66, and each is asserted rather than the total: a curriculum that turned a multi-select into
    /// a single-choice would keep the total and change what the player grades.
    @Test("the 66 questions are 50 single-choice, 14 numeric, and 2 multi-select")
    func theQuestionKindsAreExact() throws {
        var single = 0, numeric = 0, multi = 0
        for step in try Self.steps() {
            switch step {
            case .teach: break
            case .singleChoice: single += 1
            case .numeric: numeric += 1
            case .multiSelect: multi += 1
            }
        }

        #expect(single == 50)
        #expect(numeric == 14)
        #expect(multi == 2)
    }

    /// The five units the ticket names, in order, each with its own accent — and **all five accents used once**,
    /// which is what makes "the five unit accent colours" a property rather than a coincidence.
    @Test("the five units are the five the ticket names, each in its own accent")
    func theFiveUnitsAreTheFive() throws {
        let units = try Self.curriculum().units

        #expect(units.map(\.title) == [
            "Build the Foundation",
            "Control Cash Flow",
            "Master Borrowing",
            "Protect Wealth",
            "Grow Wealth",
        ])
        #expect(units.map(\.number) == [1, 2, 3, 4, 5])
        #expect(Set(units.map(\.accent)).count == 5)
        #expect(Set(units.map(\.accent)) == Set(Curriculum.Accent.allCases))
    }

    // MARK: - The shapes inside

    /// A count of 124 would be satisfied by 124 empty objects, so every step is checked to say something.
    @Test("no step is empty — every teaching page has prose and every question has a prompt")
    func noStepIsEmpty() throws {
        for step in try Self.steps() {
            switch step {
            case .teach(let teach):
                #expect(!teach.heading.isEmpty)
                // A teaching page with no prose, no list, and no example is a heading on its own.
                #expect(
                    !teach.paragraphs.isEmpty || !teach.list.isEmpty || teach.example != nil,
                    "the teaching step \"\(teach.heading)\" has nothing in it"
                )
            case .singleChoice(let question), .multiSelect(let question):
                #expect(!question.prompt.isEmpty)
                #expect(!question.explanation.isEmpty, "\"\(question.prompt)\" has no explanation")
            case .numeric(let question):
                #expect(!question.prompt.isEmpty)
                #expect(!question.explanation.isEmpty, "\"\(question.prompt)\" has no explanation")
            }
        }
    }

    /// **The answer keys are intact**, which the ticket asks for explicitly — grading is client-side and the
    /// server recomputes, so a stripped key is a lesson nothing can grade (invariant 10).
    ///
    /// Every choice question has at least one answer and every answer indexes an option that exists. A key of
    /// `[7]` over four options is a question the player would mark wrong whatever the reader picked.
    @Test("every answer key is present and indexes an option that exists")
    func theAnswerKeysAreIntact() throws {
        var single = 0, multi = 0
        for step in try Self.steps() {
            switch step {
            case .singleChoice(let question):
                single += 1
                // Exactly one, because that is what single-choice means — two would be a multi-select wearing the
                // wrong kind, and the player offers radio behaviour for it.
                #expect(question.answers.count == 1, "\"\(question.prompt)\" is single-choice with \(question.answers.count) answers")
                #expect(question.options.count >= 2)
                #expect(question.answers.allSatisfy { question.options.indices.contains($0) })
            case .multiSelect(let question):
                multi += 1
                // More than one, for the mirror-image reason.
                #expect(question.answers.count > 1, "\"\(question.prompt)\" is multi-select with one answer")
                #expect(question.answers.count < question.options.count, "every option is right, so there is nothing to pick")
                #expect(question.answers.allSatisfy { question.options.indices.contains($0) })
            case .numeric, .teach:
                break
            }
        }
        #expect(single == 50)
        #expect(multi == 2)
    }

    /// **The numeric answers are whole numbers**, which is the content rule ``Curriculum/Step/Numeric/answer``
    /// records rather than a coincidence the model relies on: `Models` may hold no `Double` outside the geometry
    /// fractions, so a fractional key would be a coordinated content-and-client change. Decoding all fourteen is
    /// what proves the rule still holds — a fractional one would have failed the decode above.
    @Test("the fourteen numeric answers are whole numbers, and one of them shows a currency symbol")
    func theNumericAnswersAreWhole() throws {
        let numeric = try Self.steps().compactMap { step -> Curriculum.Step.Numeric? in
            guard case .numeric(let question) = step else { return nil }
            return question
        }

        #expect(numeric.count == 14)
        // Money questions want the display currency beside the field; a percentage or a number of years does not.
        // Both shapes exist in the design, and a corpus with only one would leave the other untested.
        #expect(numeric.contains { $0.showsCurrencySymbol })
        #expect(numeric.contains { !$0.showsCurrencySymbol })
    }

    // MARK: - Ids, ordering, and the join

    /// Every id is unique and every lesson id is addressable, because the id is the join with the screen payload
    /// **and** the address `POST /v1/learn/lessons/:id/complete` will use (#20). Two lessons sharing one would
    /// draw one node's progress on both.
    @Test("every unit and lesson id is unique")
    func everyIDIsUnique() throws {
        let curriculum = try Self.curriculum()
        let unitIDs = curriculum.units.map(\.id)
        let lessonIDs = curriculum.allLessons.map(\.id)

        #expect(Set(unitIDs).count == unitIDs.count)
        #expect(Set(lessonIDs).count == lessonIDs.count)
        #expect(lessonIDs.allSatisfy { !$0.isEmpty })
    }

    /// `allLessons` is unit order then lesson order, which is what "lesson N+1 unlocks on completing N" is a
    /// statement about. A different flattening would make the unlock sequence mean something else.
    @Test("the flattened order is unit order then lesson order")
    func theFlattenedOrderIsTeachingOrder() throws {
        let curriculum = try Self.curriculum()

        #expect(curriculum.allLessons.map(\.id) == curriculum.units.flatMap { $0.lessons.map(\.id) })
        #expect(curriculum.allLessons.first?.id == curriculum.units.first?.lessons.first?.id)
        // Two to four lessons a unit, which is the design's own distribution — and no empty unit.
        #expect(curriculum.units.allSatisfy { (2...4).contains($0.lessons.count) })
    }

    /// **Every lesson carries its own number, restarting at 1 in each unit** — the design numbers the guide sheet
    /// that way, and a figure the reader sees comes from the payload rather than from an array index (ADR-0020).
    /// It was `index + 1` at two call sites until review.
    @Test("every lesson carries its place within its unit, and it is not the flattened index")
    func everyLessonCarriesItsNumber() throws {
        let units = try Self.curriculum().units

        for unit in units {
            #expect(unit.lessons.map(\.number) == Array(1...unit.lessons.count), "unit \(unit.id)")
            #expect(unit.lessons.map(\.numberText) == unit.lessons.map { String($0.number) })
        }
        // And it is per unit rather than across the curriculum, which is the thing the flattened index would have
        // got right for the first unit and wrong for the other four.
        #expect(try Self.curriculum().allLessons.map(\.number) == [1, 2, 3, 1, 2, 3, 4, 1, 2, 3, 1, 2, 1, 2, 3])
    }

    @Test("a lesson can be looked up by id, and an id nothing carries yields nothing")
    func lessonLookupWorks() throws {
        let curriculum = try Self.curriculum()

        #expect(curriculum.lesson(id: "u1l1")?.title == "Gross vs. Net Income")
        #expect(curriculum.lesson(id: "u5l3") != nil)
        #expect(curriculum.lesson(id: "u9l9") == nil)
    }

    // MARK: - Editorial rules

    /// **Emphasis is markdown, not HTML** (ADR-0032). The design writes `<b>` and `<i>` inline; HTML cannot reach
    /// a SwiftUI `Text`, so the conversion happens once in the extraction. A tag surviving into the corpus would
    /// be rendered literally — the reader would see `<b>`.
    @Test("no HTML survived into the curriculum, and the emphasis became markdown")
    func emphasisIsMarkdown() throws {
        let text = try Self.everyString()

        for tag in ["<b>", "</b>", "<i>", "</i>", "<br>", "<p>", "<span"] {
            #expect(!text.contains { $0.contains(tag) }, "\(tag) survived the extraction")
        }
        // And the conversion happened rather than the emphasis being stripped, which was the other way to pass the
        // scan above and loses the point of half these sentences.
        #expect(text.contains { $0.contains("**") })
    }

    /// **`{c}` is left verbatim**, as the content rules require: the figures inside a teaching example are
    /// illustrative and are never converted (ADR-0016). The player substitutes the reader's own symbol.
    @Test("the currency token is preserved verbatim, and no lesson hardcodes a symbol instead")
    func theCurrencyTokenIsVerbatim() throws {
        let text = try Self.everyString()

        #expect(text.contains { $0.contains("{c}") })
        // The design's own examples are written in dirhams and rupees nowhere — they are all `{c}`. A hardcoded
        // symbol would be one reader's currency shown to everybody, which is the defect D1 shape in content form.
        for symbol in ["AED ", "₹", "د.إ", "$"] {
            #expect(!text.contains { $0.contains(symbol) }, "a lesson hardcodes \(symbol) instead of {c}")
        }
    }

    /// Every string in the curriculum, for the two editorial scans above.
    private static func everyString() throws -> [String] {
        var out: [String] = []
        for unit in try curriculum().units {
            out += [unit.title, unit.subtitle, unit.blurb]
            for lesson in unit.lessons {
                out += [lesson.title, lesson.blurb]
                for step in lesson.steps {
                    switch step {
                    case .teach(let teach):
                        out += [teach.heading] + teach.paragraphs + teach.afterList
                        out += teach.list.flatMap { [$0.term, $0.detail] }
                        if let example = teach.example { out += [example.heading, example.body] }
                        if let tip = teach.tip { out.append(tip) }
                    case .singleChoice(let question), .multiSelect(let question):
                        out += [question.prompt, question.explanation] + question.options
                    case .numeric(let question):
                        out += [question.prompt, question.explanation]
                    }
                }
            }
        }
        return out
    }

    // MARK: - The kinds

    /// **A step kind refuses to guess** (``Curriculum/Step``), for `ExpensesScreen.Kind`'s reason: it decides what
    /// the player *does*, and grading is client-side, so guessing wrong tells a reader they are wrong when they
    /// are right.
    @Test("an unrecognised step kind fails the decode rather than degrading")
    func anUnknownStepKindFails() throws {
        let payload = Data(#"{"kind":"dragAndDrop","prompt":"?"}"#.utf8)

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Curriculum.Step.self, from: payload)
        }
    }

    /// And the two that **do** degrade, because they are presentation. An accent the client does not know draws
    /// the design's own fallback tint; an icon it does not know draws the generic lesson glyph. A unit in the
    /// wrong tint is a blemish; nothing about either can file or refuse anything.
    @Test("an unrecognised accent and an unrecognised icon degrade rather than failing")
    func presentationDegrades() throws {
        struct Wrapper: Decodable {
            let accent: Curriculum.Accent
            let icon: Curriculum.Unit.Icon
        }
        let payload = Data(#"{"accent":"chartreuse","icon":"abacus"}"#.utf8)

        let wrapper = try JSONDecoder().decode(Wrapper.self, from: payload)

        #expect(wrapper.accent == .sky)
        #expect(wrapper.icon == .book)
    }

    /// The `book` fallback is a real case rather than a spare one, so it must not be what the curriculum actually
    /// ships — fifteen lessons drawing the generic glyph would pass every scan above.
    @Test("every lesson carries a glyph of its own rather than the fallback")
    func noLessonUsesTheFallbackGlyph() throws {
        let icons = try Self.curriculum().allLessons.map(\.icon)

        #expect(!icons.contains(.book))
        #expect(Set(icons).count == 15, "two lessons share a glyph")
    }
}
