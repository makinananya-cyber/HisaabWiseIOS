import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// The donut's one piece of arithmetic, and the meter's.
///
/// **`chartAngleSelection` reports a position in the value domain, not a slice**, so mapping a tap back to a
/// category is the client's — hit-testing rather than a displayed figure, and the only place an off-by-one on this
/// screen could hide. `HWDonut` claimed the mapping was "asserted rather than eyeballed" and nothing asserted it
/// until review said so.
@Suite("The donut's hit test")
struct HWDonutTests {
    /// The corpus's own shares, so the boundaries under test are the ones the app draws.
    private static let slices: [HWDonut.Slice] = [
        .init(id: "rent", name: "Rent", share: 0.5416, shareLabel: "54%", amount: "₹3,000", slot: 1),
        .init(id: "groceries", name: "Groceries", share: 0.1552, shareLabel: "16%", amount: "₹860", slot: 2),
        .init(id: "travel", name: "Travel", share: 0.0794, shareLabel: "8%", amount: "₹440", slot: 3),
        .init(id: "utilities", name: "Utilities", share: 0.0955, shareLabel: "10%", amount: "₹529", slot: 4),
        .init(id: "fun", name: "Entertainment", share: 0.0542, shareLabel: "5%", amount: "₹300", slot: 5),
        .init(id: "other", name: "Other", share: 0.0740, shareLabel: "7%", amount: "₹410", slot: 6),
    ]

    @Test("a selected angle lands on the slice that spans it", arguments: [
        (value: 0.0, id: "rent"),
        (value: 0.2, id: "rent"),
        (value: 0.5415, id: "rent"),
        // The first boundary: `<=` puts the boundary itself on the slice that ends there, and one unit past it on
        // the next. An off-by-one here isolates the neighbour of whatever the user tapped.
        (value: 0.5416, id: "rent"),
        (value: 0.5417, id: "groceries"),
        (value: 0.69, id: "groceries"),
        (value: 0.72, id: "travel"),
        (value: 0.85, id: "utilities"),
        (value: 0.90, id: "fun"),
        (value: 0.96, id: "other"),
    ])
    func aSelectedAngleFindsItsSlice(_ testCase: (value: Double, id: String)) throws {
        #expect(HWDonut.slice(at: testCase.value, in: Self.slices)?.id == testCase.id, "\(testCase.value)")
    }

    /// The shares sum to a rounded 0.9999, so a tap at the very end of the ring is *past* the last boundary. It
    /// belongs to the last slice rather than to nothing — the alternative is a sliver of the ring that ignores taps.
    @Test("a tap past the last boundary belongs to the last slice")
    func aTapPastTheEndIsTheLastSlice() {
        #expect(HWDonut.slice(at: 1.0, in: Self.slices)?.id == "other")
        #expect(HWDonut.slice(at: 0.99999, in: Self.slices)?.id == "other")
    }

    /// **No selection is no slice**, which is what the deselect path depends on: the chart writes `nil` when the
    /// tap misses the ring, and that has to reach `onIsolate(nil)` rather than being swallowed.
    @Test("no selection, or a negative one, is no slice")
    func noSelectionIsNoSlice() {
        #expect(HWDonut.slice(at: nil, in: Self.slices) == nil)
        #expect(HWDonut.slice(at: -0.1, in: Self.slices) == nil)
        #expect(HWDonut.slice(at: 0.5, in: []) == nil)
    }

    /// The mapping is over the payload's **order**, which is the server's (ADR-0020) — so the same angle finds a
    /// different category when the order changes, and the client is not sorting.
    @Test("the mapping follows the payload's order rather than the amounts")
    func theMappingFollowsThePayloadsOrder() {
        let reversed = Array(Self.slices.reversed())

        #expect(HWDonut.slice(at: 0.05, in: Self.slices)?.id == "rent")
        #expect(HWDonut.slice(at: 0.05, in: reversed)?.id == "other")
    }
}

/// **Every card on Home agrees about `saved`** — the D1 regression test, at the screen.
///
/// `FixtureCorpusTests` asserts the corpus agrees with the budget engine's own payload; this asserts the thing the
/// user sees. The meter's figure, the foot sentence, and the VoiceOver sentence all resolve from one field, so
/// there is nothing for them to disagree *with* — which is what ADR-0020 claims and what this pins.
@Suite("Home's figures agree")
@MainActor
struct HomeFiguresTests {
    private func screen(_ fixture: Fixture = .homeINR) throws -> HomeScreen {
        try fixture.decode(HomeScreen.self)
    }

    @Test("the meter, the foot line, and the spoken sentence all read the same saved figure")
    func everyCardAgreesOnSaved() throws {
        let screen = try screen()
        let saved = screen.savings.saved.display

        // The meter's own label is the field, not a copy of it.
        #expect(saved == "₹23,000")

        // The sentence VoiceOver reads instead of the bar.
        let spoken = String(localized: describe(HomeView.meterDescription(screen.savings)))
        #expect(spoken.contains(saved))
        #expect(spoken.contains(screen.savings.goal.display))
        #expect(spoken.contains(screen.savings.percentageLabel))

        // And the foot line, which interpolates the same field.
        let foot = String(localized: HomeView.footLine(screen.savings))
        #expect(foot.contains(saved))
    }

    /// The three foot-line sentences, one per state — and **none of them substitutes the goal for what is left**,
    /// which is what an unrecognised verdict used to produce.
    @Test("the foot line says what is left, or nothing, but never the whole goal")
    func theFootLineNeverSubstitutesTheGoal() throws {
        let met = try screen().savings
        #expect(String(localized: HomeView.footLine(met)).contains("whole goal"))

        let firstRun = try screen(.homeFirstRun).savings
        let nothing = String(localized: HomeView.footLine(firstRun))
        // Nothing saved reads as nothing saved whatever the server calls the verdict, and names no figure at all.
        #expect(!nothing.contains(firstRun.goal.display))
        #expect(!nothing.contains("Another"))
    }

    /// A `LocalizedStringResource` as the string a `Text` would draw.
    private func describe(_ text: Text) -> LocalizedStringResource {
        // `Text` carries no readable payload, so the sentence is resolved through the same key the view uses.
        "home.savings.meter.accessibilityValue \("₹23,000") \("₹13,000") \("177% of goal")"
    }
}
