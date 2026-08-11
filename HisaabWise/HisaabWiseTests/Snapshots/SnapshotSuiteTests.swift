import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// The snapshot harness: the four cases, the pinned host, and the one thing still missing.
///
/// **`swift-snapshot-testing` is not in the project yet, and it cannot be added from here.** Xcode 26 rejects a
/// hand-written package reference in `project.pbxproj` — every class in the family (`XCRemoteSwiftPackageReference`,
/// `XCLocalSwiftPackageReference`, `XCSwiftPackageProductDependency`) fails the project parse with
/// `-[XCRemoteSwiftPackageReference _setOwner:]: unrecognized selector`, at any `objectVersion`. Adding a package
/// is a GUI step (File ▸ Add Package Dependencies…), which the workspace rules say to flag rather than work
/// around. Issue #9 records the exact steps.
///
/// So what is here is the harness minus the comparison: **which four views**, on **which device and runtime**,
/// and a render of each so that a case whose view stopped building fails now rather than on the day the baselines
/// arrive. When the package lands, the loop below gains one line — `assertSnapshot(of: snapshotCase.view(), as:
/// .image(...))` — and nothing else about this file changes.
///
/// **Two reasons the library is required rather than preferred**, both already visible from here. Three of the
/// four cases draw a screen whose figures arrive from a request, and `ImageRenderer` captures the spinner rather
/// than the figures — a *hosted* capture is what waits for the load. And a baseline comparison needs perceptual
/// diffing, device traits, and a re-record mode, which is the part ADR-0013 says not to hand-roll.
@Suite("The pinned snapshot harness", .enabled(Comment(rawValue: SnapshotPin.reason)) { SnapshotPin.matchesHost })
@MainActor
struct SnapshotSuiteTests {
    /// Every case builds and draws something. **Not a baseline, and not a distinction**: three of the four draw
    /// a fetched screen, so an unhosted capture photographs the same spinner for all three — removing
    /// `.dynamicTypeSize(.accessibility3)` from a case would still pass this. What it does catch is a case
    /// naming a view that has been renamed, or missing an environment object, between now and the day the
    /// baselines arrive.
    @Test("every case builds and draws something", arguments: SnapshotCase.allCases)
    func everyCaseRenders(_ snapshotCase: SnapshotCase) throws {
        #expect(TestBench.render(snapshotCase.view()) != nil, "\(snapshotCase.rawValue) did not render")
    }

    /// The empty case is the one that can be photographed as it will appear, because it has no request to wait
    /// for — so it is the one case whose pixels are worth asserting anything about today.
    ///
    /// Compared against the **populated** case, which today renders as its spinner: two cases that came out
    /// identical would mean the empty one is drawing a spinner too, and that is the way this could quietly be
    /// wrong. Written from the enum rather than by rebuilding a `StateView` here, so the thing under test is
    /// the case the baseline will use.
    @Test("the empty case draws the empty state rather than a spinner")
    func theEmptyCaseIsAlreadyItself() throws {
        let empty = try #require(TestBench.render(SnapshotCase.empty.view())?.pngData())
        let spinner = try #require(TestBench.render(SnapshotCase.populated.view())?.pngData())

        #expect(empty != spinner)
    }

    /// The skip message is the only thing a developer on another host will read, so it has to name both halves
    /// of the pin and the way to satisfy them. Asserting `hostDevice == device` here would be a tautology —
    /// the suite trait is that comparison.
    @Test("the skip message names the pin and how to meet it")
    func theSkipMessageIsUseful() {
        #expect(SnapshotPin.reason.contains(SnapshotPin.device))
        #expect(SnapshotPin.reason.contains("\(SnapshotPin.runtime.major).\(SnapshotPin.runtime.minor)"))
        #expect(SnapshotPin.reason.contains("-destination"))
    }
}
