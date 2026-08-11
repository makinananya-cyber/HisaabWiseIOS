import Observation

/// Which strapline is showing, and nothing else.
///
/// **The one view model in the app with no `fetch()`** and no ``LoadState``, which is issue #13's criterion
/// rather than an omission: Landing makes no request, so there is nothing to be loading, empty, offline, or
/// failed about. It is therefore *not* a ``BaseViewModel`` conformance — that protocol's whole content is one
/// request and the mapping of its outcome, and a conformance that returned a constant would be a screen
/// pretending to have a server.
///
/// **It holds an index, not the words.** The four straplines are copy, and copy lives in the presentation
/// layer where `LocalisationTests` looks for it — a String Catalogue key held in `ViewModels/` would read as
/// an orphaned entry to the scan that checks nothing is left behind. So this owns the rotation and
/// ``LandingView`` owns the sentences.
///
/// **It does not own the clock.** `advance()` is called by the view's `.task`, so the rotation is testable
/// without waiting 3.8 seconds and Reduce Motion suppresses it by simply never starting — see ADR-0012 on why
/// this is the one animation that is *removed* rather than replaced.
@MainActor
@Observable
final class LandingViewModel {
    /// How many straplines the screen rotates through. The design has four; `LandingView` supplies exactly
    /// that many sentences and `LandingTests` asserts the two agree.
    let straplineCount: Int

    /// Which one is showing, `0 ..< straplineCount`.
    private(set) var strapline = 0

    init(straplineCount: Int = 4) {
        // A count of zero would make `advance()` divide by zero, and a screen with no strapline is not a state
        // the design has. Clamped rather than trapped: this is a preview and test seam, not a user input.
        self.straplineCount = max(1, straplineCount)
    }

    /// The next strapline, wrapping. The design's rotation is a cycle, so there is no end to reach and no
    /// "seen them all" state to keep.
    func advance() {
        strapline = (strapline + 1) % straplineCount
    }
}
