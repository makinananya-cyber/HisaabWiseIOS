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
/// unwraps an optional in a `body`. Each of #18, #19, #21, and #23 changes exactly one property's type — three
/// have, and the pattern held all three times: the property's type changed, it moved into the initialiser
/// because a real view model needs a client, and nothing else in this file did.
///
/// `Observable` is conformed to by hand rather than through the `@Observable` macro, and that is the honest
/// spelling: every property here is a `let`, so there is nothing for the macro to broadcast. What changes is
/// the *state inside* each view model, and each of those is `@Observable` itself.
@MainActor
final class TabViewModels: Observable {
    let home: HomeViewModel
    let expenses: ExpensesViewModel
    let learn: LearnViewModel
    let reports: ReportsViewModel
    let account: UnwrittenScreenViewModel

    /// - Parameters:
    ///   - home: Home's view model, made by the graph because it needs a client.
    ///   - expenses: Expenses', for the same reason (#18).
    ///   - learn: Learn's, which needs the content loader as well (#19).
    ///   - reports: Reports', which needs only a client — the archive is one read and nothing cacheable (#21).
    ///     Account is still built here because there is nothing to configure about it yet.
    init(
        home: HomeViewModel,
        expenses: ExpensesViewModel,
        learn: LearnViewModel,
        reports: ReportsViewModel
    ) {
        self.home = home
        self.expenses = expenses
        self.learn = learn
        self.reports = reports
        account = UnwrittenScreenViewModel()
    }

    /// Every model, for the assertion that there are as many as there are tabs and that no two tabs share
    /// one. A test that cannot enumerate them can only check the ones it thought to name, which is the
    /// property that would go wrong.
    var everyModel: [AnyObject] { [home, expenses, learn, reports, account] }
}
