import SwiftUI
@testable import HisaabWise
import Testing

/// ADR-0012's motion rule, as assertions: **Reduce Motion replaces, it never removes.**
///
/// `accessibilityReduceMotion` is read-only, so no test can put the app into that state and photograph
/// the result. What can be asserted is the decision itself, which is why the arrival of a view is a
/// *value* here rather than a ternary at each call site: `HWEntrance` is what a screen picks, and its
/// reduced form is what a screen gets. A `nil`, a `.identity`, or an entrance that reduced to nothing at
/// all would fail here rather than in a review.
@Suite("Reduce Motion")
struct ReducedMotionTests {
    /// The whole vocabulary. Checked against `Kind` so that a fourth entrance cannot be added without
    /// arriving in the list every assertion below iterates.
    @Test("the vocabulary is complete")
    func everyKindHasAnEntrance() {
        #expect(HWEntrance.all.count == HWEntrance.Kind.allCases.count)
        #expect(Set(HWEntrance.all.map(\.kind)) == Set(HWEntrance.Kind.allCases))
    }

    /// The criterion. Every arrival still *arrives* under Reduce Motion — as a cross-fade, which is a
    /// change a motion-sensitive user can see and a sighted user cannot miss.
    @Test("every entrance reduces to a cross-fade rather than to nothing")
    func everyEntranceReducesToAFade() {
        for entrance in HWEntrance.all {
            #expect(entrance.reduced.kind == .fade, "\(entrance.kind) reduces to \(entrance.reduced.kind)")
        }
    }

    /// The case that would be easiest to get wrong by being clever: a fade is already the reduced form, so
    /// reducing it must leave it alone rather than removing the last of the feedback.
    @Test("a cross-fade is not itself removed")
    func aFadeSurvivesReduction() {
        #expect(HWEntrance.fade.reduced == HWEntrance.fade)
    }

    /// The movement is replaced; its **timing** is not. A toast that took 420ms to arrive still takes
    /// 420ms, so the event reads as the same event at the same pace.
    @Test("reduction changes how a view arrives, not how long it takes")
    func reductionPreservesTiming() {
        for entrance in HWEntrance.all {
            #expect(entrance.reduced.duration == entrance.duration, "\(entrance.kind) changed pace")
        }
    }

    /// An overshoot is the one curve Reduce Motion is unambiguously about — the thing that goes past its
    /// destination and comes back. No reduced form may use one.
    @Test("no reduced form overshoots")
    func reducedFormsDoNotOvershoot() {
        #expect(HWEntrance.pop.curve.overshoots, "the vocabulary no longer contains a curve worth reducing")

        for entrance in HWEntrance.all {
            #expect(!entrance.reduced.curve.overshoots, "\(entrance.kind) still overshoots when reduced")
        }
    }

    /// Resolution is the call site's one decision, and it is the identity when the user has asked for
    /// nothing. An entrance that changed under `false` would mean every screen animated the reduced form
    /// for everybody.
    @Test("resolving with motion allowed changes nothing")
    func resolvingWithoutReductionIsTheIdentity() {
        for entrance in HWEntrance.all {
            #expect(entrance.resolved(reduceMotion: false) == entrance)
            #expect(entrance.resolved(reduceMotion: true) == entrance.reduced)
        }
    }

    /// And the two that carry movement do change, which is what stops this suite from passing on a policy
    /// that quietly did nothing.
    @Test("the entrances that move are genuinely different when reduced")
    func movingEntrancesAreReplaced() {
        #expect(HWEntrance.rise.reduced != HWEntrance.rise)
        #expect(HWEntrance.pop.reduced != HWEntrance.pop)
    }

    /// The worked example ADR-0012 asks for, asserted where it is: the toast picks `rise`, so its arrival
    /// is the policy's rather than a ternary of its own.
    @Test("the toast's arrival comes from the vocabulary")
    func theToastUsesTheVocabulary() throws {
        let source = try String(
            contentsOf: SourceTree.appSources.appending(path: "Components/HWToast.swift"),
            encoding: .utf8
        )

        #expect(source.contains("HWEntrance"))
        #expect(source.contains("accessibilityReduceMotion"))
    }
}
