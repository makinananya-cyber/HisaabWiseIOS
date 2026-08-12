import Foundation
@testable import HisaabWise
import Testing

/// The size and shape of the snapshot set — which is a decision, not a host-dependent fact.
///
/// Separate from `SnapshotSuiteTests` because that suite skips on any host but the pinned one (`SnapshotPin`),
/// and "there are exactly four" has nothing to do with which simulator is running. A rule that only holds on
/// one machine is a rule nobody is held to.
@Suite("The snapshot set")
struct SnapshotCaseTests {
    /// ADR-0013's number, as an assertion: "the snapshot suite stays deliberately small and pinned. An
    /// unpinned or sprawling snapshot suite goes flaky, and a flaky gate gets deleted rather than fixed."
    /// A fifth case is a decision somebody makes on purpose, not a file somebody adds.
    @Test("there are exactly four snapshot cases")
    func exactlyFourCases() {
        #expect(SnapshotCase.allCases.count == 4)
        // And they are the four kinds the ADR names, not four of one kind.
        #expect(SnapshotCase.allCases.map(\.rawValue).sorted()
            == ["home-arabic", "home-ax3", "home-populated", "reports-empty"])
    }

    @Test("no two cases would write to the same baseline")
    func namesAreDistinct() {
        // The raw value is the baseline's filename once the library lands, so two cases sharing one would
        // silently compare the wrong picture — and the second would overwrite the first on a re-record.
        #expect(Set(SnapshotCase.allCases.map(\.rawValue)).count == SnapshotCase.allCases.count)
    }

    /// Exactly one case can be photographed as it will appear without a hosted capture, and it is the empty
    /// one. Recorded as an assertion because it is the fact that decides how much the current suite can claim.
    @Test("three of the four draw a fetched screen")
    func threeCasesNeedAHostedCapture() {
        #expect(SnapshotCase.allCases.count { $0.drawsAFetchedScreen } == 3)
        #expect(!SnapshotCase.empty.drawsAFetchedScreen)
    }
}
