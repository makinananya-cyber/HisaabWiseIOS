import Observation

/// One view model per tab, made once and handed to the shell.
///
/// Issue #5's criterion is "one view model per tab, created at the composition root and injected via
/// `@Environment`", and this is the object that gets injected. Five of them cannot go into the environment
/// individually — four are the same type today, so they would overwrite each other — and a screen cannot read
/// ``AppEnvironment`` instead, because that holds the `APIClient` and `LayeringTests` keeps the networking
/// layer out of `Views/`.
///
/// **Held, not made.** A `body` that constructed a view model would reset a screen every time the user
/// switched away and back, and the reset would look like a slow network rather than a bug. The lifetime is
/// the app's, which is the lifetime a tab has.
///
/// **Five named properties rather than a dictionary**, so every tab has one by construction and nothing
/// unwraps an optional in a `body`. Each of #18, #19, #21, and #23 changed exactly one property's type, and the
/// pattern held all four times: the property's type changed, it moved into the initialiser because a real view
/// model needs a client, and nothing else in this file did — except the one thing #23 added, below.
///
/// **It is also the app's ``ScreenRepaint``**, and it is the only object that could be: a display-currency or
/// language change makes every *other* screen's figures stale (ADR-0003), and this is the one place that holds
/// all five view models. The conformance is why the account view model is `connect`ed rather than injected —
/// `AppEnvironment` closes the loop exactly as it does for the language manager.
///
/// `Observable` is conformed to by hand rather than through the `@Observable` macro, and that is the honest
/// spelling: every property here is a `let`, so there is nothing for the macro to broadcast. What changes is
/// the *state inside* each view model, and each of those is `@Observable` itself.
@MainActor
final class TabViewModels: Observable, ScreenRepaint {
    let home: HomeViewModel
    let expenses: ExpensesViewModel
    let learn: LearnViewModel
    let reports: ReportsViewModel
    let account: AccountViewModel

    /// - Parameters:
    ///   - home: Home's view model, made by the graph because it needs a client.
    ///   - expenses: Expenses', for the same reason (#18).
    ///   - learn: Learn's, which needs the content loader as well (#19).
    ///   - reports: Reports', which needs only a client — the archive is one read and nothing cacheable (#21).
    ///   - account: Account's (#23). The only one that needs the **language manager** as well, because the picker
    ///     that changes the app's language is on it (ADR-0024) — and the last of the five to stop being built
    ///     here, which is what retired the placeholder.
    init(
        home: HomeViewModel,
        expenses: ExpensesViewModel,
        learn: LearnViewModel,
        reports: ReportsViewModel,
        account: AccountViewModel
    ) {
        self.home = home
        self.expenses = expenses
        self.learn = learn
        self.reports = reports
        self.account = account
    }

    /// Every model, for the assertion that there are as many as there are tabs and that no two tabs share
    /// one. A test that cannot enumerate them can only check the ones it thought to name, which is the
    /// property that would go wrong.
    var everyModel: [AnyObject] { [home, expenses, learn, reports, account] }

    // MARK: - ScreenRepaint

    /// Re-reads the four screens a preference change made stale — **not Account's own**, which came back with the
    /// write that changed it (ADR-0020).
    ///
    /// **One after another, and deliberately not concurrently.** The four reads are independent and four
    /// `async let`s would overlap the waiting — but they would also put four screens into `.loading` at once
    /// behind a tab bar the user is free to tap, and the tab they land on would be the one whose request is
    /// still in flight. Sequential means the screens come back in the order they are listed in the tab bar,
    /// which is the order the reader is most likely to visit them in.
    ///
    /// Nothing here reports anything. `BaseViewModel.load()` is the one owner of turning a failure into a
    /// `LoadState` (ADR-0016), so a screen that could not be re-read says so in the one place a screen says so —
    /// and it says it on the tab the user opens next, which is when they would find out anyway.
    func repaintEveryScreen() async {
        try? await home.load()
        try? await expenses.load()
        try? await learn.load()
        try? await reports.load()
    }
}
