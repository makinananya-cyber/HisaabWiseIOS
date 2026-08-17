import Foundation

/// The copy the components own, rather than take from a caller.
///
/// It is a very short list on purpose. A component takes its words from the screen — a button's title,
/// a field's label — because only the screen knows what it is asking for. What is left here is the copy
/// that belongs to the *control* and would otherwise be written twelve times: the close affordance every
/// sheet has, and the state a spinner cannot announce.
///
/// Gathered into one type so that ``keys`` can be asserted against the String Catalogue in one place;
/// a key with nothing behind it shows the user the key (ADR-0011).
enum HWComponentCopy {
    /// The `.sheet-x` affordance. Icon-only, so this is the whole of what VoiceOver reads.
    static let closeSheet: LocalizedStringResource = "component.sheet.close"

    /// Read as the button's value while a request is in flight. The spinner that replaces the label is
    /// invisible to VoiceOver, so without this the control goes silent exactly when it is busy
    /// (ADR-0012).
    static let inFlight: LocalizedStringResource = "component.button.inFlight"

    /// The `.unit-guide` affordance on a Learn unit header. Icon-only, so this is the whole reading (#19).
    static let unitGuide: LocalizedStringResource = "component.unit.guide"

    /// What pressing an open lesson node does. A **hint** rather than a label: the label is the lesson's own
    /// title, which is the server's, and only the *consequence* is the control's to describe.
    static let lessonOpenHint: LocalizedStringResource = "component.lesson.hint.open"

    /// And what pressing a locked one does. It is not a disabled control — the design refuses with a sentence
    /// rather than swallowing the tap — so the hint says which, and a reader hears why before they press.
    static let lessonLockedHint: LocalizedStringResource = "component.lesson.hint.locked"

    /// The lesson the reader should do next — **the `START` flag's only reading**.
    ///
    /// The flag itself is hidden from VoiceOver, because a floating badge is a second element saying something
    /// about the node beside it. That only works if the node says it, and for one build it did not: `isNext`
    /// reached no accessibility surface at all, so a VoiceOver user could not tell which of fifteen lessons was
    /// the cursor. Review caught the comment claiming otherwise. Accessibility is a parity requirement.
    static let lessonNextHint: LocalizedStringResource = "component.lesson.hint.next"

    /// The `.p-x` affordance in the lesson player's header. Icon-only, so this is the whole reading (#20).
    ///
    /// A component's own rather than the screen's, for ``closeSheet``'s reason: leaving a lesson is what the control
    /// *is*, and a screen supplying the word would be a screen able to get it wrong.
    static let closeLesson: LocalizedStringResource = "component.lesson.close"

    /// `.mend-goal` — the word in front of the savings meter's far end, `Goal AED 2,000`.
    ///
    /// The component's rather than the screen's, unusually, and the design is why: the meter's whole idea is that
    /// **the bar's far edge *is* the goal**, so the word naming it belongs to the bar. Two screens draw this meter
    /// — Home and a month's detail — and a caller supplying the word would be two callers able to disagree about
    /// what the right-hand end of the same control means. The figure inside it is still the server's.
    static func meterGoal(_ figure: String) -> LocalizedStringResource {
        "component.meter.goal \(figure)"
    }

    /// `#mtag` — the label that travels with the savings meter's pin, `AED 1,120 saved`.
    ///
    /// The component's for ``meterGoal(_:)``'s reason, and one more: the word is what stops the tag being a bare
    /// figure floating over a gradient. The figure inside it is the server's display string, never re-formatted
    /// (ADR-0003).
    static func meterSaved(_ figure: String) -> LocalizedStringResource {
        "component.meter.saved \(figure)"
    }

    /// Every key the components render themselves.
    static let keys = [
        closeSheet.key, inFlight.key, unitGuide.key,
        lessonOpenHint.key, lessonLockedHint.key, lessonNextHint.key,
        closeLesson.key,
        // Taken with a sample argument: the key is the format string, and that is what the catalogue holds.
        meterGoal("").key, meterSaved("").key,
    ]

    /// The hint for one lesson: where to start, what will happen, or why it will not.
    ///
    /// **One table, read by the node on the path and the row in the guide sheet**, so the two cannot come to
    /// disagree about what a press does — the same reason `HWLessonRow.glyph(for:)` is one table.
    static func lessonHint(state: HWLessonNodeState, isNext: Bool) -> LocalizedStringResource {
        switch state {
        case .locked: lessonLockedHint
        case .available, .completed: isNext ? lessonNextHint : lessonOpenHint
        }
    }
}
