import SwiftUI
@testable import HisaabWise
import Testing

/// The four-segment split bar: what it draws, and **what it stands aside for** above the accessibility threshold.
///
/// The second is the screen's own criterion (#22) and the only one a render can make: ADR-0012 requires the bar to
/// be *replaced* by a labelled list rather than shrunk, and the list it is replaced by is the key that is already
/// drawn under it — the call ``HWDonut`` makes for the same reason.
@Suite("HWSplitBar")
@MainActor
struct HWSplitBarTests {
    private static func segments(widths: [Double]) -> [HWSplitBar.Segment] {
        zip(HWSplitPortion.allCases, widths).map { portion, width in
            HWSplitBar.Segment(
                portion: portion,
                name: "reports.detail.split.needs",
                amount: "₹47,740",
                target: portion == .surplus ? nil : Text(verbatim: "aim ₹32,500"),
                width: width
            )
        }
    }

    private static func bar(widths: [Double] = [0.7345, 0.0835, 0.182, 0]) -> HWSplitBar {
        HWSplitBar(
            segments: segments(widths: widths),
            accessibilityLabel: "reports.detail.split.accessibilityLabel"
        )
    }

    /// **Four parts, because §4.2 [FIX] says four** — and the design's "left unspent" is not one of them.
    @Test("the portions are the four the budget rule settles on")
    func thereAreFourPortions() {
        #expect(HWSplitPortion.allCases.count == 4)
        #expect(HWSplitPortion.allCases == [.needs, .wants, .saved, .surplus])
    }

    @Test("the bar renders with a surplus and without one")
    func theBarRenders() {
        #expect(TestBench.render(Self.bar()) != nil)
        #expect(TestBench.render(Self.bar(widths: [0, 0, 0.2, 0.8])) != nil)
    }

    /// **Above the threshold the bar is gone, not smaller**, and the key rows are what remain (ADR-0012).
    ///
    /// Asserted by drawing the same component with every part at zero width: if the bar were still on screen the
    /// two pictures would differ, because one would carry four coloured parts and the other none. At an ordinary
    /// size they *do* differ, which is what stops this passing vacuously.
    @Test("the bar stands aside at accessibility sizes and is drawn below them")
    func theBarIsReplacedAboveTheThreshold() throws {
        let drawn = Self.bar()
        let empty = Self.bar(widths: [0, 0, 0, 0])

        for size in DynamicTypeSize.allCases {
            let withParts = try #require(TestBench.render(drawn.dynamicTypeSize(size))?.pngData())
            let withNone = try #require(TestBench.render(empty.dynamicTypeSize(size))?.pngData())

            if size.isAccessibilitySize {
                #expect(withParts == withNone, "\(size) still draws the bar")
            } else {
                #expect(withParts != withNone, "\(size) has already given up the bar")
            }
        }
    }

    /// And the list keeps growing after it takes over, because it is made of text.
    @Test("the labelled list scales past the threshold")
    func theListKeepsScaling() throws {
        let atThreshold = try #require(TestBench.measure(Self.bar().dynamicTypeSize(.accessibility1))?.height)
        let atAX5 = try #require(TestBench.measure(Self.bar().dynamicTypeSize(.accessibility5))?.height)

        #expect(atAX5 > atThreshold)
    }

    /// A share outside `0...1` is clamped rather than drawn: the number arrives from a payload, and a part drawn at
    /// 1.4 would run outside the card. Asserted through the picture, since the clamp is inside a `GeometryReader`.
    @Test("a share past the end of the track is clamped")
    func aSharePastTheEndIsClamped() throws {
        let clamped = try #require(TestBench.render(Self.bar(widths: [1, 0, 0, 0]))?.pngData())
        let beyond = try #require(TestBench.render(Self.bar(widths: [4, 0, 0, 0]))?.pngData())

        #expect(clamped == beyond)
    }
}
