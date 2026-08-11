import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// Landing, and the four claims about it that are not pixels.
///
/// It is the one screen with **no request**, so there is no `LoadState` to assert and no transport to stub.
/// What is left is worth checking precisely: that there are four straplines and the rotation is a cycle, that
/// the [FIX] actually landed, that the copy exists, and that the call to action calls back.
@Suite("Landing")
@MainActor
struct LandingTests {
    // MARK: - The rotation

    @Test("the rotation is a cycle through four straplines")
    func rotationCyclesThroughFour() {
        let viewModel = LandingViewModel()
        #expect(viewModel.straplineCount == 4)
        #expect(viewModel.strapline == 0)

        var seen: [Int] = [viewModel.strapline]
        for _ in 1..<4 {
            viewModel.advance()
            seen.append(viewModel.strapline)
        }

        // All four, in order, and then back to the first: the design's rotation has no end to reach.
        #expect(seen == [0, 1, 2, 3])
        viewModel.advance()
        #expect(viewModel.strapline == 0)
    }

    /// **Nothing advances on its own.** The view's `.task` is what calls `advance()`, which is what makes Reduce
    /// Motion able to suppress the rotation by simply never starting it (ADR-0012) — a view model with a timer
    /// inside would rotate for everybody and leave the view to hide it.
    @Test("the view model holds no clock")
    func theViewModelHoldsNoClock() async throws {
        let viewModel = LandingViewModel()

        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.strapline == 0)
        // Said structurally as well, since the absence of a timer is the property: no sleeping, no scheduling.
        let source = try SourceTree.codeLines(
            of: SourceTree.appSources.appending(path: "ViewModels/LandingViewModel.swift")
        )
        for clock in ["Task.sleep", "Timer", "DispatchQueue", "ContinuousClock", "Date("] {
            #expect(!source.contains { $0.contains(clock) }, "the view model reaches for \(clock)")
        }
    }

    @Test("a degenerate count cannot divide by zero")
    func aDegenerateCountIsClamped() {
        let viewModel = LandingViewModel(straplineCount: 0)

        #expect(viewModel.straplineCount == 1)
        viewModel.advance()
        #expect(viewModel.strapline == 0)
    }

    /// The view's list and the view model's count are two numbers that have to agree: four sentences rotating
    /// through five slots would show an empty pill one time in five.
    @Test("the screen has as many sentences as the rotation has slots")
    func theSentencesMatchTheCount() throws {
        let straplines = try Self.straplineKeys()

        #expect(straplines.count == LandingViewModel().straplineCount)
        #expect(Set(straplines).count == straplines.count, "two slots show the same sentence")
    }

    // MARK: - The copy, and the [FIX]

    @Test("every key Landing renders has English copy")
    func copyExists() throws {
        try CatalogueCopy.expectEnglishCopy(forKeys: try Self.straplineKeys() + [
            "landing.headline.first",
            "landing.headline.second",
            "landing.cta",
            "landing.free",
            "landing.hero.accessibilityLabel",
            "landing.strapline.accessibilityLabel",
        ])
    }

    /// **Product Spec §3.1's [FIX].** The design's first strapline is "Every rupee, tracked without thinking
    /// about it." — and the app displays whatever currency the user is paid in, formatted by the server
    /// (ADR-0003), so naming one in the copy is wrong for everybody it is not. The replacement is
    /// currency-neutral, and this is what stops the original coming back in a translation pass.
    @Test("no strapline names a currency")
    func noStraplineNamesACurrency() throws {
        let currencies = ["rupee", "rupees", "dirham", "dirhams", "AED", "INR", "₹", "$", "dollar"]

        for key in try Self.straplineKeys() {
            let english = try #require(CatalogueCopy.english(in: try CatalogueCopy.entry(key)))
            for currency in currencies {
                #expect(
                    !english.localizedCaseInsensitiveContains(currency),
                    "\(key) says \(currency): the app shows the user's own currency, not one the copy picked"
                )
            }
        }
    }

    // MARK: - The call to action

    @Test("Get Started calls back rather than deciding where to go")
    func theCallToActionCallsBack() throws {
        var started = 0
        let landing = LandingView(viewModel: LandingViewModel()) { started += 1 }

        // The closure is the seam: the screen holds no route, so the root can send it anywhere (#14).
        landing.onGetStarted()

        #expect(started == 1)
    }

    /// **The double-length half of the pseudolanguage harness** (ADR-0011), which the RTL preview does not
    /// cover: doubled copy has to make the screen *taller* rather than being cut off. `ShellLocalisationTests`
    /// asserts this for the shared placeholders; Landing has the longest copy in the app.
    @Test("doubled copy makes the pill taller rather than clipping")
    func doubledCopyWraps() throws {
        // The pill's own shape — a bordered box with a leading dot — at single and at doubled length, measured
        // the way the harness measures: a doubled sentence that comes back the same height was truncated.
        let single = try #require(CatalogueCopy.english(in: try CatalogueCopy.entry("landing.strapline.1")))
        let doubled = "\(single) \(single)"

        let short = TestBench.measure(Self.pill(single))
        let long = TestBench.measure(Self.pill(doubled))

        let shortHeight = try #require(short?.height)
        let longHeight = try #require(long?.height)
        #expect(longHeight > shortHeight)
        // And no wider: copy that grew sideways has escaped the phone rather than wrapped.
        #expect(short?.width == long?.width)
    }

    /// The strapline's own shape, so the measurement is of the thing that has to wrap rather than of a screen
    /// whose spacers would absorb the difference.
    @MainActor
    private static func pill(_ sentence: String) -> some View {
        HStack(spacing: 12) {
            Circle().frame(width: 7, height: 7)
            Text(verbatim: sentence)
                .font(.hw(.bodyLarge))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 334, minHeight: 58)
    }

    @Test("it renders")
    func itRenders() {
        #expect(TestBench.render(LandingView(viewModel: LandingViewModel(), onGetStarted: {})) != nil)
    }

    /// The screen is not a ``BaseView`` and must not become one: it has nothing to load, so a `LoadState`
    /// would be four states no request can produce (issue #13).
    @Test("Landing has no load state and no request")
    func landingHasNoLoadState() throws {
        let view = try SourceTree.codeLines(
            of: SourceTree.appSources.appending(path: "Views/LandingView.swift")
        )
        let viewModel = try SourceTree.codeLines(
            of: SourceTree.appSources.appending(path: "ViewModels/LandingViewModel.swift")
        )

        #expect(!view.contains { $0.contains(": BaseView") })
        #expect(!viewModel.contains { $0.contains("BaseViewModel") })
        #expect(!viewModel.contains { $0.contains("fetch()") })
        #expect(!viewModel.contains { $0.contains("LoadState") })
    }

    // MARK: - The entrance stagger

    /// The design's six delays, transcribed rather than computed — `0`, `.12`, `.30`, `.52`, `.76`, `.98`. They
    /// accelerate, so a formula would flatten the effect.
    @Test("the stagger is the design's six delays, and it holds past the last one")
    func theStaggerIsTheDesignsDelays() {
        let delays = (0..<6).map { HWEntrance.staggerDelay(step: $0) }

        #expect(delays == [0, 0.12, 0.30, 0.52, 0.76, 0.98])
        // Strictly increasing, which is what makes it a stagger rather than six things arriving together.
        #expect(zip(delays, delays.dropFirst()).allSatisfy { $0 < $1 })
        // A seventh band holds at the last delay instead of arriving later still.
        #expect(HWEntrance.staggerDelay(step: 9) == 0.98)
        #expect(HWEntrance.staggerDelay(step: -1) == 0)
    }

    /// Every strapline key the screen lists, read from its source so the test cannot drift from the array.
    private static func straplineKeys() throws -> [String] {
        try SourceTree.codeLines(of: SourceTree.appSources.appending(path: "Views/LandingView.swift"))
            .compactMap { line in
                guard let match = line.firstMatch(of: try! Regex(#"\"(landing\.strapline\.\d+)\""#)) else {
                    return nil
                }
                return match[1].substring.map(String.init)
            }
    }
}
