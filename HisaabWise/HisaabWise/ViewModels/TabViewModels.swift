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
/// unwraps an optional in a `body`. Each of #18, #19, #21, and #23 changes exactly one property's type.
///
/// `Observable` is conformed to by hand rather than through the `@Observable` macro, and that is the honest
/// spelling: every property here is a `let`, so there is nothing for the macro to broadcast. What changes is
/// the *state inside* each view model, and each of those is `@Observable` itself.
@MainActor
final class TabViewModels: Observable {
    let home: HomeViewModel
    let expenses: UnwrittenScreenViewModel
    let learn: UnwrittenScreenViewModel
    let reports: UnwrittenScreenViewModel
    let account: UnwrittenScreenViewModel

    /// - Parameter home: the one screen that exists, so the one that needs a client. The other four are
    ///   built here because there is nothing to configure about them yet.
    init(home: HomeViewModel) {
        self.home = home
        expenses = UnwrittenScreenViewModel()
        learn = UnwrittenScreenViewModel()
        reports = UnwrittenScreenViewModel()
        account = UnwrittenScreenViewModel()
    }

    /// Every model, for the assertion that there are as many as there are tabs and that no two tabs share
    /// one. A test that cannot enumerate them can only check the ones it thought to name, which is the
    /// property that would go wrong.
    var everyModel: [AnyObject] { [home, expenses, learn, reports, account] }
}
