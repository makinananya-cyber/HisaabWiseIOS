import Foundation

/// Every other screen has to be read again.
///
/// **The display currency and the language are the two settings that change what every screen says**, and
/// neither changes it on the client. Money is converted *and formatted* server-side (ADR-0003) and every figure
/// on every screen arrives as a `display` string, so a screen that was read in rupees is a screen full of rupee
/// strings until it is read again. The same is true of a language: `Accept-Language` is what decided the wording
/// and the number formatting of every payload already in hand.
///
/// So a preference change is a **re-read of the app**, not a re-render of it. Account's own screen comes back
/// with the write (ADR-0020); this is the other four.
///
/// **A protocol in `Models` rather than a closure the graph passes in**, for the reason `LanguageSink` is one:
/// it points the dependency downwards. `AccountViewModel` needs the other four view models and lives beside
/// them, so a concrete reference either way round would be a cycle; `TabViewModels` is the one object that holds
/// all five, so it is the conformance, and `AppEnvironment` closes the loop with one `connect(to:)` call exactly
/// as it does for the language manager.
///
/// It is **not a second seam** (ADR-0013): the only conformance is the real `TabViewModels`, in the app and in
/// the tests alike.
@MainActor
protocol ScreenRepaint: AnyObject {
    /// Re-reads every screen whose figures were formatted in the preference that has just changed.
    ///
    /// Non-throwing and reporting nothing: each screen maps its own failure to its own `LoadState` through
    /// `BaseViewModel.load()`, which is the one owner of that mapping (ADR-0016). A repaint that "failed" is four
    /// screens each saying so in the one place a screen says so.
    func repaintEveryScreen() async
}
