import SwiftUI
@testable import HisaabWise
import Testing

/// ADR-0012's scaling policy, as assertions: **text scales unclamped, and a chart is replaced rather
/// than shrunk.**
///
/// The two halves are asserted separately because they fail separately. That the ceiling and the
/// threshold sit next to each other is a *value* claim — checkable without rendering anything, and the
/// thing most likely to drift when somebody edits one of them. That the alternative is what gets drawn
/// is a *pixel* claim, and only a render can make it.
@Suite("Scaling")
@MainActor
struct ScalingTests {
    /// Stands in for the donut: a shape, which carries no text and so cannot be read at any size.
    private func chart() -> some View {
        Rectangle().frame(width: 160, height: 160)
    }

    /// Stands in for the category list it is replaced by: the same information as words.
    private func alternative() -> some View {
        VStack(alignment: .leading) {
            Text(verbatim: "Rent — 40%")
            Text(verbatim: "Groceries — 25%")
        }
    }

    // MARK: - The policy, as values

    /// The load-bearing relationship between the two numbers in the policy.
    ///
    /// The ceiling is the size a chart may still be *drawn* at; the threshold is where it stops being a
    /// chart. Those have to meet exactly: a gap would leave sizes where the chart is clamped and no
    /// alternative has taken over — which is the shrunk-chart outcome ADR-0012 rules out — and an overlap
    /// would clamp a layout that is already made of text.
    @Test("the ceiling is the largest size at which a chart is still drawn")
    func theCeilingMeetsTheThreshold() {
        let drawn = DynamicTypeSize.allCases.filter { !HWScaling.replacesVisualisation(at: $0) }

        #expect(drawn.max() == HWScaling.visualisationCeiling)
        // And the other side of the join: everything above the ceiling is replaced, nothing below it is.
        #expect(DynamicTypeSize.allCases.filter { $0 > HWScaling.visualisationCeiling }
            .allSatisfy { HWScaling.replacesVisualisation(at: $0) })
    }

    @Test("every accessibility size replaces the visualisation, and no ordinary size does")
    func replacementFollowsTheAccessibilitySizes() {
        for size in DynamicTypeSize.allCases {
            #expect(
                HWScaling.replacesVisualisation(at: size) == size.isAccessibilitySize,
                "\(size) disagrees with the accessibility-size boundary"
            )
        }
    }

    // MARK: - What is actually drawn

    /// The criterion, in pixels: above the threshold the chart is **gone**, not smaller.
    @Test("at an accessibility size the alternative is drawn and the chart is not")
    func theAlternativeReplacesTheChart() throws {
        let pattern = chart().hwVisualisation(replacedBy: alternative)

        let replaced = try #require(TestBench.render(pattern.dynamicTypeSize(.accessibility1))?.pngData())
        let plainAlternative = try #require(
            TestBench.render(alternative().dynamicTypeSize(.accessibility1))?.pngData()
        )

        // Identical to the alternative rendered on its own: nothing of the chart is left behind, and no
        // scaled-down copy of it is drawn alongside.
        #expect(replaced == plainAlternative)
    }

    @Test("below the threshold the chart is what is drawn")
    func theChartSurvivesOrdinarySizes() throws {
        let pattern = chart().hwVisualisation(replacedBy: alternative)

        let drawn = try #require(TestBench.render(pattern.dynamicTypeSize(.large))?.pngData())
        let plainAlternative = try #require(TestBench.render(alternative().dynamicTypeSize(.large))?.pngData())

        #expect(drawn != plainAlternative)
    }

    /// The switch happens at the boundary and nowhere else. Asserted across the whole enum rather than at
    /// the two sizes either side of it, because an off-by-one here is invisible — the layout still looks
    /// reasonable, just at the wrong setting.
    @Test("the swap happens exactly at the accessibility boundary, at every size")
    func theSwapHappensAtTheBoundary() throws {
        let pattern = chart().hwVisualisation(replacedBy: alternative)

        for size in DynamicTypeSize.allCases {
            let drawn = try #require(TestBench.render(pattern.dynamicTypeSize(size))?.pngData())
            let plainAlternative = try #require(TestBench.render(alternative().dynamicTypeSize(size))?.pngData())

            if size.isAccessibilitySize {
                #expect(drawn == plainAlternative, "\(size) still draws the chart")
            } else {
                #expect(drawn != plainAlternative, "\(size) has already given up the chart")
            }
        }
    }

    /// The alternative is a list of text, so it must keep scaling after it takes over. A clamp applied to
    /// the wrong branch would cap the reading layout at the ceiling — the failure ADR-0012 cares most
    /// about, and one that looks like a working replacement.
    @Test("the alternative keeps growing past the ceiling")
    func theAlternativeIsNotClamped() throws {
        let pattern = chart().hwVisualisation(replacedBy: alternative)

        let atThreshold = try #require(TestBench.measure(pattern.dynamicTypeSize(.accessibility1))?.height)
        let atAX5 = try #require(TestBench.measure(pattern.dynamicTypeSize(.accessibility5))?.height)

        #expect(atAX5 > atThreshold)
    }

    /// The chart's own labels still scale up to the ceiling, and the clamp changes nothing on the way
    /// there.
    ///
    /// **The clamp cannot bite while the threshold sits immediately above the ceiling**, and that is the
    /// point of it rather than a hole in it: it states the largest size a chart may be drawn at
    /// independently of where the threshold happens to be, so raising the threshold later cannot silently
    /// un-cap the chart. The join itself is what ``theCeilingMeetsTheThreshold`` pins.
    @Test("a chart's labels scale up to the ceiling, and the clamp alters nothing below it")
    func theChartScalesUpToTheCeiling() throws {
        // A chart with a label in it, since a bare shape would be the same height at every size and could
        // not tell a scaling label from a pinned one.
        let labelled = VStack {
            Rectangle().frame(width: 160, height: 160)
            Text(verbatim: "AED 4,200")
        }
        let pattern = labelled.hwVisualisation(replacedBy: alternative)

        let atDefault = try #require(TestBench.measure(pattern.dynamicTypeSize(.large))?.height)
        let atCeiling = try #require(
            TestBench.measure(pattern.dynamicTypeSize(HWScaling.visualisationCeiling))?.height
        )

        #expect(atCeiling > atDefault)
        // And at the ceiling the pattern draws what the content draws on its own: the clamp is a ceiling,
        // not a cap that quietly changes ordinary rendering.
        #expect(
            TestBench.render(pattern.dynamicTypeSize(HWScaling.visualisationCeiling))?.pngData()
                == TestBench.render(labelled.dynamicTypeSize(HWScaling.visualisationCeiling))?.pngData()
        )
    }
}
